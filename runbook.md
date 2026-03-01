# SOC Lab Runbook — aurora

> **Purpose:** Step-by-step commands and commentary for building and operating the local SOC lab.
> All VMs run on `aurora` (Aurora OS 43, KVM/virt-manager).
> Intended as both an operational reference and a portfolio writeup.

---

## Lab Architecture

```
[aurora host — NAT uplink (virbr0)]
              |
        [OPNsense FW VM]
              |
    ┌─────────┼──────────┬──────────────┐
    │         │          │              │
lab-soc   lab-domain  lab-attack   lab-sandbox
192.168.10  192.168.20  192.168.30   192.168.40
    │         │          │              │
Wazuh       DC01        Kali        Sandbox
Splunk    Win-host                 (no internet)
          Linux-sender
```

### VM Summary

| VM | OS | IP(s) | Role |
|---|---|---|---|
| OPNsense | OPNsense (FreeBSD) | .10.1 / .20.1 / .30.1 / .40.1 | Firewall, inter-segment routing |
| Wazuh | Ubuntu 24.04 | 192.168.10.10 / 192.168.40.10 | SIEM/XDR, agent collector |
| Splunk | Ubuntu 24.04 | 192.168.10.40 | Log analysis, secondary SIEM |
| DC01 | Windows Server 2022 | 192.168.20.20 | AD Domain Controller (lab.local) |
| Windows host | Windows 10/11 | 192.168.20.30 | Domain-joined endpoint |
| Linux sender | Ubuntu 24.04 | 192.168.20.50 | Log source (Wazuh agent + Splunk UF) |
| Kali | Kali Linux | 192.168.30.10 / 192.168.20.60 | Attack platform |
| Sandbox | TBD | 192.168.40.50 | Isolated phone-home/malware host |

---

## Phase 1: Host Preparation

### 1.1 Configure Passwordless Sudo

Required for bridge and network interface management without interactive auth.
Run in a terminal on aurora (one-time, requires current sudo auth):

```bash
echo 'blyons ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/blyons-nopasswd
sudo chmod 440 /etc/sudoers.d/blyons-nopasswd

# Verify
sudo -l | grep NOPASSWD
```

### 1.2 Clear Stale Bridge and Fix Default Network

libvirtd left a stale virbr0 interface on a previous run. Clear it so libvirt
can manage bridge creation cleanly:

```bash
sudo ip link delete virbr0 2>/dev/null || true

# Restart libvirtd to pick up clean state
sudo systemctl restart libvirtd

# Start the default network (virbr0 will be recreated cleanly)
virsh net-start default
virsh net-autostart default
```

### 1.3 Create Lab Virtual Networks

Four isolated networks — one per segment. OPNsense will be the gateway on each.

```bash
# Write all 4 network definitions
for net in \
  "lab-soc|virbr-soc|192.168.10.1" \
  "lab-domain|virbr-domain|192.168.20.1" \
  "lab-attack|virbr-attack|192.168.30.1" \
  "lab-sandbox|virbr-sandbox|192.168.40.1"; do
  IFS='|' read -r name bridge ip <<< "$net"
  cat > /tmp/${name}.xml << EOF
<network>
  <name>${name}</name>
  <forward mode='nat'/>
  <bridge name='${bridge}' stp='on' delay='0'/>
  <ip address='${ip}' netmask='255.255.255.0'/>
</network>
EOF
  virsh net-define /tmp/${name}.xml
  virsh net-start ${name}
  virsh net-autostart ${name}
  echo "Created: ${name}"
done

# Verify all networks
virsh net-list --all
```

> **Note:** NAT is enabled on all networks initially so VMs can reach the internet
> for updates and installs. Once OPNsense is up, we'll handle routing through it
> and adjust the lab-sandbox network to drop internet access at the firewall level.

### 1.4 Create Storage Pool

```bash
sudo mkdir -p /var/lib/libvirt/images/soc-lab
sudo chown root:libvirt /var/lib/libvirt/images/soc-lab
sudo chmod 771 /var/lib/libvirt/images/soc-lab

virsh pool-define-as soc-lab dir --target /var/lib/libvirt/images/soc-lab
virsh pool-start soc-lab
virsh pool-autostart soc-lab

# Verify
virsh pool-list --all
```

### 1.5 Download ISOs

