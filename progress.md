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

## 5-Question Reboot Check
| Question | Answer |
|----------|--------|
| Where am I? | Planning complete — blocked on sudo/bridge fix |
| Where am I going? | Networks → OPNsense → Wazuh → Splunk → DC → Win host → Linux sender → Kali → Sandbox |
| What's the goal? | Local SOC/Blue Team lab on aurora — firewall-segmented, 8 VMs |
| What have I learned? | See findings.md |
| What have I done? | Full plan documented, network design finalized, runbook written |

## Error Log
| Timestamp | Error | Attempt | Resolution |
|-----------|-------|---------|------------|
| — | — | — | — |
