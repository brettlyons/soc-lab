# Progress Log — SOC Lab (aurora)

## Session: 2026-03-01

### Phase 1: Planning & Network Design
- **Status:** complete
- Actions taken:
  - Inventoried host resources (CPU, RAM, disk, virtualization support)
  - Reviewed existing homelab backup for context (Proxmox configs now archived)
  - Defined VM stack, resource allocation, and build order
  - Chose install methods for each VM
  - Designed lab network (isolated bridge, 192.168.100.0/24)
  - Created project directory: `/home/blyons/workspace/soc-lab/`
- Files created:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

### Session 2: 2026-03-01 (continued)
- **Status:** in_progress
- Actions taken:
  - Expanded scope: added OPNsense firewall, Kali, Sandbox VM
  - Redesigned network: 4 isolated segments (soc, domain, attack, sandbox)
  - Attempted lab-net creation — blocked by stale virbr0 / sudo auth issue
  - Updated all planning docs (task_plan.md, findings.md, runbook.md)
  - Scope locked — no further additions until current stack is built
- Files modified:
  - `task_plan.md` (full rewrite — 10 phases)
  - `findings.md` (full rewrite — network topology, firewall rules, IP table)
  - `runbook.md` (full rewrite — all 10 phases with commands)

### Phases 2–10: Pending
- **Blocker:** passwordless sudo + stale virbr0 must be resolved first
- Next action: run sudo fix in terminal, then resume here

### Session 3: 2026-03-01
- **Status:** in_progress
- Actions taken:
  - Verified all ISO checksums
  - OPNsense bz2: PASS; Ubuntu: PASS; Kali: FAIL (mismatch, deleted)
  - Switched Kali from installer ISO to official QEMU qcow2 7z (downloading in background)
  - Replaced OPNsense with Alpine Linux + nftables router (simpler, fully scriptable, ~512MB RAM)
  - Updated task_plan.md and findings.md to reflect both decisions

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Planning complete — blocked on sudo/bridge fix |
| Where am I going? | Networks → OPNsense → Wazuh → Splunk → DC → Win host → Linux sender → Kali → Sandbox |
| What's the goal? | Local SOC/Blue Team lab on aurora — firewall-segmented, 8 VMs |
| What have I learned? | See findings.md |
| What have I done? | Full plan documented, network design finalized, runbook written |

## Session 4: 2026-03-01

### Phase 3: fw-router Alpine install
- Deleted and recreated fw-router VM (clean slate after boot failures)
- Alpine 3.23.3 installed to disk via setup-alpine (user drove interactively in virt-manager)
- SSH key auth working: `ssh -i /tmp/fw-router-key root@192.168.122.54`
- Key stored at `/tmp/fw-router-key` (host) — save to permanent location
- Root password: \<set during setup-alpine\>
- PermitRootLogin: prohibit-password (key auth only — correct)
- **Status:** SSH working, ready for nftables + Suricata config
- Scripts saved to `scripts/fw-router/`: alpine-answers, fw-install.sh, fw-addkey.sh, fw-mvkey.sh

### Pending (Phase 3)
- [ ] Enable IP forwarding (sysctl net.ipv4.ip_forward=1)
- [ ] Configure static IPs on eth1 (192.168.10.1) and eth2 (192.168.40.1)
- [ ] Write nftables ruleset (NAT lab-net→WAN, block sandbox→WAN)
- [ ] Install Suricata + ET Open rules
- [ ] Configure rsyslog → Wazuh UDP 514

## Session 5: 2026-03-01 (continued)

### Phase 3: fw-router — completed
- nftables ruleset deployed and verified:
  - NAT lab-net → WAN (masquerade on eth0)
  - Sandbox isolation: eth2 can only reach 192.168.10.10 (Wazuh)
  - Management SSH: `iif eth0 ip saddr 192.168.122.0/24 tcp dport 22 accept`
  - Host → lab-net forwarding: `iif eth0 oif eth1 ip saddr 192.168.122.0/24 accept`
