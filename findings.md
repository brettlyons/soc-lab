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

## Virtual Networks

| VLAN | Name | Subnet | Bridge | Gateway | Purpose |
|------|------|--------|--------|---------|---------|
| — | WAN | NAT via virbr0 | virbr0 | DHCP | OPNsense uplink only |
| 10 | lab-soc | 192.168.10.0/24 | virbr-soc | 192.168.10.1 (OPN) | SOC tools |
| 20 | lab-domain | 192.168.20.0/24 | virbr-domain | 192.168.20.1 (OPN) | AD domain + log sources |
| 30 | lab-attack | 192.168.30.0/24 | virbr-attack | 192.168.30.1 (OPN) | Kali attack platform |
| 40 | lab-sandbox | 192.168.40.0/24 | virbr-sandbox | 192.168.40.1 (OPN) | Isolated sandbox |

## IP Assignments

| VM | lab-soc (10) | lab-domain (20) | lab-attack (30) | lab-sandbox (40) |
|---|---|---|---|---|
| OPNsense | 192.168.10.1 | 192.168.20.1 | 192.168.30.1 | 192.168.40.1 |
| Wazuh | 192.168.10.10 | — | — | 192.168.40.10* |
| Splunk | 192.168.10.40 | — | — | — |
| DC01 | — | 192.168.20.20 | — | — |
| Windows host | — | 192.168.20.30 | — | — |
| Linux sender | — | 192.168.20.50 | — | — |
| Kali | — | 192.168.20.60* | 192.168.30.10 | — |
| Sandbox | — | — | — | 192.168.40.50 |

*Wazuh gets a NIC in lab-sandbox to receive agent traffic from the sandbox VM
*Kali gets an optional NIC in lab-domain for attack scenario access to the AD environment

## Firewall Rules (OPNsense)

| Source | Destination | Action | Reason |
|---|---|---|---|
| lab-domain | lab-soc (Wazuh 10.10, Splunk 10.40) | ALLOW | Agent/log forwarding |
| lab-attack | lab-domain | ALLOW | Kali → AD attack scenarios |
| lab-attack | lab-soc (Wazuh 10.10) | ALLOW | Optional: Kali agent reporting |
| lab-sandbox | lab-soc (Wazuh 40.10) | ALLOW | Wazuh agent only |
| lab-sandbox | WAN (internet) | BLOCK | Prevent real phone-home |
| lab-sandbox | lab-domain | BLOCK | Isolate from AD |
| lab-sandbox | lab-attack | BLOCK | Isolate from Kali |
| Any | Any | BLOCK (default) | Deny all else |

## VM Roster

| VM | OS | RAM | vCPU | Disk | NICs |
|---|---|---|---|---|---|
| OPNsense | OPNsense (FreeBSD) | 2GB | 2 | 20GB | WAN + 4× lab |
| Wazuh | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | lab-soc, lab-sandbox |
| Splunk | Ubuntu 24.04 LTS | 8GB | 4 | 80GB | lab-soc, lab-domain |
| DC01 | Windows Server 2022 | 4GB | 2 | 60GB | lab-domain |
| Windows host | Windows 10/11 | 4GB | 2 | 60GB | lab-domain |
| Linux sender | Ubuntu 24.04 LTS | 2GB | 2 | 40GB | lab-domain |
| Kali | Kali Linux | 4GB | 2 | 60GB | lab-attack, lab-domain |
| Sandbox | TBD | 4GB | 2 | 60GB | lab-sandbox |
| **Total** | | **36GB** | **20** | **460GB*** | |

*qcow2 thin-provisioned — actual initial disk usage ~80–120GB

## Install Methods

### OPNsense
- Download ISO from https://opnsense.org/download/ (amd64 dvd)
- Install to 20GB disk, configure all 5 interfaces during setup
- Wazuh syslog forwarding: System → Log Files → Remote → add Wazuh IP:514

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
