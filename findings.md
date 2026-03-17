# Findings & Decisions — SOC Lab (aurora)

## Requirements
- Alpine Linux + nftables firewall — controls inter-segment traffic, runs Suricata + dnsmasq
- Wazuh SIEM/XDR (single-node, all-in-one)
- Splunk Enterprise (secondary SIEM / log analysis platform)
- Windows Active Directory Domain Controller (lab.local)
- Two Windows 11 user workstations joined to domain (victims for attack scenarios)
- Windows 11 forensic workstation (analyst machine, separate from domain users)
- Linux VM — log sender, web server, CSRF/watering hole target
- Kali Linux VM — Red Team attack platform (full lab-net access + internet for VPN)
- Sandbox VM — isolated for phone-home/malware analysis
- All running locally on `aurora` via KVM/virt-manager
- BHIS Home Lab checklist as guiding framework
- Blue Team / SOC investigation + detection engineering focus

## Host Environment
- **Hostname:** aurora
- **OS:** Aurora 43 (Universal Blue, Fedora Kinoite / KDE) — NOT Bazzite
- **Hypervisor:** QEMU/KVM + virt-manager (already installed)
- **AMD-V:** Enabled (confirmed via lscpu)
- **RAM:** 54GB total; ~50GB available at idle
- **Storage:** 930GB NVMe; ~356GB free (LUKS encrypted, qcow2 thin-provisioned)
- **Previous homelab:** Proxmox-based, now offline, being dismantled
  - Configs archived: `/home/blyons/backups/desktop/homecore-ops/workspace/homelab/`

## Network Topology

```
[aurora host]
      │
  virbr0 (NAT → internet)           192.168.122.0/24
      │
[fw-router — Alpine Linux + nftables + Suricata + dnsmasq]
  eth0 → WAN (virbr0)               192.168.122.10
  eth1 → lab-net                    192.168.10.1/24
  eth2 → lab-sandbox  (NIC REMOVED — disabled until Phase 10)
      │
  lab-net (virbr-lab bridge)        192.168.10.0/24
  ├── Wazuh SIEM          .10
  ├── DC01                .20
  ├── win-user01          .30   ← domain workstation (victim)
  ├── win-user02          .31   ← domain workstation (victim)
  ├── Splunk              .40
  ├── win-forensic        .50   ← analyst/forensic workstation
  ├── Linux sender        .51   ← log sender + web server
  └── Kali                .60   ← Red Team attack platform
```

> **Design rationale:** Flat lab-net for all attack/defend VMs. Kali needs full internet
> for VPN to training sites (HackTheBox, TryHackMe, etc.) and free access to targets
> for detection tuning. Only the sandbox is genuinely isolated (blocks real C2 callbacks).
>
> **eth2 / lab-sandbox:** NIC removed from fw-router due to a libvirt bug that prevented
> lab-sandbox from starting alongside the default network. Will be re-added in Phase 10.

## Virtual Networks

| Name | Subnet | Bridge | Gateway | Purpose |
|------|--------|--------|---------|---------|
| WAN | NAT via virbr0 | virbr0 | DHCP | Router uplink only |
| lab-net | 192.168.10.0/24 | virbr-net | 192.168.10.1 (fw) | All lab VMs, full internet |
| lab-sandbox | 192.168.40.0/24 | virbr-sandbox | 192.168.40.1 (fw) | Sandbox, no internet |

## IP Assignments

| VM | IP | MAC (lab-net) | Status | Notes |
|---|---|---|---|---|
| fw-router | 192.168.10.1 | 52:54:00:6f:f8:de | ✓ running | Alpine, nftables, Suricata, dnsmasq |
| Wazuh | 192.168.10.10 | 52:54:00:99:10:49 | ✓ running | SIEM/XDR, dashboard https://192.168.10.10 |
| DC01 | 192.168.10.20 | — | pending | Windows Server 2022, AD lab.local |
| win-user01 | 192.168.10.30 | 52:54:00:32:ec:6f | installing | Win11 workstation, labadmin, domain victim |
| win-user02 | 192.168.10.31 | 52:54:00:bd:25:da | installing | Win11 workstation, labadmin, domain victim |
| Splunk | 192.168.10.40 | 52:54:00:18:01:10 | ✓ running | Web UI http://192.168.10.40:8000 |
| win-forensic | 192.168.10.50 | 52:54:00:e2:4c:3f | shut off | Win11, analyst account, forensic tools |
| Linux sender | 192.168.10.51 | — | pending | Ubuntu, log sender + Apache web server |
| Kali | 192.168.10.60 | 52:54:00:d8:c1:0b | ✓ running | Red Team, full internet + VPN. Login: kali/kali |
| Sandbox | 192.168.40.50 | — | pending | lab-sandbox only, no internet |

