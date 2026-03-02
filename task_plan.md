# Task Plan: SOC Home Lab — aurora (local VM stack)

## Goal
Build a local SOC/Blue Team practice lab on `aurora` (Aurora OS, KVM/virt-manager) with a firewall, SIEM (Wazuh), log analysis (Splunk), Windows AD domain, attack platform (Kali), and an isolated sandbox for phone-home/malware analysis.

## Host
- **Machine:** aurora
- **OS:** Aurora 43 (Universal Blue / Fedora Kinoite-based, KDE)
- **CPU:** AMD Ryzen AI 7 350 — 8 cores / 16 threads (AMD-V enabled)
- **RAM:** 54GB total (~50GB available)
- **Disk:** 930GB NVMe — ~356GB free (thin-provisioned qcow2, actual usage much less)
- **Hypervisor:** QEMU/KVM + virt-manager (already installed)

## Current Phase
Phase 3 — Firewall VM (Alpine Linux + nftables, replacing OPNsense)

## Phases

### Phase 1: Planning & Network Design
- [x] Inventory host resources
- [x] Define VM stack and resource allocation
- [x] Design segmented network topology
- [x] Choose install methods for each VM
- **Status:** complete

### Phase 2: Host Preparation
- [x] Configure passwordless sudo for blyons
- [x] Clear stale virbr0 bridge
- [x] Create 4 libvirt virtual networks (lab-soc, lab-domain, lab-attack, lab-sandbox)
- [x] Create libvirt storage pool (soc-lab at /var/lib/libvirt/images/soc-lab/)
- [x] Download ISOs (Ubuntu 24.04.4 ✓, OPNsense 26.1.2 downloading, Kali 2025.4 downloading, Win11 ✓)
- **Status:** complete

### Phase 3: Firewall Router VM (Alpine Linux + nftables + Suricata)
> **Decision:** Replaced OPNsense with Alpine Linux + nftables. Simpler, fully scriptable,
> ~512MB RAM / 4GB disk vs 2GB / 20GB.
> **Network redesign:** Collapsed 4 segments → 2. lab-net (flat, all VMs, full internet/NAT)
> + lab-sandbox (isolated, no internet). Kali needs full internet for VPN to HTB/THM etc.
- [x] Download Alpine Linux 3.23.3 Virtual ISO (SHA256 verified ✓)
- [ ] Delete stale libvirt networks (lab-soc, lab-domain, lab-attack) — replace with lab-net
- [ ] Create VM (512MB RAM, 1 vCPU, 4GB disk)
- [ ] Attach 3 NICs: WAN (virbr0) + lab-net + lab-sandbox
- [ ] Run alpine-setup, configure interfaces + static IPs
- [ ] Enable IP forwarding
- [ ] Write nftables ruleset: NAT lab-net→WAN, block sandbox→WAN, allow sandbox→Wazuh only
- [ ] Install Suricata + configure on lab-net interface (ET Open rules)
- [ ] Configure rsyslog → Wazuh UDP 514
- [ ] Configure Suricata EVE JSON → Wazuh agent
- **Status:** in_progress

### Phase 4: Wazuh Server
- [x] Create Ubuntu 24.04 VM (8GB RAM, 4 vCPU, 80GB disk) — unattended via autoinstall seed ISO
- [x] Attach NICs: lab-soc (192.168.10.10) + lab-sandbox (192.168.40.10)
- [x] Run Wazuh all-in-one installer (wazuh-install.sh -a, version 4.14)
- [x] Verified: wazuh-manager, wazuh-indexer, wazuh-dashboard all active
- [x] Dashboard: https://192.168.10.10 — admin / (see wazuh-install-files.tar on VM)
- [ ] Configure syslog receiver (UDP/TCP 514)
- [ ] Configure OPNsense syslog → Wazuh (after OPNsense VM up)
- **Status:** complete (syslog/OPNsense config deferred to Phase 11)

### Phase 5: Splunk
- [ ] Create Ubuntu 24.04 VM (8GB RAM, 4 vCPU, 80GB disk)
- [ ] Attach NICs: lab-soc + lab-domain
- [ ] Install Splunk Enterprise (free 500MB/day tier)
- [ ] Enable receiving on port 9997
- [ ] Verify web UI accessible on port 8000
- **Status:** pending

### Phase 6: Windows Domain Controller
- [ ] Create Windows Server 2022 VM (4GB RAM, 2 vCPU, 60GB disk)
- [ ] Attach NIC: lab-domain
- [ ] Install AD DS role, promote to DC
- [ ] Domain: lab.local
- [ ] Configure DNS pointing to DC
- **Status:** pending

### Phase 7: Windows Host
- [ ] Create Windows 10/11 VM (4GB RAM, 2 vCPU, 60GB disk)
- [ ] Attach NIC: lab-domain
- [ ] Join to lab.local domain
- [ ] Install Wazuh agent → 192.168.10.10
- [ ] Install Splunk UF → 192.168.10.40:9997
- **Status:** pending

### Phase 8: Linux Log Sender
- [ ] Create Ubuntu 24.04 VM (2GB RAM, 2 vCPU, 40GB disk)
- [ ] Attach NIC: lab-domain
- [ ] Install Wazuh agent → 192.168.10.10
- [ ] Install Splunk Universal Forwarder → 192.168.10.40:9997
- **Status:** pending