- Static IPs: eth1=192.168.10.1/24, eth2=192.168.40.1/24
- IP forwarding enabled (sysctl net.ipv4.ip_forward=1, persisted in /etc/sysctl.conf)
- SSH key stored at `~/.ssh/fw-router-key` (moved from /tmp)

### Phase 3: Detection Architecture Redesign
- Identified: intra-subnet traffic on lab-net bypasses fw-router at L2 — never traverses nftables
- Designed 3-tier detection architecture for Atomic Red Team tuning fidelity:
  - Tier 1: Suricata on fw-router eth1 (perimeter NIDS — C2, exfil, north-south)
  - Tier 2: Suricata on aurora virbr-lab bridge (internal NIDS — lateral movement, east-west)
  - Tier 3: Sysmon+Wazuh (Windows), auditd+Wazuh (Linux) host EDR
- Added Phase 3b (Suricata), Sysmon/auditd tasks, Phase 11 ART tuning to task_plan.md

### Phase 4: Wazuh Server — completed
- Ubuntu 24.04 VM installed via autoinstall seed ISO
- Wazuh all-in-one (v4.14) installed and verified:
  - wazuh-manager, wazuh-indexer, wazuh-dashboard: active
  - Dashboard: https://192.168.10.10 — admin / (credentials in ~/wazuh-install-files.tar)
- Aurora host route added: 192.168.10.0/24 via 192.168.122.10

### Host Networking — persistent (completed)
- fw-router WAN IP fixed: DHCP reservation MAC `52:54:00:ca:03:ea` → `192.168.122.10`
- VM autostart enabled: fw-router, wazuh
- NM dispatcher installed: `/etc/NetworkManager/dispatcher.d/99-soc-lab-routes`
  - Adds 192.168.10.0/24 and 192.168.40.0/24 via 192.168.122.10 on virbr0 up
- Scripts committed to repo: `scripts/host-setup/` (host-network-setup.sh, 99-soc-lab-routes)
- SSH alias updated: `ssh -i ~/.ssh/fw-router-key root@192.168.122.10`

### Created/Updated scripts
- `scripts/sendkey-lib.sh` — full ASCII send-key helper (uppercase + all punctuation)
- `scripts/fw-router/nftables.conf` — final ruleset with management SSH + host→lab-net
- `scripts/fw-router/fw-setup.sh` — complete fw-router post-install setup
- `scripts/host-setup/host-network-setup.sh` — idempotent host networking restore script
- `scripts/host-setup/99-soc-lab-routes` — NM dispatcher script

### Status
- Phase 3: complete
- Phase 4: complete (Suricata verification deferred to Phase 3b)
- Phase 3b: pending — next up (Suricata on fw-router + aurora)
- Phase 5 (Splunk): pending

## Session 6: 2026-03-03

### Startup & Boot Verification
- User rebooted host — confirmed all VMs come back up cleanly
- Three root causes found and fixed:

**Issue 1: virsh wrong URI**
- `virsh` defaults to `qemu:///session`; VMs are on `qemu:///system`
- Always use `virsh --connect qemu:///system`

**Issue 2: NM grabbing virbr0 (blocks libvirt default network)**
- NM had a bridge profile for virbr0, recreating it at boot before libvirt could claim it
- Fixed: `nmcli con delete virbr0` + created `/etc/NetworkManager/conf.d/unmanaged-libvirt.conf`
  - Content: `[keyfile]` / `unmanaged-devices=interface-name:virbr*,interface-name:vnet*,interface-name:veth*`

**Issue 3: nftables loading wrong file (SSH blocked to fw-router)**
- Alpine nftables init loads `/etc/nftables.nft`, not `/etc/nftables.conf`
- Management SSH rule was only in `.conf`; `.nft` had the old pre-management ruleset
- Fixed: `cp /etc/nftables.conf /etc/nftables.nft && rc-service nftables reload` on fw-router
- Confirmed all rules correct and persistent after reboot

### Status after Session 6 (final)
- Phase 3: complete and reboot-persistent ✓
- Phase 4: Wazuh running, dashboard at https://192.168.10.10 ✓
- lab-sandbox NIC removed from fw-router + wazuh (lab-sandbox network disabled — libvirt bug)
- soc-lab-routes.service: installed, enabled, adds routes on every boot
- **Next:** Phase 3b — Suricata on fw-router (Tier 1) + aurora host (Tier 2)