```bash
mkdir -p ~/workspace/soc-lab/isos
cd ~/workspace/soc-lab/isos

# Ubuntu 24.04 LTS Server (used for Wazuh, Splunk, Linux sender)
wget https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso

# OPNsense (check https://opnsense.org/download/ for current version)
wget https://mirror.ams1.nl.leaseweb.net/opnsense/releases/25.1/OPNsense-26.1.2-dvd-amd64.iso.bz2
bzip2 -d OPNsense-26.1.2-dvd-amd64.iso.bz2

# Kali Linux (check https://www.kali.org/get-kali/ for current version)
wget https://cdimage.kali.org/kali-2025.4/kali-linux-2025.4-installer-amd64.iso

# VirtIO drivers for Windows VMs
wget https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso

# Windows Server 2022 and Windows 10/11:
# Download manually from https://www.microsoft.com/en-us/evalcenter/
# (requires browser + free Microsoft account)
# Save to ~/workspace/soc-lab/isos/
```

---

## Phase 2: OPNsense Firewall

### 2.1 Create OPNsense VM

OPNsense needs 5 NICs: 1 WAN (NAT uplink) + 4 lab segments.

```bash
virt-install \
  --name opnsense \
  --ram 2048 \
  --vcpus 2 \
  --disk pool=soc-lab,size=20,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/OPNsense-26.1.2-dvd-amd64.iso \
  --network network=default,model=virtio \
  --network network=lab-soc,model=virtio \
  --network network=lab-domain,model=virtio \
  --network network=lab-attack,model=virtio \
  --network network=lab-sandbox,model=virtio \
  --os-variant freebsd14.0 \
  --graphics spice \
  --video qxl \
  --boot cdrom,hd
```

> NIC order matters — OPNsense will assign them as vtnet0–vtnet4.
> vtnet0 = WAN (default/NAT), vtnet1–4 = lab segments.

### 2.2 OPNsense Initial Setup

During install, select:
- Install (not Live)
- UFS or ZFS (ZFS recommended for snapshots)
- Set root password

After first boot, at the console:
1. Assign interfaces:
   - WAN → vtnet0
   - LAN → vtnet1 (lab-soc, 192.168.10.1/24)
   - OPT1 → vtnet2 (lab-domain, 192.168.20.1/24)
   - OPT2 → vtnet3 (lab-attack, 192.168.30.1/24)
   - OPT3 → vtnet4 (lab-sandbox, 192.168.40.1/24)

2. Set interface IPs via console menu option 2.

Access web UI: `http://192.168.10.1` from the Wazuh/SOC segment
Default credentials: admin / opnsense

### 2.3 Configure Interfaces (Web UI)

Interfaces → [each OPT interface] → Enable, set description and static IP.

| Interface | Description | IP | DHCP |
|---|---|---|---|
| vtnet0 | WAN | DHCP from virbr0 | Yes |
| vtnet1 | SOC | 192.168.10.1/24 | No |
| vtnet2 | DOMAIN | 192.168.20.1/24 | No |
| vtnet3 | ATTACK | 192.168.30.1/24 | No |
| vtnet4 | SANDBOX | 192.168.40.1/24 | No |

### 2.4 Firewall Rules (Web UI: Firewall → Rules)

**DOMAIN rules (traffic from lab-domain):**
```
Allow  DOMAIN → SOC 192.168.10.10 port 1514    # Wazuh agent
Allow  DOMAIN → SOC 192.168.10.10 port 1515    # Wazuh enrollment
Allow  DOMAIN → SOC 192.168.10.40 port 9997    # Splunk UF
Allow  DOMAIN → WAN any                         # Internet for updates
Block  DOMAIN → SANDBOX any                     # Isolate sandbox
```

**ATTACK rules (traffic from lab-attack):**
```
Allow  ATTACK → DOMAIN any                      # Kali → AD targets
Allow  ATTACK → SOC 192.168.10.10 any          # Optional: Kali → Wazuh
Allow  ATTACK → WAN any                         # Internet for tool updates
Block  ATTACK → SANDBOX any                     # Don't allow Kali → sandbox
```

**SANDBOX rules (traffic from lab-sandbox):**
```
Allow  SANDBOX → SOC 192.168.40.10 port 1514   # Wazuh agent (Wazuh's sandbox NIC)
Allow  SANDBOX → SOC 192.168.40.10 port 1515   # Wazuh enrollment
Block  SANDBOX → WAN any                        # *** NO REAL INTERNET ***
Block  SANDBOX → DOMAIN any                     # Isolate from AD
Block  SANDBOX → ATTACK any                     # Isolate from Kali
```

### 2.5 Configure Syslog → Wazuh

System → Log Files → Remote:
- Enable Remote Logging: Yes
- Remote syslog servers: `192.168.10.10` port 514 UDP
- Log everything (or select: Firewall Events, System Events)

---

## Phase 3: Wazuh Server

### 3.1 Create Wazuh VM