> fw-router WAN IP (virbr0): 192.168.122.10 (fixed via libvirt DHCP reservation)

## Firewall Rules (nftables)

Ruleset: `scripts/fw-router/nftables.nft` — deploy with `scripts/fw-router/nftables-deploy.sh`

> Note: eth2 rules removed — lab-sandbox NIC was removed from fw-router (libvirt bug).
> Sandbox rules will be re-added in Phase 10.

| Chain | Interface | Rule | Reason |
|---|---|---|---|
| input | eth0 (WAN) | ALLOW TCP 22 from 192.168.122.0/24 | SSH management from host |
| input | eth0 (WAN) | ALLOW UDP/TCP 53 from 192.168.122.0/24 | DNS queries from host |
| input | eth1 (lab-net) | ALLOW all | Lab VMs can reach fw-router services |
| forward | eth1→eth0 | ALLOW all | lab-net → internet (NAT) |
| forward | eth0→eth1 | ALLOW from 192.168.122.0/24 | Host → lab-net pass-through |
| nat postrouting | eth0 | MASQUERADE | NAT for lab-net internet access |
| (default) | — | DROP | All other traffic blocked |

## VM Roster

| VM | OS | RAM | vCPU | Disk | IP | Status |
|---|---|---|---|---|---|---|
| fw-router | Alpine 3.23 | 1GB | 1 | 4GB | .1 | ✓ running |
| Wazuh | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | .10 | ✓ running |
| DC01 | Windows Server 2022 | 4GB | 2 | 60GB | .20 | pending ISO |
| win-user01 | Windows 11 Pro | 4GB | 2 | 60GB | .30 | installing |
| win-user02 | Windows 11 Pro | 4GB | 2 | 60GB | .31 | installing |
| Splunk | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | .40 | ✓ running |
| win-forensic | Windows 11 Pro | 4GB | 2 | 60GB | .50 | shut off |
| Linux sender | Ubuntu 24.04 LTS | 2GB | 2 | 40GB | .51 | pending |
| Kali | Kali Linux (qcow2) | 4GB | 2 | 15GB | .60 | ✓ running |
| Sandbox | TBD | 4GB | 2 | 60GB | .40.50 | pending |
| **Total** | | **42.5GB** | **23** | **504GB** | | |

qcow2 thin-provisioned — actual initial disk usage ~80–120GB

## Install Methods

### Firewall Router (Alpine Linux + nftables + dnsmasq)
> Replaced OPNsense. Simpler, fully scriptable, ~1GB RAM / 4GB disk.
- Alpine Linux 3.23.3 Virtual ISO (SHA256 verified)
- 2 active NICs: WAN (virbr0/NAT) + lab-net (eth1). eth2/lab-sandbox NIC removed (Phase 10).
- IP forwarding: `net.ipv4.ip_forward=1` in `/etc/sysctl.conf`
- nftables ruleset: `scripts/fw-router/nftables.nft` → deploy: `scripts/fw-router/nftables-deploy.sh`
- Suricata 8.x (Tier 1 NIDS) on eth1, ET Open rules, EVE JSON → rsyslog → Wazuh + Splunk
- dnsmasq: DNS (lab.local zone) + DHCP (192.168.10.100–200) on eth1
  - Also listens on eth0 (192.168.122.10) for host DNS queries
  - Config: `scripts/fw-router/dnsmasq.conf` → deploy: `scripts/fw-router/dnsmasq-setup.sh`
- rsyslog forwards Suricata EVE → Wazuh TCP :514 (facility local3) + Splunk TCP :5514

### Wazuh
- Ubuntu 24.04 base install → Wazuh all-in-one script
- `curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh && bash wazuh-install.sh -a`
- Dashboard on port 443