## Session 8: 2026-03-04

### Phase 3b: Suricata — Perimeter + Internal NIDS (complete)

**Tier 1 (fw-router):**
- Bumped fw-router RAM 512MB → 1GB (virsh setmaxmem/setmem, reboot)
- Installed Suricata 8.0.3 from Alpine edge/community (not in 3.23 main)
  - suricata-update auto-fetches ET Open rules on install (~48k rules enabled)
  - Configured af-packet on eth1 (lab-net), community-id enabled
- Installed rsyslog; configured imfile→omfwd forwarding to Wazuh :514 (facility local3)
- nftables.nft still had stale eth2 rules — already fixed in Session 7

**Tier 2 (aurora host — Podman containers):**
- Suricata: `jasonish/suricata:latest` on virbr-lab bridge
  - ET Open rules via suricata-update in container (required --network host for DNS)
  - Three volumes: /etc/suricata-internal, /var/lib/suricata-internal, /var/log/suricata/internal
  - Quadlet: `/etc/containers/systemd/suricata-internal.container`
- rsyslog: `rsyslog/syslog_appliance_alpine:latest`
  - Tails /var/log/suricata/internal/eve.json → Wazuh :514 (facility local4)
  - Required Network=host (no host networking = connection refused to 192.168.10.10)
  - Quadlet: `/etc/containers/systemd/rsyslog-suricata.container`

**Wazuh:**
- Added syslog <remote> stanza to ossec.conf: port 514/TCP, allowed-ips 192.168.10.1 + 192.168.122.1
- Verified both sources connected and EVE JSON arriving (confirmed via logall=yes temporarily)
- Suricata decoder (rule 86600/86601) parses event_type fields correctly

**Deployment scripts:**
- `scripts/fw-router/suricata-setup.sh` — full Tier 1 setup from scratch
- `scripts/host-setup/suricata-internal-setup.sh` — full Tier 2 setup from scratch
- `scripts/host-setup/suricata-internal/` — config files and Quadlet units
- `scripts/check-lab.sh` — updated with 7 new Suricata/rsyslog checks (20/20 total)

**Gotchas logged:**
- Suricata not in Alpine 3.23 main — must use edge/community
- suricata-update needs --network host for DNS resolution in container
- suricata-update needs /var/lib/suricata mounted (separate volume) to persist enabled-sources state
- rsyslog container needs Network=host to route to 192.168.10.10 via fw-router
- Wazuh allowed-ips must use 192.168.10.1 (fw-router eth1) not 192.168.122.10 (WAN IP)
- Aurora is image-based — no package layering; all host services run as Podman containers

### Status
- Phase 3b: complete ✓
- Splunk noted as "add-on" — not a blocker for Phases 6–9
- rsyslog → Splunk forwarding (Suricata EVE to both SIEMs) planned for Phase 5
- Blog post series planned covering the full build (post-completion)
- **Next:** Phase 6 (Windows DC) or Phase 9 (Kali — quick win, existing qcow2)

## Session 7: 2026-03-03

### Startup Check
- Both VMs (fw-router, wazuh) running and reachable
- Wazuh dashboard responding (HTTP 302)
- nftables on fw-router was stopped after reboot — root cause: `/etc/nftables.nft` still referenced
  `eth2` (lab-sandbox NIC removed in Session 6). Fixed by removing eth2 rules from `/etc/nftables.nft`.
- Wrote `scripts/check-lab.sh` — comprehensive health check script (12 checks, all green)

### Status
- Lab fully operational ✓
- **Next:** Phase 3b — Suricata on fw-router (Tier 1) + aurora host (Tier 2)

## Session 9: 2026-03-05

### Phase 5: Splunk Enterprise — complete

