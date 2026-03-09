# Task Plan: SOC Home Lab — aurora (local VM stack)

## Goal
Build a local SOC/Blue Team practice lab on `aurora` (Aurora OS, KVM/virt-manager) with a firewall, SIEM (Wazuh), log analysis (Splunk), Windows AD domain, attack platform (Kali), and an isolated sandbox for phone-home/malware analysis. Tuned for Atomic Red Team detection engineering across a 3-tier detection architecture.

## Host
- **Machine:** aurora
- **OS:** Aurora 43 (Universal Blue / Fedora Kinoite-based, KDE)
- **CPU:** AMD Ryzen AI 7 350 — 8 cores / 16 threads (AMD-V enabled)
- **RAM:** 54GB total (~50GB available)
- **Disk:** 930GB NVMe — ~356GB free (thin-provisioned qcow2, actual usage much less)
- **Hypervisor:** QEMU/KVM + virt-manager (already installed)

## Detection Architecture (3-Tier)

| Tier | Component | Location | Catches |
|------|-----------|----------|---------|
| 1 — Perimeter NIDS | Suricata (ET Open rules) | fw-router, on eth1 (lab-net) | C2 callbacks, exfil, inbound scans, north-south traffic |
| 2 — Internal NIDS | Suricata (ET Open rules) | aurora host, on virbr-lab bridge | East-west lateral movement, intra-subnet recon |
| 3 — Host EDR | Wazuh agent + Sysmon (Win) / auditd (Linux) | Every VM | Process exec, registry, file events, credential access |

> **Rationale:** Intra-subnet VM-to-VM traffic never traverses the fw-router (L2 bridge bypass).
> Tier 2 on the hypervisor bridge catches lateral movement that Tier 1 misses — mirrors a
> real SPAN port on a core switch. All three tiers feed Wazuh SIEM.

## Current Phase
Phase 5 complete. Next: blog post write-up (rsyslog→Splunk), then Phase 6 (Windows DC) or Phase 9 (Kali).

## Phases

### Phase 1: Planning & Network Design
- [x] Inventory host resources
- [x] Define VM stack and resource allocation
- [x] Design segmented network topology
- [x] Choose install methods for each VM
- [x] Design 3-tier detection architecture (perimeter NIDS / internal NIDS / host EDR)
- **Status:** complete

### Phase 2: Host Preparation
- [x] Configure passwordless sudo for blyons
- [x] Clear stale virbr0 bridge
- [x] Create libvirt virtual networks (lab-net, lab-sandbox)
- [x] Create libvirt storage pool (soc-lab at /var/lib/libvirt/images/soc-lab/)
- [x] Download ISOs (Ubuntu 24.04.4 ✓, Kali qcow2 ✓, Alpine 3.23.3 ✓, Win11 ✓)
- **Status:** complete

### Phase 3: Firewall Router VM (Alpine Linux + nftables)
- [x] Download Alpine Linux 3.23.3 Virtual ISO (SHA256 verified ✓)
- [x] Create VM (512MB RAM, 1 vCPU, 4GB disk)
- [x] Attach 3 NICs: WAN (virbr0) + lab-net + lab-sandbox
- [x] Run setup-alpine, install to disk
- [x] Configure static IPs: eth1=192.168.10.1, eth2=192.168.40.1
- [x] Enable IP forwarding (net.ipv4.ip_forward=1)
- [x] Write + load nftables ruleset (NAT lab-net→WAN, sandbox isolation)
- [x] SSH key auth working (~/.ssh/fw-router-key)
- **Status:** complete

### Phase 3b: Suricata — Perimeter + Internal NIDS
> Two Suricata instances for full 3-tier coverage.
#### Tier 1 — Perimeter (on fw-router)
- [x] Install Suricata on fw-router (Alpine edge/community — not in 3.23 main)
- [x] Configure af-packet on eth1 (lab-net facing interface), community-id enabled
- [x] ET Open rules auto-fetched by suricata-update on install (~48k enabled)
- [x] EVE JSON output → `/var/log/suricata/eve.json`
- [x] No Wazuh agent (glibc incompatible with Alpine/musl) — rsyslog used instead
- [x] rsyslog imfile → Wazuh TCP syslog :514 (facility local3, source 192.168.10.1)
- [x] Deploy script: `scripts/fw-router/suricata-setup.sh`
#### Tier 2 — Internal East-West (on aurora host)
- [x] Suricata in Podman container (jasonish/suricata:latest) on virbr-lab
- [x] ET Open rules via suricata-update in container (~48k enabled)
- [x] EVE JSON → `/var/log/suricata/internal/eve.json`, community-id enabled
- [x] No Wazuh agent on aurora (out of scope; Aurora is image-based, no package layering)
- [x] rsyslog in Podman container (rsyslog/syslog_appliance_alpine) → Wazuh :514 (facility local4)
- [x] Quadlet units auto-start via multi-user.target
- [x] Deploy script: `scripts/host-setup/suricata-internal-setup.sh`
- **Status:** complete