### Splunk
- Ubuntu 24.04 base → Splunk Enterprise .deb (free account required)
- Web UI port 8000, UF receiver port 9997

### Windows Build Pipeline
All Windows VMs use unattended install ISOs built from templates + `pass` credentials.
No passwords are stored in git — placeholders are substituted at build time.

| VM | Build dir | pass key | Hostname | Local user |
|---|---|---|---|---|
| win-forensic | `win11-forensic/` | `soc-lab/windows-analyst` | WIN-FORENSIC | analyst (admin) |
| win-user01 | `win11-workstation/` | `soc-lab/windows-workstation` | WIN-USER01 | labadmin (admin) |
| win-user02 | `win11-workstation/` | `soc-lab/windows-workstation` | WIN-USER02 | labadmin (admin) |
| DC01 | `win-server-2022/` | `soc-lab/dc01-admin` | DC01 | Administrator |

Build command:
- Workstations: `bash win11-workstation/build-iso.sh <HOSTNAME> ~/Downloads/Win11_25H2_English_x64.iso`
- DC01: `bash win-server-2022/build-iso.sh ~/Downloads/WindowsServer2022*.iso` (eval ISO required)

DC01 Autounattend does full unattended AD DS install + `Install-ADDSForest -DomainName lab.local` — triggers automatic reboot to complete DC promotion.

VirtIO driver paths: Win11 uses `w11/amd64`, Server 2022 uses `w2k22/amd64`.

**DNS architecture once DC01 is up:**

DC01 is authoritative for `lab.local` and *must* be the primary DNS for domain-joined clients —
AD Kerberos, Group Policy, and domain join all depend on the DC's SRV records
(`_ldap._tcp.lab.local`, `_kerberos._tcp.lab.local`, etc.) which dnsmasq cannot serve.

```
Domain-joined VMs  →  DNS: 192.168.10.20 (DC01)   →  DC01 forwards unknown to 192.168.10.1
Non-domain VMs     →  DNS: 192.168.10.1  (dnsmasq) →  forwards to 1.1.1.1/8.8.8.8
aurora host        →  DNS: 192.168.122.10 (dnsmasq) →  lab.local stub zone only
```

Actions when DC01 is ready:
1. Set DC01's DNS forwarder to `192.168.10.1` (Conditional Forwarders → `.` → 192.168.10.1)
2. Set domain-joined VMs' DNS to `192.168.10.20` (handled by DHCP option 6 update or GPO)
3. dnsmasq can optionally remove its `lab.local` A records — DC01 is now authoritative
4. Non-domain VMs keep using dnsmasq unchanged

### Kali
- Kali bare ISO: https://www.kali.org/get-kali/#kali-installer-images
- Or Kali VM image (pre-built): https://www.kali.org/get-kali/#kali-virtual-machines

### Sandbox
- OS TBD based on scenario (Windows for malware analysis, Linux for C2 callbacks)
- Snapshot baseline immediately after install — revert between scenarios

## Blockers / Prerequisites
- **Passwordless sudo:** Required for bridge interface management
  - Fix: `echo 'blyons ALL=(ALL) NOPASSWD: ALL' | sudo tee /etc/sudoers.d/blyons-nopasswd && sudo chmod 440 /etc/sudoers.d/blyons-nopasswd`
- **Stale virbr0:** Must be cleared before libvirt can create lab networks
  - Fix: `sudo ip link delete virbr0` then re-start default network

## Resources
- OPNsense: https://opnsense.org/download/
- Wazuh all-in-one: https://documentation.wazuh.com/current/installation-guide/
- Wazuh agent (Linux): https://documentation.wazuh.com/current/installation-guide/wazuh-agent/
- Wazuh agent (Windows): https://documentation.wazuh.com/current/installation-guide/wazuh-agent/wazuh-agent-package-windows.html
- Splunk Enterprise: https://www.splunk.com/en_us/download/splunk-enterprise.html
- Splunk UF: https://www.splunk.com/en_us/download/universal-forwarder.html
- Windows evals: https://www.microsoft.com/en-us/evalcenter/
- VirtIO drivers: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
- Kali ISO: https://www.kali.org/get-kali/#kali-installer-images
- Previous Proxmox notes: `/home/blyons/backups/desktop/homecore-ops/workspace/homelab/notes.md`

## Access Reference

### SSH