**Splunk VM:**
- Ubuntu 24.04 autoinstall via seed ISO: 192.168.10.40, labadmin user, SSH key auth
- Splunk Enterprise 10.2.1 installed as `splunk` system user (root deprecated in 10.x)
- Admin password set via user-seed.conf (--seed-passwd unreliable); boot-start via init.d
- Deployment script: `scripts/host-setup/splunk-vm-setup.sh`
- Autoinstall config: `autoinstall/splunk/user-data`

**Suricata EVE → Splunk forwarding:**
- rsyslog on fw-router (Tier 1) dual-forwards to Wazuh :514 AND Splunk :5514
- rsyslog container on aurora (Tier 2) same dual-forward pattern
- Splunk config on VM:
  - Index: `suricata`, TCP input port 5514, sourcetype `suricata:eve`
  - props.conf: KV_MODE=json, time parsing from "timestamp" field
  - transforms.conf: regex strips syslog header, leaving clean JSON as _raw
- Verified: `index=suricata | stats count by event_type` returns alert, dns, flow, ssh, tls

**Traffic generation:**
- `scripts/generate-traffic.sh` — seeds EVE events through both Tier 1 and Tier 2

**Blog notes:**
- `blog-notes.md` — running notes for all planned blog posts; Splunk section complete

**Gotchas:**
- autoinstall paused at "Continue?" prompt — seed ISO present but kernel param not set; typed yes at console
- user-seed.conf must exist before first Splunk start (not --seed-passwd)
- pass stores the Splunk admin password but terminal displays it with \! (shell ! escaping) — actual password has no backslash

### Status
- Phase 5: complete ✓
- Both SIEMs (Wazuh + Splunk) receiving Suricata EVE from Tier 1 and Tier 2
- Blog write-up planned for next session

## Session 10: 2026-03-07