### Phase 4: Wazuh Server
- [x] Create Ubuntu 24.04 VM (8GB RAM, 4 vCPU, 80GB disk) — unattended via autoinstall seed ISO
- [x] Attach NICs: lab-net (192.168.10.10) + lab-sandbox (192.168.40.10)
- [x] Run Wazuh all-in-one installer (wazuh-install.sh -a, version 4.14)
- [x] Verified: wazuh-manager, wazuh-indexer, wazuh-dashboard all active
- [x] Dashboard: https://192.168.10.10 — admin / (see wazuh-install-files.tar on VM)
- [ ] Configure syslog receiver (UDP/TCP 514) for fw-router rsyslog
- [ ] Verify Suricata EVE alerts appearing in dashboard (after Phase 3b)
- **Status:** complete (syslog + Suricata verification deferred to Phase 3b)

### Phase 5: Splunk
- [x] Create Ubuntu 24.04 VM (8GB RAM, 4 vCPU, 80GB disk) — autoinstall seed ISO
- [x] Attach NIC: lab-net (192.168.10.40)
- [x] Install Splunk Enterprise 10.2.1 as splunk system user (not root)
- [x] Enable receiving on port 9997 (for Splunk UFs)
- [x] Web UI accessible on port 8000, admin password via user-seed.conf
- [x] rsyslog dual-forward: Tier 1 (fw-router) + Tier 2 (rsyslog container) → Splunk TCP :5514
- [x] suricata index: props.conf (KV_MODE=json), transforms.conf (strip syslog header → clean JSON _raw)
- [x] Verified: EVE events landing — alert, dns, flow, ssh, tls event types confirmed
- [x] Deploy scripts: `scripts/host-setup/splunk-vm-setup.sh`, `autoinstall/splunk/user-data`
- [x] Traffic seeding: `scripts/generate-traffic.sh`
- **Status:** complete
- **Blog post:** "Forwarding rsyslog to Splunk without a Universal Forwarder" — notes in blog-notes.md

### Phase 6: Windows Domain Controller
- [ ] Create Windows Server 2022 VM (4GB RAM, 2 vCPU, 60GB disk)
- [ ] Attach NIC: lab-net
- [ ] Install AD DS role, promote to DC
- [ ] Domain: lab.local
- [ ] Configure DNS pointing to DC
- [ ] Install Wazuh agent → 192.168.10.10 (Tier 3 host EDR)
- [ ] Install Sysmon with SwiftOnSecurity or Olaf config
- [ ] Install Splunk UF → 192.168.10.40:9997
- **Status:** pending

### Phase 7: Windows Host (Forensic Workstation)
- [x] Create Windows 11 Pro VM (4GB RAM, 2 vCPU, 60GB disk) — win-forensic
- [x] Attach NIC: lab-net (MAC 52:54:00:e2:4c:3f, target IP 192.168.10.50)
- [x] Unattended install: Autounattend.xml (hostname WIN-FORENSIC, user analyst, SPICE/RDP/WinRM/Defender RT off)
- [x] Build pipeline: win11-forensic/build-iso.sh reads pass soc-lab/windows-analyst — no creds in git
- [ ] Verify install completes, confirm login as analyst
- [ ] Assign static IP 192.168.10.50 (libvirt DHCP reservation or manual)
- [ ] Install Wazuh agent → 192.168.10.10 (Tier 3 host EDR)
- [ ] Install Sysmon with SwiftOnSecurity or Olaf config
- [ ] Install Splunk UF → 192.168.10.40:9997
- [ ] Install forensic tools: Eric Zimmermann toolkit, Volatility3, WinPmem, etc.
- [ ] Install Atomic Red Team (for detection tuning)
- [ ] Join to lab.local domain (after Phase 6 DC is up)
- **Status:** in_progress (install running)

### Phase 8: Linux Log Sender
- [ ] Create Ubuntu 24.04 VM (2GB RAM, 2 vCPU, 40GB disk)
- [ ] Attach NIC: lab-net
- [ ] Install Wazuh agent → 192.168.10.10 (Tier 3 host EDR)
- [ ] Configure auditd with comprehensive ruleset
- [ ] Install Splunk Universal Forwarder → 192.168.10.40:9997
- **Status:** pending

