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
| fw-router | Alpine 3.23 | 1GB | 1 | 4GB | WAN + lab-net |
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

## SSH Access

| Host | User | Key | Notes |
|------|------|-----|-------|
| fw-router (192.168.122.10) | root | `~/.ssh/fw-router-key` | Fixed IP via libvirt DHCP reservation |
| Wazuh (192.168.10.10) | labadmin | `~/.ssh/id_ed25519` | Ubuntu, passwordless sudo |
| Splunk (192.168.10.40) | labadmin | `~/.ssh/id_ed25519` | Ubuntu, passwordless sudo; web UI http://192.168.10.40:8000 admin/REDACTED |

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