```bash
virt-install \
  --name wazuh \
  --ram 8192 \
  --vcpus 4 \
  --disk pool=soc-lab,size=80,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/ubuntu-24.04.4-live-server-amd64.iso \
  --network network=lab-soc,model=virtio \
  --network network=lab-sandbox,model=virtio \
  --os-variant ubuntu24.04 \
  --graphics spice \
  --console pty,target_type=serial
```

During Ubuntu install:
- Hostname: `wazuh`
- User: `labadmin`
- Primary NIC (lab-soc): static `192.168.10.10/24`, gateway `192.168.10.1`, DNS `8.8.8.8`
- Secondary NIC (lab-sandbox): static `192.168.40.10/24`, no gateway
- Install OpenSSH: yes

### 3.2 Install Wazuh (All-in-One)

```bash
ssh labadmin@192.168.10.10

sudo apt update && sudo apt upgrade -y

# Download installer and config
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh


# Edit config.yml — single-node: all IPs set to 127.0.0.1
# nodes.wazuh_indexer[0].ip  = 127.0.0.1
# nodes.wazuh_server[0].ip   = 127.0.0.1
# nodes.wazuh_dashboard[0].ip = 127.0.0.1

sudo bash wazuh-install.sh -a
# Record admin password from output — also saved to wazuh-passwords.tar.gz
```

Dashboard: `https://192.168.10.10` — user: `admin`

### 3.3 Enable Syslog Receiver

```bash
sudo nano /var/ossec/etc/ossec.conf

# Add inside <ossec_config>:
# <remote>
#   <connection>syslog</connection>
#   <port>514</port>
#   <protocol>udp</protocol>
#   <allowed-ips>192.168.0.0/16</allowed-ips>
# </remote>

sudo systemctl restart wazuh-manager

# Verify listening
sudo ss -ulnp | grep 514
```

### 3.4 Verify

```bash
sudo systemctl status wazuh-manager wazuh-indexer wazuh-dashboard
sudo /var/ossec/bin/wazuh-control status
```

---

## Phase 4: Splunk

### 4.1 Create Splunk VM

```bash
virt-install \
  --name splunk \
  --ram 8192 \
  --vcpus 4 \
  --disk pool=soc-lab,size=80,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/ubuntu-24.04.4-live-server-amd64.iso \
  --network network=lab-soc,model=virtio \
  --network network=lab-domain,model=virtio \
  --os-variant ubuntu24.04 \
  --graphics spice
```

During install:
- Hostname: `splunk`
- Primary NIC (lab-soc): static `192.168.10.40/24`, gateway `192.168.10.1`
- Secondary NIC (lab-domain): static `192.168.20.40/24`, no gateway

### 4.2 Install Splunk Enterprise

```bash
ssh labadmin@192.168.10.40

sudo apt update && sudo apt upgrade -y

# Download from https://www.splunk.com/en_us/download/splunk-enterprise.html
# (requires free Splunk account — get .deb link)
wget -O splunk.deb '<paste-download-url>'
sudo dpkg -i splunk.deb

sudo /opt/splunk/bin/splunk start --accept-license --answer-yes \
  --no-prompt --seed-passwd 'REDACTED'

sudo /opt/splunk/bin/splunk enable boot-start -systemd-managed 1 -user splunk

# Enable receiving from Universal Forwarders
sudo /opt/splunk/bin/splunk enable listen 9997 -auth admin:'REDACTED'
```

Web UI: `http://192.168.10.40:8000` — user: `admin`

---

## Phase 5: Windows Domain Controller

### 5.1 Create DC VM

```bash
virt-install \
  --name dc01 \
  --ram 4096 \
  --vcpus 2 \
  --disk pool=soc-lab,size=60,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/WinServer2022_eval.iso \
  --disk ~/workspace/soc-lab/isos/virtio-win.iso,device=cdrom \
  --network network=lab-domain,model=virtio \
  --os-variant win2k22 \
  --graphics spice \
  --video qxl
```

> Load VirtIO storage driver from the virtio-win ISO during Windows install
> (Browse to virtio-win CD → amd64 → w11 or w10 → vioscsi.inf)

### 5.2 Configure DC

In PowerShell (run as Administrator):

```powershell
# Rename computer
Rename-Computer -NewName "DC01" -Restart

# After reboot — set static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.20.20 `
  -PrefixLength 24 -DefaultGateway 192.168.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
  -ServerAddresses 127.0.0.1, 8.8.8.8

# Install AD DS
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# Promote to Domain Controller
Install-ADDSForest `
  -DomainName "lab.local" `
  -DomainNetbiosName "LAB" `
  -InstallDns `
  -SafeModeAdministratorPassword (ConvertTo-SecureString 'REDACTED' -AsPlainText -Force) `
  -Force
# Reboots automatically
```