### Phase 9: Kali Linux
- [ ] Extract Kali qcow2 from 7z archive, move to storage pool
- [ ] Create Kali VM (4GB RAM, 2 vCPU) using existing qcow2
- [ ] Attach NIC: lab-net
- [ ] Verify tools available (nmap, metasploit, impacket, etc.)
- [ ] Install Wazuh agent (optional — track attacker activity for red team log correlation)
- **Status:** pending

### Phase 10: Sandbox / Phone-Home Host
- [ ] Create VM (4GB RAM, 2 vCPU, 60GB disk) — OS TBD (Windows for malware, Linux for C2)
- [ ] Attach NIC: lab-sandbox ONLY
- [ ] fw-router blocks all outbound internet from sandbox segment
- [ ] Install Wazuh agent → 192.168.40.10 (captures all activity)
- [ ] Snapshot baseline immediately after install — revert between scenarios
- **Status:** pending

### Phase 11: Integration & Validation
- [ ] Confirm all Wazuh agents reporting to dashboard
- [ ] Confirm logs flowing into Splunk from all sources
- [ ] Confirm Suricata EVE alerts (both tiers) visible in Wazuh
- [ ] Test firewall rules (sandbox cannot reach internet, can reach Wazuh only)
- [ ] Run Atomic Red Team subset — verify detections fire across all 3 tiers
- [ ] Document which ART techniques hit which tier (tuning baseline)
- [ ] Document network map and credential sheet (local only)
- **Status:** pending

## Resource Allocation

| VM            | OS                   | RAM  | vCPU | Disk  | Networks          |
|---------------|----------------------|------|------|-------|-------------------|
| fw-router     | Alpine Linux 3.23    | 512MB| 1    | 4GB   | WAN + lab-net + lab-sandbox |
| Wazuh         | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-net, lab-sandbox |
| Splunk        | Ubuntu 24.04 LTS     | 8GB  | 4    | 80GB  | lab-net           |
| DC01          | Windows Server 2022  | 4GB  | 2    | 60GB  | lab-net           |
| Windows host  | Windows 10/11        | 4GB  | 2    | 60GB  | lab-net           |
| Linux sender  | Ubuntu 24.04 LTS     | 2GB  | 2    | 40GB  | lab-net           |
| Kali          | Kali Linux (qcow2)   | 4GB  | 2    | 60GB  | lab-net           |
| Sandbox       | TBD                  | 4GB  | 2    | 60GB  | lab-sandbox       |
| **Total**     |                      | **34.5GB** | **19** | **444GB** | |
| Host headroom | Aurora               | ~18GB | 2+  | —     | —                 |

> qcow2 thin provisioning: ~80–120GB actual initial usage

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| QEMU/KVM + virt-manager | Already installed, native Linux, best performance |
| 2 libvirt networks (lab-net + lab-sandbox) | Flat lab-net for all attack/defend VMs; Kali needs full internet for VPN to HTB/THM |
| Alpine Linux + nftables firewall | Simpler, fully scriptable, ~512MB RAM vs 2GB |
| 3-tier detection: perimeter NIDS + internal NIDS + host EDR | Emulates enterprise/MSSP architecture; needed for realistic ART tuning |
| Suricata Tier 1 on fw-router | Perimeter sensor — catches C2/exfil/north-south; mirrors enterprise perimeter IDS |
| Suricata Tier 2 on aurora virbr-lab | Internal sensor — catches lateral movement bypassing router; mirrors core switch SPAN |
| Sysmon on Windows VMs | Host EDR for process/registry/file telemetry; required for most ART technique coverage |
| auditd on Linux VMs | Linux equivalent of Sysmon for host EDR tier |
| Wazuh all-in-one installer | Simplest single-node path |
| Splunk Enterprise free tier | 500MB/day — sufficient for home lab |
| Windows Server 2022 eval ISO | 180-day free trial |
| Sandbox on lab-sandbox only | fw-router blocks real internet; Wazuh captures all activity |

