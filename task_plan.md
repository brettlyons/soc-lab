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
Phase 1 — Planning complete, pending sudo fix before Phase 2

## Phases

### Phase 1: Planning & Network Design
- [x] Inventory host resources
- [x] Define VM stack and resource allocation
- [x] Design segmented network topology
- [x] Choose install methods for each VM
- **Status:** complete

### Phase 2: Host Preparation
- [ ] Configure passwordless sudo for blyons
- [ ] Clear stale virbr0 bridge
- [ ] Create 4 libvirt virtual networks (lab-soc, lab-domain, lab-attack, lab-sandbox)
- [ ] Create libvirt storage pool
- [ ] Download ISOs (Ubuntu 24.04, OPNsense, Windows Server 2022, Windows 10/11, Kali)
- **Status:** pending — blocked on sudo

### Phase 3: OPNsense Firewall
- [ ] Create OPNsense VM (2GB RAM, 2 vCPU, 20GB disk)
- [ ] Attach 5 NICs: WAN (NAT uplink) + 4 lab networks
- [ ] Initial OPNsense setup (WAN, LAN/SOC interface)
- [ ] Configure interfaces for all 4 segments
- [ ] Set firewall rules:
  - lab-soc ↔ lab-domain: allow (agents/logs)
  - lab-soc ↔ lab-attack: allow (Kali reporting to Wazuh)
  - lab-sandbox → internet: BLOCK
  - lab-sandbox ↔ lab-soc: allow (Wazuh agent only)
  - lab-attack → lab-domain: allow (attack traffic for lab scenarios)
- [ ] Enable syslog forwarding to Wazuh
- **Status:** pending

### Phase 4: Wazuh Server
- [ ] Create Ubuntu 24.04 VM (8GB RAM, 4 vCPU, 80GB disk)
- [ ] Attach NICs: lab-soc + lab-domain + lab-sandbox
- [ ] Run Wazuh all-in-one installer
- [ ] Verify Wazuh dashboard accessible
- [ ] Configure syslog receiver (UDP/TCP 514)
- [ ] Configure OPNsense syslog → Wazuh
- **Status:** pending

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
| OPNsense      | OPNsense (FreeBSD)   | 2GB  | 2    | 20GB  | WAN + all 4 lab segments          |
| Wazuh         | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-soc, lab-domain, lab-sandbox  |
| Splunk        | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-soc, lab-domain               |
| DC01          | Windows Server 2022  | 4GB  | 2    | 60GB  | lab-domain                        |
| Windows host  | Windows 10/11        | 4GB  | 2    | 60GB  | lab-domain                        |
| Linux sender  | Ubuntu 24.04 LTS     | 2GB  | 2    | 40GB  | lab-domain                        |
| Kali          | Kali Linux           | 4GB  | 2    | 60GB  | lab-attack, lab-domain            |
| Sandbox       | TBD                  | 4GB  | 2    | 60GB  | lab-sandbox                       |
| **Total**     |                      | **36GB** | **20** | **460GB** |                           |
| Host headroom | Aurora               | ~18GB | 2+  | —     | —                                 |

> qcow2 thin provisioning: 460GB allocated, actual initial usage ~80–120GB

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| QEMU/KVM + virt-manager | Already installed, native Linux, best performance |
| 4 isolated libvirt networks | L3 segmentation; firewall enforces inter-VLAN policy |
| OPNsense firewall VM | Controls all inter-segment routing; logs feed Wazuh; realistic enterprise pattern |
| Wazuh all-in-one installer | Simplest single-node path |
| Splunk Enterprise free tier | 500MB/day — sufficient for home lab |
| Windows Server 2022 eval ISO | 180-day free trial |
| Kali as full VM (not Distrobox) | Needs isolated network segment, real NIC for attack scenarios |
| Sandbox on lab-sandbox only | OPNsense blocks real internet; Wazuh captures all activity |
| Passwordless sudo | Required for bridge/network management without interactive auth |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| virbr0 stale bridge blocks lab-net creation | 1 | Pending: delete via sudo ip link delete virbr0 |
| sudo requires interactive auth in Claude session | 1 | Pending: configure passwordless sudo |

## Notes
- Build order: sudo fix → networks → OPNsense → Wazuh → Splunk → DC → Win host → Linux sender → Kali → Sandbox
- Kali ISO: https://www.kali.org/get-kali/#kali-virtual-machines (or bare ISO)
- OPNsense ISO: https://opnsense.org/download/
- Windows evals: https://www.microsoft.com/en-us/evalcenter/
- Wazuh: https://documentation.wazuh.com/current/installation-guide/
- Splunk: https://www.splunk.com/en_us/download/splunk-enterprise.html
- Previously ran homelab on Proxmox (offline/dismantled) — configs archived in backup