| Host | User | Key | Notes |
|------|------|-----|-------|
| fw-router (192.168.122.10) | root | `~/.ssh/fw-router-key` | Fixed IP via libvirt DHCP reservation |
| Wazuh (192.168.10.10) | labadmin | `~/.ssh/id_ed25519` | Ubuntu, passwordless sudo |
| Splunk (192.168.10.40) | labadmin | `~/.ssh/id_ed25519` | Ubuntu, passwordless sudo |

### RDP (Windows VMs)

Use `bash scripts/rdp.sh` — fzf picker, pulls passwords from pass store automatically.

| VM | IP | User | pass key |
|----|-----|------|----------|
| win-forensic | 192.168.10.50 | analyst | `soc-lab/windows-analyst` |
| win-user01 | 192.168.10.30 | labadmin | `soc-lab/windows-workstation` |
| win-user02 | 192.168.10.31 | labadmin | `soc-lab/windows-workstation` |
| DC01 | 192.168.10.20 | Administrator | `soc-lab/dc01-admin` |

### Web UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| Wazuh dashboard | https://192.168.10.10 | admin / see `~/wazuh-install-files.tar` on Wazuh VM |
| Splunk | http://192.168.10.40:8000 | admin / `pass soc-lab/splunk-admin` |

## Detection Architecture (Phase 3b — complete)

### Tier 1 — Perimeter NIDS (fw-router)
- **Suricata 8.0.3** (Alpine edge/community) on `eth1` (lab-net)
- ET Open rules (~48k enabled), community-id enabled
- EVE JSON → `/var/log/suricata/eve.json`
- **rsyslog** tails eve.json → Wazuh TCP syslog port 514 (facility: local3)
- Source IP seen by Wazuh: `192.168.10.1` (fw-router eth1)
- Deploy: `scripts/fw-router/suricata-setup.sh` (run on fw-router as root)

### Tier 2 — Internal NIDS (aurora host)
- **Suricata** in Podman container (`jasonish/suricata:latest`) on `virbr-lab`
- ET Open rules (~48k enabled), community-id enabled
- EVE JSON → `/var/log/suricata/internal/eve.json`
- **rsyslog** in Podman container (`rsyslog/syslog_appliance_alpine:latest`)
- Forwards eve.json → Wazuh TCP syslog port 514 (facility: local4)
- Source IP seen by Wazuh: `192.168.122.1` (aurora virbr0 gateway)
- Quadlet units: `/etc/containers/systemd/suricata-internal.container`, `rsyslog-suricata.container`
- Deploy: `scripts/host-setup/suricata-internal-setup.sh` (run as root on aurora)

### Wazuh syslog receiver config
- Added `<remote>` syslog stanza to `/var/ossec/etc/ossec.conf`
- Allows: `192.168.10.1` (Tier 1) and `192.168.122.1` (Tier 2)
- Template stanza: `scripts/host-setup/suricata-internal/wazuh-ossec-syslog-stanza.xml`

### Splunk EVE forwarding (Phase 5 — complete)
- rsyslog on fw-router (Tier 1) dual-forwards: Wazuh TCP :514 AND Splunk TCP :5514
- rsyslog container on aurora (Tier 2) same dual-forward pattern
- Splunk index: `suricata`, sourcetype: `suricata:eve`, TCP input port 5514
- props.conf: `KV_MODE = json` — auto-extracts all EVE fields
- transforms.conf: regex `^[^{]*(\{.+\})$` strips syslog header, leaving clean JSON as `_raw`
- Configs: `scripts/fw-router/50-suricata-wazuh.conf`, `scripts/host-setup/suricata-internal/rsyslog.conf`
- Splunk app configs on VM: `/opt/splunk/etc/apps/search/local/props.conf` + `transforms.conf`

### Note on Aurora OS and package installation
- Aurora is image-based (Universal Blue / rpm-ostree). Layering packages is a last resort
  as it breaks the clean image update chain (would require a custom base image).
- All host-side services run as Podman containers with Quadlet systemd units instead.
- No Wazuh agent on aurora — syslog forwarding handles log shipping.

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| virbr0 stale bridge — blocks new network creation | Pending: sudo ip link delete virbr0 |
| sudo requires interactive auth in Claude terminal session | Pending: configure passwordless sudo |
