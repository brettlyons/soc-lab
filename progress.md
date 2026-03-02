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
- Root password: REDACTED
- PermitRootLogin: prohibit-password (key auth only — correct)
- **Status:** SSH working, ready for nftables + Suricata config
- Scripts saved to `scripts/fw-router/`: alpine-answers, fw-install.sh, fw-addkey.sh, fw-mvkey.sh

### Pending (Phase 3)
- [ ] Enable IP forwarding (sysctl net.ipv4.ip_forward=1)
- [ ] Configure static IPs on eth1 (192.168.10.1) and eth2 (192.168.40.1)
- [ ] Write nftables ruleset (NAT lab-net→WAN, block sandbox→WAN)
- [ ] Install Suricata + ET Open rules
- [ ] Configure rsyslog → Wazuh UDP 514

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| 2026-03-01 | virsh send-key uppercase letters dropped silently | multiple | Avoid uppercase in all send-key commands |
| 2026-03-01 | -O flag (uppercase O) garbled in wget via send-key | 1 | User manually moved file; use -o or redirect instead |
| 2026-03-01 | Alpine live ISO loses state on VM reboot | 1 | Must run setup-alpine to install to disk before rebooting |
| 2026-03-01 | HTTP server blocked by firewalld from VM | 1 | sudo firewall-cmd --zone=libvirt --add-port=8080/tcp |
