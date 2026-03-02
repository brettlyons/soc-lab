# Findings & Decisions — SOC Lab (aurora)

## Requirements
- OPNsense firewall VM — controls all inter-segment traffic, logs to Wazuh
- Wazuh SIEM/XDR (single-node)
- Splunk Enterprise (log analysis, secondary SIEM)
- Windows Active Directory Domain Controller (lab.local)
- Windows host joined to domain
- Linux VM sending logs to Wazuh and Splunk
- Kali Linux VM — attack/Red Team platform (needs real NIC, not Distrobox)
- Sandbox VM — isolated host for phone-home/malware analysis scenarios
- All running locally on `aurora` via KVM/virt-manager
- Blue Team / SOC investigation focus

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
  virbr0 (NAT → internet)
      │
[fw-router — Alpine Linux + nftables + Suricata]
  eth0 → WAN (virbr0)
  eth1 → lab-net      192.168.10.0/24   (all lab VMs — full NAT internet)
  eth2 → lab-sandbox  192.168.40.0/24   (sandbox only — WAN BLOCKED)
```

> **Design rationale:** Flat lab-net for all attack/defend VMs. Kali needs full internet
> for VPN to training sites (HackTheBox, TryHackMe, etc.) and free access to targets
> for detection tuning. Only the sandbox is genuinely isolated (blocks real C2 callbacks).

## Virtual Networks

| Name | Subnet | Bridge | Gateway | Purpose |
|------|--------|--------|---------|---------|
| WAN | NAT via virbr0 | virbr0 | DHCP | Router uplink only |
| lab-net | 192.168.10.0/24 | virbr-net | 192.168.10.1 (fw) | All lab VMs, full internet |
| lab-sandbox | 192.168.40.0/24 | virbr-sandbox | 192.168.40.1 (fw) | Sandbox, no internet |

## IP Assignments

| VM | lab-net (10) | lab-sandbox (40) | Notes |
|---|---|---|---|
| fw-router | 192.168.10.1 | 192.168.40.1 | Alpine, nftables, Suricata |
| Wazuh | 192.168.10.10 | 192.168.40.10 | NIC on both to reach sandbox agent |
| Splunk | 192.168.10.40 | — | |
| DC01 | 192.168.10.20 | — | |
| Windows host | 192.168.10.30 | — | |
| Linux sender | 192.168.10.50 | — | |
| Kali | 192.168.10.60 | — | Full internet + VPN to HTB/THM etc. |
| Sandbox | — | 192.168.40.50 | No internet, Wazuh agent only |

## Firewall Rules (nftables)

| Source | Destination | Action | Reason |
|---|---|---|---|
| lab-net | WAN | ALLOW (NAT/masquerade) | Internet for all lab VMs incl. Kali VPN |
| lab-sandbox | lab-net (Wazuh 40.10) | ALLOW | Wazuh agent traffic only |
| lab-sandbox | WAN | BLOCK | No real internet from sandbox |
| lab-sandbox | lab-net (other) | BLOCK | Isolate from lab VMs |
| WAN | lab-net | BLOCK (default) | No unsolicited inbound |

## VM Roster

| VM | OS | RAM | vCPU | Disk | NICs |
|---|---|---|---|---|---|
| fw-router | Alpine 3.23 | 512MB | 1 | 4GB | WAN + lab-net + lab-sandbox |
| Wazuh | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | lab-net, lab-sandbox |
| Splunk | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | lab-net |
| DC01 | Windows Server 2022 | 4GB | 2 | 60GB | lab-net |
| Windows host | Windows 10/11 | 4GB | 2 | 60GB | lab-net |
| Linux sender | Ubuntu 24.04 LTS | 2GB | 2 | 40GB | lab-net |
| Kali | Kali Linux (qcow2) | 4GB | 2 | 60GB | lab-net |
| Sandbox | TBD | 4GB | 2 | 60GB | lab-sandbox |
| **Total** | | **34.5GB** | **19** | **444GB*** | |

*qcow2 thin-provisioned — actual initial disk usage ~80–120GB

## Install Methods

### Firewall Router (Alpine Linux + nftables)
> Replaced OPNsense. Simpler, scriptable, ~512MB RAM / 4GB disk.
- Alpine Linux Virtual ISO (amd64): https://alpinelinux.org/downloads/
- 5 NICs: WAN (virbr0/NAT) + lab-soc + lab-domain + lab-attack + lab-sandbox
- IP forwarding: `echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf`
- nftables rules file: `/etc/nftables.nft` — same policy as original OPNsense plan
- Syslog to Wazuh: rsyslog UDP 514 → 192.168.10.10

### Wazuh
- Ubuntu 24.04 base install → Wazuh all-in-one script
- `curl -sO https://packages.wazuh.com/4.x/wazuh-install.sh && bash wazuh-install.sh -a`
- Dashboard on port 443

### Splunk
- Ubuntu 24.04 base → Splunk Enterprise .deb (free account required)
- Web UI port 8000, UF receiver port 9997

### Windows Server 2022 / Windows 10/11
- Microsoft Evaluation Center ISOs (180-day free, no license)
- VirtIO drivers ISO for better KVM performance

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

## Issues Encountered
| Issue | Resolution |
|-------|------------|
| virbr0 stale bridge — blocks new network creation | Pending: sudo ip link delete virbr0 |
| sudo requires interactive auth in Claude terminal session | Pending: configure passwordless sudo |