### Blog & Portfolio
- Published "Forwarding rsyslog to Splunk Without a Universal Forwarder" to brettlyons.dev
  - Conference anecdote (Wild West Hackin' Fest) added
  - Screenshot (`splunk_suricata_index.png`) added to Verification section
  - IoT gateways added as a use case
  - AI disclosure footer added
- `brettlyons/soc-lab` GitHub repo made public
  - Scrubbed all plaintext credentials from files and full git history (git-filter-repo)
  - All passwords stored in pass under `soc-lab/`
  - git-filter-repo installed via brew for future use

### Status
- Blog post (rsyslog→Splunk): published ✓
- Repo: public ✓
- **Next:** Phase 6 (Windows DC) or Phase 9 (Kali)
- **Next:** Blog post write-up, then Phase 6 (Windows DC) or Phase 9 (Kali)

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-03-01 | virsh send-key uppercase letters dropped silently | multiple | Avoid uppercase in all send-key commands |
| 2026-03-01 | -O flag (uppercase O) garbled in wget via send-key | 1 | User manually moved file; use -o or redirect instead |
| 2026-03-01 | Alpine live ISO loses state on VM reboot | 1 | Must run setup-alpine to install to disk before rebooting |
| 2026-03-01 | HTTP server blocked by firewalld from VM | 1 | sudo firewall-cmd --zone=libvirt --add-port=8080/tcp |
| 2026-03-03 | virsh shows no VMs after reboot | 1 | Wrong URI — use qemu:///system not qemu:///session |
| 2026-03-03 | libvirt default network stuck inactive after reboot | 1 | NM managed virbr0 — deleted NM profile, added unmanaged-libvirt.conf |
| 2026-03-03 | SSH to fw-router blocked after reboot | 1 | nftables.nft (loaded by init) lacked management SSH rule; cp nftables.conf → nftables.nft |
| 2026-03-03 | virsh send-key KEY_PERIOD invalid | 1 | Use KEY_DOT for period character |
| 2026-03-03 | NM unmanaged-libvirt.conf broke route persistence | 1 | NM dispatcher never fires for unmanaged interfaces. Fixed: systemd unit soc-lab-routes.service adds routes after virtnetworkd |
| 2026-03-03 | libvirt hook SELinux denial (exit 126) caused all networks to fail autostart | 1 | Required virt_hooks_unconfined boolean AND system_u SELinux context. Too fragile — removed hook entirely |
| 2026-03-03 | lab-sandbox "already in use by virbr0" on every start attempt | ongoing | Unknown libvirt internal state bug. Workaround: removed lab-sandbox NIC from fw-router + wazuh; lab-sandbox disabled until Phase 10 |

## Session 13: 2026-03-11

### Phase 3c: dnsmasq DNS + DHCP on fw-router — complete

- Integrated BHIS homelab checklist (`~/workspace/home_soc_story/bhis_homelab_checklist.md`)
  - Mapped all checklist items to existing phases
  - Added Phase 3c (DNS/DHCP), webservers, attack scenarios, CIS hardening to task_plan.md
- Installed dnsmasq 2.91 on fw-router (`apk add dnsmasq`)
- Single source of truth: `scripts/fw-router/dnsmasq.conf`
- Deploy: `bash scripts/fw-router/dnsmasq-setup.sh` (host-side; install → SCP conf → restart)
- **DNS verified** from Wazuh VM (`dig @192.168.10.1`):
  - fw-router.lab.local → 192.168.10.1 ✓
  - wazuh.lab.local → 192.168.10.10 ✓
  - splunk.lab.local → 192.168.10.40 ✓
  - win-forensic.lab.local → 192.168.10.50 ✓
- **DHCP** configured: range 192.168.10.100–200, options 3/6/15/66
  - Static reservations: wazuh, splunk, win-forensic by MAC
  - DHCP lease test: pending next VM join
- Gotcha: `expand-hosts` in dnsmasq picked up `127.0.0.1 fw-router` from /etc/hosts on fw-router
  — removed `expand-hosts`; explicit `address=` records are sufficient

### Status
- Phase 3c: complete ✓
- **Next:** Phase 7 (win-forensic — Splunk UF + forensic tools) or Phase 6 (DC01)

## Session 12: 2026-03-09

### Phase 7: win-forensic — RDP + clipboard working

- Diagnosed boot failure: `/dev/kvm` owned by `systemd-network` instead of `kvm` group
  - libvirt private devns couldn't bind-mount /dev/kvm → QEMU saw ENOENT
  - Temp fix: `sudo chown root:kvm /dev/kvm && sudo chmod 0666 /dev/kvm`
  - Permanent fix pending next reboot test: `/etc/udev/rules.d/99-kvm.rules`
- Switched from SPICE to RDP for win-forensic console access
  - SPICE clipboard requires `spice-vdagentd` on host (not easily installed on Aurora image-based OS)
  - RDP clipboard works natively and is cleaner for Windows VMs
  - `scripts/rdp-forensic.sh`: xfreerdp with 4K/HiDPI scaling, password via `/args-from:stdin`
- Confirmed Autounattend.xml already enables RDP at FirstLogon (Order 4)

### Status
- Phase 7: in_progress — RDP working, static IP 192.168.10.50 confirmed
- **Next:** Wazuh agent, Sysmon, Splunk UF on win-forensic; then Phase 6 (DC01)

## Session 11: 2026-03-08

### Phase 7 (partial): Forensic Windows Workstation
- Created `win11-forensic/` directory with:
  - `Autounattend.xml` (template — ANALYST_PASS_PLACEHOLDER, no creds in git)
  - `build-iso.sh` (reads password from `pass soc-lab/windows-analyst`, substitutes, builds ISO)
- Password stored in `pass` under `soc-lab/windows-analyst`
- Built `Win11_forensic_unattended.iso` (7.6GB, Win11 Pro + VirtIO drivers + Autounattend.xml)
- Created `win-forensic` VM: 4GB RAM, 2 vCPU, 60GB qcow2, lab-net (VirtIO NIC)
- VM started — Windows install in progress
- Hostname: WIN-FORENSIC, user: analyst (local admin)
- FirstLogon: SPICE tools, PowerShell RemoteSigned, WinRM, RDP, C:\Tools directories, Defender RT off
- VM MAC: 52:54:00:e2:4c:3f (assign static IP via libvirt DHCP or manual)

### Status
- Windows install in progress
- **Next:** Verify install completes, confirm login, assign static IP 192.168.10.50
- **Next (Phase 7):** Wazuh agent, Sysmon, Splunk UF