### 5.3 Create Lab Users

```powershell
# After DC promotion, create a standard domain user
New-ADUser -Name "Lab User" -GivenName "Lab" -Surname "User" `
  -SamAccountName "labuser" -UserPrincipalName "labuser@lab.local" `
  -AccountPassword (ConvertTo-SecureString 'REDACTED' -AsPlainText -Force) `
  -Enabled $true

# Create a domain admin for lab management
New-ADUser -Name "Lab Admin" -SamAccountName "labadmin" `
  -AccountPassword (ConvertTo-SecureString 'REDACTED' -AsPlainText -Force) `
  -Enabled $true
Add-ADGroupMember -Identity "Domain Admins" -Members "labadmin"
```

---

## Phase 6: Windows Host

### 6.1 Create Windows Client VM

```bash
virt-install \
  --name win-host \
  --ram 4096 \
  --vcpus 2 \
  --disk pool=soc-lab,size=60,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/Windows10_eval.iso \
  --disk ~/workspace/soc-lab/isos/virtio-win.iso,device=cdrom \
  --network network=lab-domain,model=virtio \
  --os-variant win10 \
  --graphics spice \
  --video qxl
```

### 6.2 Join Domain and Install Agents

```powershell
# Set static IP
New-NetIPAddress -InterfaceAlias "Ethernet" -IPAddress 192.168.20.30 `
  -PrefixLength 24 -DefaultGateway 192.168.20.1
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" `
  -ServerAddresses 192.168.20.20

# Join domain
Add-Computer -DomainName "lab.local" `
  -Credential (Get-Credential LAB\labadmin) -Restart

# After reboot — install Wazuh agent (get current MSI URL from docs)
Invoke-WebRequest -Uri "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.x.x-1.msi" `
  -OutFile "wazuh-agent.msi"
msiexec /i wazuh-agent.msi /q `
  WAZUH_MANAGER="192.168.10.10" `
  WAZUH_AGENT_NAME="win-host"
NET START WazuhSvc

# Install Splunk Universal Forwarder
# Download MSI from https://www.splunk.com/en_us/download/universal-forwarder.html
msiexec /i splunkforwarder.msi /q `
  SPLUNKUSERNAME=admin `
  SPLUNKPASSWORD="REDACTED" `
  RECEIVING_INDEXER="192.168.10.40:9997"
```

---

## Phase 7: Linux Log Sender

### 7.1 Create VM

```bash
virt-install \
  --name linux-sender \
  --ram 2048 \
  --vcpus 2 \
  --disk pool=soc-lab,size=40,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/ubuntu-24.04.4-live-server-amd64.iso \
  --network network=lab-domain,model=virtio \
  --os-variant ubuntu24.04 \
  --graphics spice
```

Install with:
- Hostname: `linux-sender`
- Static IP: `192.168.20.50/24`, gateway `192.168.20.1`, DNS `192.168.20.20`

### 7.2 Install Wazuh Agent

```bash
ssh labadmin@192.168.20.50

curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
  https://packages.wazuh.com/4.x/apt/ stable main" \
  | sudo tee /etc/apt/sources.list.d/wazuh.list

sudo apt update
sudo WAZUH_MANAGER='192.168.10.10' apt install wazuh-agent -y

sudo systemctl daemon-reload
sudo systemctl enable --now wazuh-agent
```

### 7.3 Install Splunk Universal Forwarder

```bash
# Download .deb from https://www.splunk.com/en_us/download/universal-forwarder.html
wget -O splunkuf.deb '<paste-download-url>'
sudo dpkg -i splunkuf.deb

sudo /opt/splunkforwarder/bin/splunk start --accept-license --answer-yes \
  --no-prompt --seed-passwd 'REDACTED'
sudo /opt/splunkforwarder/bin/splunk enable boot-start -systemd-managed 1

sudo /opt/splunkforwarder/bin/splunk add forward-server 192.168.10.40:9997 \
  -auth admin:'REDACTED'

sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/syslog -index main
sudo /opt/splunkforwarder/bin/splunk add monitor /var/log/auth.log -index main

sudo systemctl restart SplunkForwarder
```

---

## Phase 8: Kali Linux

### 8.1 Create Kali VM

Kali gets two NICs: attack segment (primary) + domain segment (for AD attack scenarios).

```bash
virt-install \
  --name kali \
  --ram 4096 \
  --vcpus 2 \
  --disk pool=soc-lab,size=60,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/kali-linux-2025.4-installer-amd64.iso \
  --network network=lab-attack,model=virtio \
  --network network=lab-domain,model=virtio \
  --os-variant debiantesting \
  --graphics spice \
  --video qxl
```