### Phase 9: Kali Linux
- [ ] Create Kali VM (4GB RAM, 2 vCPU, 60GB disk)
- [ ] Attach NIC: lab-attack (+ lab-domain for attack scenarios)
- [ ] Install Wazuh agent (optional — track attacker activity)
- [ ] Verify tools available (nmap, metasploit, impacket, etc.)
- **Status:** pending

### Phase 10: Sandbox / Phone-Home Host
- [ ] Create VM (4GB RAM, 2 vCPU, 60GB disk) — OS TBD
- [ ] Attach NIC: lab-sandbox ONLY
- [ ] OPNsense blocks all outbound internet from this segment
- [ ] Install Wazuh agent (captures all activity for analysis)
- [ ] Snapshot baseline before any suspect activity
- **Status:** pending

### Phase 11: Integration & Validation
- [ ] Confirm all agents reporting to Wazuh dashboard
- [ ] Confirm logs flowing into Splunk from all sources
- [ ] Confirm OPNsense logs appearing in Wazuh
- [ ] Test firewall rules (sandbox cannot reach internet)
- [ ] Generate test events, trace through Wazuh and Splunk
- [ ] Document network map and credential sheet (local only)
- **Status:** pending

## Resource Allocation

| VM            | OS                   | RAM  | vCPU | Disk  | Networks                          |
|---------------|----------------------|------|------|-------|-----------------------------------|
| fw-router     | Alpine Linux         | 512MB| 1    | 4GB   | WAN + all 4 lab segments          |
| Wazuh         | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-soc, lab-domain, lab-sandbox  |
| Splunk        | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-soc, lab-domain               |
| DC01          | Windows Server 2022  | 4GB  | 2    | 60GB  | lab-domain                        |
| Windows host  | Windows 10/11        | 4GB  | 2    | 60GB  | lab-domain                        |
| Linux sender  | Ubuntu 24.04 LTS     | 2GB  | 2    | 40GB  | lab-domain                        |
| Kali          | Kali Linux           | 4GB  | 2    | 60GB  | lab-attack, lab-domain            |
| Sandbox       | TBD                  | 4GB  | 2    | 60GB  | lab-sandbox                       |
| **Total**     |                      | **34.5GB** | **19** | **444GB** |                        |
| Host headroom | Aurora               | ~18GB | 2+  | —     | —                                 |

> qcow2 thin provisioning: 460GB allocated, actual initial usage ~80–120GB

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| QEMU/KVM + virt-manager | Already installed, native Linux, best performance |
| 4 isolated libvirt networks | L3 segmentation; firewall enforces inter-VLAN policy |
| Alpine Linux + nftables firewall | Simpler, fully scriptable, ~512MB RAM vs 2GB; same segmentation/log goals as OPNsense |
| Wazuh all-in-one installer | Simplest single-node path |
| Splunk Enterprise free tier | 500MB/day — sufficient for home lab |
| Windows Server 2022 eval ISO | 180-day free trial |
| Kali as full VM (not Distrobox) | Needs isolated network segment, real NIC for attack scenarios |
| Sandbox on lab-sandbox only | OPNsense blocks real internet; Wazuh captures all activity |
| Passwordless sudo | Required for bridge/network management without interactive auth |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| virbr0 stale bridge blocks lab-net creation | 1 | Fixed: sudo nmcli connection delete virbr0 |
| sudo requires interactive auth in Claude session | 1 | Fixed: passwordless sudo configured |
| Ubuntu ISO corruption (dual wget processes) | 1 | Fixed: killed both, deleted, single fresh download |
| QEMU permission denied on /home/blyons ISO path | 1 | Fixed: sudo chmod o+x on path components |
| Wazuh install URL 403 (packages.wazuh.com/4.x) | 1 | Fixed: use version-specific URL /4.14/wazuh-install.sh |
| Ubuntu autoinstall requires manual "yes" confirmation | 1 | User confirmed manually; accepted Ubuntu safety UX |
| Kali ISO checksum mismatch (e1a1654f vs 3b4a3a9f) | 1 | Deleted; switched to official QEMU qcow2 7z instead |
| OPNsense interactive console setup too cumbersome | 1 | Replaced with Alpine Linux + nftables router VM |

## Notes
- Build order: sudo fix → networks → OPNsense → Wazuh → Splunk → DC → Win host → Linux sender → Kali → Sandbox
- Kali QEMU image: https://cdimage.kali.org/kali-2025.4/kali-linux-2025.4-qemu-amd64.7z (SHA256: e4b958f89d5c26f672a140628315a3a8f733fde9830722ae3d371b5536285d1d)
- Alpine Linux ISO: https://alpinelinux.org/downloads/ (Virtual, amd64)
- OPNsense ISO retained in isos/ as fallback but NOT used
- Windows evals: https://www.microsoft.com/en-us/evalcenter/
- Wazuh: https://documentation.wazuh.com/current/installation-guide/
- Splunk: https://www.splunk.com/en_us/download/splunk-enterprise.html
- Previously ran homelab on Proxmox (offline/dismantled) — configs archived in backup