## Errors Encountered
| Error | Attempt | Resolution |
|-------|---------|------------|
| virbr0 stale bridge blocks lab-net creation | 1 | Fixed: sudo nmcli connection delete virbr0 |
| sudo requires interactive auth in Claude session | 1 | Fixed: passwordless sudo configured |
| Ubuntu ISO corruption (dual wget processes) | 1 | Fixed: killed both, deleted, single fresh download |
| QEMU permission denied on /home/blyons ISO path | 1 | Fixed: sudo chmod o+x on path components |
| Wazuh install URL 403 (packages.wazuh.com/4.x) | 1 | Fixed: use version-specific URL /4.14/wazuh-install.sh |
| Kali ISO checksum mismatch | 1 | Deleted; switched to official QEMU qcow2 7z |
| OPNsense interactive console too cumbersome | 1 | Replaced with Alpine Linux + nftables |
| Alpine live ISO loses state on VM reboot | 1 | Must run setup-alpine to install to disk first |
| virsh send-key drops uppercase letters silently | multiple | Avoid uppercase in all send-key commands |
| HTTP server blocked by firewalld from VM | 1 | sudo firewall-cmd --zone=libvirt --add-port=8080/tcp |
| After host reboot: VMs all show stopped in virsh | 1 | Root cause: `virsh` defaults to qemu:///session; VMs live on qemu:///system. Always use `virsh --connect qemu:///system` |
| After host reboot: `default` libvirt network stuck inactive | 1 | NM grabbed virbr0 as its own bridge, blocking libvirt. Fix: delete NM profile (`nmcli con delete virbr0`), create `/etc/NetworkManager/conf.d/unmanaged-libvirt.conf` to permanently unmanage virbr* interfaces |
| nftables management SSH rule missing after fw-router reboot | 1 | Alpine nftables service loads `/etc/nftables.nft`, not `/etc/nftables.conf`. Correct config was only in .conf. Fix: `cp /etc/nftables.conf /etc/nftables.nft` — now persists correctly |
| virsh send-key KEY_PERIOD invalid | 1 | Use KEY_DOT for the period character |
| NM unmanaged-libvirt.conf broke route persistence | 1 | NM dispatcher never fires for unmanaged (virbr*) interfaces. Fixed: systemd unit `soc-lab-routes.service` adds routes after virtnetworkd starts |
| libvirt hook caused SELinux denials + network taint | 1 | virt_hooks_unconfined boolean required; hook also caused lab-sandbox to get "tainted" state. Removed hook entirely; systemd unit is simpler and SELinux-clean |
| lab-sandbox network stuck — "already in use by virbr0" | ongoing | Unknown libvirt internal state corruption. Workaround: removed lab-sandbox NIC from fw-router and wazuh so they can autostart. lab-sandbox disabled until Phase 10 |
| win-forensic won't start: "Could not access KVM kernel module: No such file or directory" | 1 | Root cause: `/dev/kvm` owned by `systemd-network:0660` instead of `kvm:0666`. libvirt creates a private devns for QEMU — when bind-mounting /dev/kvm into it, the wrong group/mode causes ENOENT inside the namespace. Temp fix: `sudo chown root:kvm /dev/kvm && sudo chmod 0666 /dev/kvm`. If it recurs after next reboot, permanent fix: `echo 'KERNEL=="kvm", GROUP="kvm", MODE="0666"' \| sudo tee /etc/udev/rules.d/99-kvm.rules` |

## Notes
- SSH to fw-router: `ssh -i ~/.ssh/fw-router-key root@192.168.122.10` (fixed IP via libvirt DHCP reservation)
- Kali QEMU image: kali-linux-2025.4-qemu-amd64.7z (SHA256: e4b958f89d5c26f672a140628315a3a8f733fde9830722ae3d371b5536285d1d)
- Wazuh dashboard: https://192.168.10.10 — admin / (see wazuh-install-files.tar on VM)
- Scripts: scripts/fw-router/ (alpine-answers, fw-setup.sh, nftables.conf), scripts/sendkey-lib.sh
- Host setup: scripts/host-setup/host-network-setup.sh (run to restore lab networking after host reinstall)
- Windows evals: https://www.microsoft.com/en-us/evalcenter/
- Sysmon configs: SwiftOnSecurity (broad) or Olaf Hartong modular (recommended for ART tuning)
- Atomic Red Team: https://github.com/redcanaryco/atomic-red-team

## Host Networking (survives reboots)
- fw-router WAN IP fixed: MAC `52:54:00:ca:03:ea` → `192.168.122.10` (libvirt DHCP reservation in default network)
- VMs autostart: fw-router + wazuh (`virsh --connect qemu:///system autostart <vm>`)
- NM ignores virbr* interfaces: `/etc/NetworkManager/conf.d/unmanaged-libvirt.conf`
  - Without this, NM grabs virbr0 at boot and blocks libvirt from starting the default network
- Lab routes added by systemd: `/etc/systemd/system/soc-lab-routes.service`
  - Runs after virtnetworkd; adds `192.168.10.0/24` and `192.168.40.0/24` via `192.168.122.10`
  - Replaces the libvirt hook (removed) and NM dispatcher (doesn't fire for unmanaged interfaces)
- lab-sandbox network: **disabled** — libvirt bug prevents it from starting alongside default network
  - lab-sandbox NIC removed from fw-router and wazuh VMs (re-add in Phase 10)
  - SELinux boolean `virt_hooks_unconfined` was enabled (persistent) but hook was removed anyway
- Always use `virsh --connect qemu:///system` — default URI is session, not system
- To restore from scratch: `bash scripts/host-setup/host-network-setup.sh`