During install:
- Primary NIC (lab-attack): static `192.168.30.10/24`, gateway `192.168.30.1`
- Secondary NIC (lab-domain): static `192.168.20.60/24`, no gateway

### 8.2 Post-Install

```bash
sudo apt update && sudo apt full-upgrade -y

# Confirm key tools present
nmap --version
msfconsole --version 2>/dev/null || echo "install: sudo apt install metasploit-framework"
impacket-secretsdump --help 2>/dev/null || echo "install: sudo apt install python3-impacket"

# Optional: Wazuh agent on Kali (track your own attack activity in Wazuh)
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH \
  | sudo gpg --dearmor -o /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] \
  https://packages.wazuh.com/4.x/apt/ stable main" \
  | sudo tee /etc/apt/sources.list.d/wazuh.list
sudo apt update
sudo WAZUH_MANAGER='192.168.10.10' apt install wazuh-agent -y
sudo systemctl enable --now wazuh-agent
```

---

## Phase 9: Sandbox VM

### 9.1 Create Sandbox VM

OS TBD — Windows for malware analysis, Linux for C2 callback testing.
Example using Windows 10:

```bash
virt-install \
  --name sandbox \
  --ram 4096 \
  --vcpus 2 \
  --disk pool=soc-lab,size=60,format=qcow2,bus=virtio \
  --cdrom ~/workspace/soc-lab/isos/Windows10_eval.iso \
  --disk ~/workspace/soc-lab/isos/virtio-win.iso,device=cdrom \
  --network network=lab-sandbox,model=virtio \
  --os-variant win10 \
  --graphics spice \
  --video qxl
```

Static IP: `192.168.40.50/24`, gateway `192.168.40.1` (OPNsense — will block internet)

### 9.2 Snapshot Baseline

```bash
# Take baseline snapshot before any analysis activity
virsh snapshot-create-as sandbox sandbox-baseline "Clean install — pre-analysis"
virsh snapshot-list sandbox

# Revert to clean state between scenarios
virsh snapshot-revert sandbox sandbox-baseline
```

### 9.3 Install Wazuh Agent

All sandbox activity gets captured by Wazuh for analysis:

**Windows:**
```powershell
msiexec /i wazuh-agent.msi /q `
  WAZUH_MANAGER="192.168.40.10" `
  WAZUH_AGENT_NAME="sandbox"
NET START WazuhSvc
```

**Linux:**
```bash
sudo WAZUH_MANAGER='192.168.40.10' apt install wazuh-agent -y
sudo systemctl enable --now wazuh-agent
```

> Wazuh's sandbox NIC (192.168.40.10) receives agent traffic.
> OPNsense allows sandbox → 192.168.40.10 ports 1514/1515 only.

---

## Phase 10: Integration & Validation

### Verify All Wazuh Agents

```bash
# On wazuh VM
sudo /var/ossec/bin/agent_control -l
# Expected: dc01, win-host, linux-sender, kali (optional), sandbox
```

### Verify Splunk Receiving

```bash
# In Splunk web UI: http://192.168.10.40:8000
# Search: index=main | stats count by host
# Expected: linux-sender, win-host (UF installed)
```

### Test Firewall — Sandbox Internet Block

```bash
# On sandbox VM — should FAIL
ping 8.8.8.8
curl -I https://google.com

# On Kali — should SUCCEED
ping 8.8.8.8
```

### Generate Test Events (Blue Team Exercise)

```bash
# From Kali — brute force SSH on linux-sender
hydra -l labadmin -P /usr/share/wordlists/rockyou.txt \
  ssh://192.168.20.50 -t 4

# Watch Wazuh dashboard for: "Multiple authentication failures" alert
# Watch Splunk: index=main source="/var/log/auth.log" "Failed password"
# Watch OPNsense logs: Firewall → Log Files → Live View
```

---

## VM Management Reference

```bash
# List all VMs
virsh list --all

# Start / stop
virsh start <name>
virsh shutdown <name>
virsh destroy <name>       # force off

# Snapshots
virsh snapshot-create-as <name> <snap-name> "Description"
virsh snapshot-list <name>
virsh snapshot-revert <name> <snap-name>

# Clone
virt-clone --original <name> --name <new-name> --auto-clone

# Console access
virsh console <name>       # serial console (if configured)
virt-manager               # GUI — open VM display
```

---

*Last updated: 2026-03-01*
*Machine: aurora | OS: Aurora 43 (Universal Blue / Fedora Kinoite)*
