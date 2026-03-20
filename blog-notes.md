# SOC Lab Blog Notes

A running log of decisions, gotchas, and insights for turning this build into
blog posts. Written as things happen — rough notes to be shaped into posts later.

---

## Post Series Outline

1. **Architecture & Network Design** — why this layout, what each tier catches
2. **Firewall VM** — Alpine + nftables, why not OPNsense
3. **NIDS: Suricata Dual-Tier** — perimeter + internal, EVE JSON, rsyslog forwarding
4. **SIEM: Wazuh** — autoinstall, EVE decoding, syslog receiver
5. **Log Analysis: Splunk** — setup, EVE ingestion, SPL queries on Suricata data
6. **Windows AD + Detection** — DC, Sysmon, Atomic Red Team
7. **Putting It Together** — ART runs, detections across all tiers

---

## Post 1: Architecture & Network Design

### Why a dedicated firewall VM instead of host-based routing?
- Forces all lab traffic through a single choke point — realistic enterprise topology
- nftables runs entirely inside an Alpine VM; easy to snapshot, rebuild, script
- Separates firewall concerns from the hypervisor — closer to how real environments work

### The three-tier NIDS model
Most home SOC labs put Suricata on one box and call it done. The problem:
intra-subnet VM-to-VM traffic never crosses the router — it's switched at L2 by
the hypervisor bridge and is invisible to a perimeter sensor.

Solution: two Suricata instances.
- **Tier 1** on fw-router eth1 (lab-net facing) — catches north-south traffic:
  C2 callbacks, exfil, inbound scans, internet-bound anomalies
- **Tier 2** on the aurora host itself, listening on virbr-lab — catches east-west
  lateral movement between VMs that never touches the router

This mirrors an enterprise setup where you'd have a perimeter IDS and a core
switch SPAN port feeding an internal sensor.

### Why Alpine for the firewall?
- Original plan was OPNsense, switched after realising the web UI / interactive
  console made scripted deployment painful via virsh send-key
- Alpine boots in ~512MB RAM, nftables config is a single readable text file,
  `setup-alpine` is fully scriptable
- Downside: no pre-built Wazuh agent (glibc vs musl) — solved with rsyslog forwarding

### Why containers for host-side services on Aurora?
- Aurora OS is image-based (Universal Blue / Fedora Kinoite). Adding packages
  via `rpm-ostree` breaks the clean image update chain — you'd need to build a
  custom base image to keep getting updates properly
- Podman + Quadlet systemd units give the same result without touching the base OS
- Everything is reproducible from scripts in the repo

---

## Post 3: NIDS — Suricata Dual-Tier

### Suricata not in Alpine 3.23 main
`apk add suricata` fails on Alpine 3.23 — the package only exists in
`edge/community`. Must use:
```sh
apk add --repository http://dl-cdn.alpinelinux.org/alpine/edge/community suricata
```
The postinstall script auto-runs suricata-update and fetches ET Open rules (~48k
rules, ~48k enabled) — no manual rule download step needed.

### community-id: why bother?
community-id is a hash of the 5-tuple (src/dst IP+port, proto) that's the same
across Suricata, Zeek, and other tools. Enables correlation between Suricata alerts
and flow records even when session IDs differ. Worth enabling — zero cost.

### Why rsyslog instead of a Wazuh agent on fw-router?
Wazuh agent binaries are compiled against glibc. Alpine Linux uses musl libc.
They're binary-incompatible. Options considered:
- Build Wazuh agent from source on Alpine (painful, fragile)
- Run agent in a container on fw-router (possible but adds complexity to a VM
  that's already resource-constrained at 1GB RAM)
- Forward via syslog — Wazuh has a built-in syslog receiver and Suricata decoder

Syslog forwarding won. rsyslog's `imfile` module tails the EVE JSON file and
ships each line as a syslog message to Wazuh port 514/TCP.

### Key gotcha: allowed-ips uses eth1 IP, not WAN IP
When fw-router connects to Wazuh at 192.168.10.10, the source IP is 192.168.10.1
(eth1 — same subnet). The WAN IP (192.168.122.10) is never used for this connection.
Wazuh's `<allowed-ips>` must list `192.168.10.1`, not `192.168.122.10`.

### suricata-update in a container needs --network host
The jasonish/suricata container image includes suricata-update. Running it to
fetch ET Open rules requires internet access. Without `--network host`, the
container's DNS fails:
```
Error: [Errno -2] Name or service not known
```
Add `--network host` to the suricata-update run. Also: `/var/lib/suricata` must
be a separate mounted volume — that's where suricata-update stores the enabled
sources list. If it's not persisted, `enable-source et/open` is lost between runs.

---

## Standalone Post: Forwarding rsyslog to Splunk (without a Universal Forwarder)

**Status:** Ready to write. All configs working, data verified in Splunk.
**Audience:** Security engineers / blue teamers who need to get structured logs into Splunk
from a host that can't run a Splunk UF (musl libc, embedded device, container, etc.)
**Origin:** Someone at a conference asked about this exact pattern.

### The problem
Splunk's Universal Forwarder requires glibc. Alpine Linux uses musl — they're binary
incompatible. Same issue applies to embedded devices, minimal containers, etc.
The UF is also heavier than necessary when you only need to forward one log file.

### The solution: rsyslog imfile → Splunk TCP input
rsyslog's `imfile` module tails a file and ships each line as a syslog message.
Splunk has a built-in TCP input that receives those messages. A `transforms.conf`
stanza strips the syslog header, leaving clean JSON as `_raw`.

### Full rsyslog config (see scripts/fw-router/50-suricata-wazuh.conf)
```
module(load="imfile" PollingInterval="5")

input(type="imfile"
      File="/var/log/suricata/eve.json"
      Tag="suricata-eve"
      Severity="info"
      Facility="local3"
      PersistStateInterval="10"
      ReadMode="0"
      FreshStartTail="on"
      StateFile="suricata-eve")

if $syslogfacility-text == 'local3' then {
    action(type="omfwd"
           Target="192.168.10.10"
           Port="514"
           Protocol="tcp"
           Template="RSYSLOG_SyslogProtocol23Format")
    action(type="omfwd"
           Target="192.168.10.40"
           Port="5514"
           Protocol="tcp"
           Template="RSYSLOG_SyslogProtocol23Format")
    stop
}
```

### Full Splunk config
**props.conf** (`/opt/splunk/etc/apps/search/local/props.conf`):
```ini
[suricata:eve]
SHOULD_LINEMERGE = false
KV_MODE = json
TIME_PREFIX = "timestamp":"
TIME_FORMAT = %Y-%m-%dT%H:%M:%S.%6N%z
TRANSFORMS-strip_syslog_header = strip_syslog_header
```

**transforms.conf** (`/opt/splunk/etc/apps/search/local/transforms.conf`):
```ini
[strip_syslog_header]
REGEX = ^[^{]*(\{.+\})$
FORMAT = $1
DEST_KEY = _raw
```

**Splunk inputs.conf** (TCP input, port 5514, index=suricata, sourcetype=suricata:eve)
— created via Splunk web UI: Settings → Data Inputs → TCP

### Key points for the post
- `imfile` tails any file — not just syslog-format logs; works with EVE JSON, audit logs, etc.
- Two `action()` blocks in one `if` = dual-forward to Wazuh AND Splunk simultaneously; one config, two SIEMs
- Port 5514 (not 514) avoids collision with other syslog receivers; TCP not UDP for reliability
- The regex in transforms.conf: `^[^{]*(\{.+\})$` — skips everything before the first `{`
  This strips the syslog header (timestamp, hostname, tag) leaving only the JSON payload as _raw
- `KV_MODE = json` does all field extraction automatically — no field aliases needed
- `FreshStartTail = on` means rsyslog only ships new lines after startup — avoids replaying the whole file on restart

### Verification SPL
```spl
index=suricata | stats count by event_type
index=suricata event_type=alert | table _time, src_ip, dest_ip, alert.signature
```

---

## Standalone Post: Provisioning a Bare-Metal Hypervisor with Fedora CoreOS + Ignition

**Status:** Ready to write. Process completed and verified.
**Audience:** Homelabbers / security folks who want a reproducible, cattle-not-pets hypervisor
**Hook:** One USB drive, three reboots, and a fully configured KVM hypervisor appears — no clicking, no forgetting configs.

### The problem with traditional installs

Every time you reinstall a hypervisor host you go through the same ritual: click through
the installer, set the hostname, create the user, install packages, copy configs, set up
libvirt networks, enable services. It works, but it's manual and error-prone. Six months
later you rebuild and realise you forgot a config you didn't write down.

Fedora CoreOS + Ignition flips this. The machine definition lives in a file in your git
repo. The USB drive carries that definition. Boot, install, walk away.

### What is Ignition?

Ignition is a first-boot provisioning system built into Fedora CoreOS. Unlike cloud-init
(which runs on every boot), Ignition runs exactly once — during the initial install — and
applies your config atomically before the machine is ever handed to you. By the time you
can SSH in, everything is already in place: users, SSH keys, files, systemd units, the
works.

The human-editable format is **Butane** (`.bu`) — a clean YAML dialect. You compile it
to the actual JSON Ignition format (`.ign`) before provisioning.

### What is ucore-hci?

ucore-hci is a Universal Blue image — a custom Fedora CoreOS image that ships with
KVM/libvirt, Podman, and Cockpit pre-installed. It's purpose-built for bare-metal
hypervisor duty. No extra packages needed; you boot into a machine that already knows
how to run VMs.

Because CoreOS uses `rpm-ostree` (immutable base image), you can't just `dnf install`
things at will. ucore-hci solves this by baking the right packages into the image itself.
For anything else — host-side services like Suricata — you run Podman containers instead
of layering packages.

### The autorebase two-step

ucore-hci doesn't have its own ISO. You boot the standard Fedora CoreOS live ISO and
let two systemd oneshot services handle the image swap:

1. **Boot 1** (vanilla CoreOS): `ucore-unsigned-autorebase.service` fires, rebases to
   `ostree-unverified-registry:ghcr.io/ublue-os/ucore-hci:stable`, creates a sentinel
   file, disables itself, reboots.
2. **Boot 2** (unsigned ucore): `ucore-signed-autorebase.service` fires, rebases to
   `ostree-image-signed:docker://ghcr.io/ublue-os/ucore-hci:stable` (cosign-verified),
   creates its sentinel, disables itself, reboots.
3. **Boot 3+**: Both sentinel files exist, neither service fires — normal operation.

The sentinel pattern (`ConditionPathExists=!/etc/ucore-autorebase/unverified` etc.)
comes directly from the official ublue-os/ucore examples. Don't invent your own
guard logic here — the official pattern is what it is for good reason.

### What goes in the Ignition config

The full config lives at `ignition/ucore-hci.bu` in this repo. Key sections:

- **Users + SSH key** — blyons account, wheel/libvirt/kvm groups, passwordless sudo
- **NetworkManager unmanaged config** — prevents NM from grabbing virbr* at boot
  (a real gotcha: NM will steal virbr0 before libvirt can claim it, breaking the
  default NAT network on every reboot — learned the hard way on aurora, baked in here)
- **systemd-resolved stub zone** — routes `*.lab.local` queries to fw-router dnsmasq
- **Kerberos LAB realm config** — so xfreerdp NLA works with domain accounts out of the box
- **libvirt network XML** — lab-net definition dropped into /etc/soc-lab/ for first-boot script
- **Podman Quadlet units** — Suricata Tier 2 + rsyslog EVE forwarder, auto-start via systemd
- **soc-lab-first-boot.service** — one-shot: defines libvirt networks, DHCP reservation, storage pool
- **soc-lab-routes.service** — adds 192.168.10.0/24 + 192.168.40.0/24 routes via fw-router after virtnetworkd starts
- **Nightly shutdown timer** — powers off at 21:00, rtcwake programs RTC alarm for 08:00

### Embedding Ignition into the live ISO

The live ISO shell has no SSH keys to pull files from another machine. The clean
solution: embed the `.ign` file directly into the ISO using `coreos-installer`.
Then the USB is fully self-contained — no network, no key exchange needed.

```bash
# 1. Compile Butane → Ignition (use Podman since Aurora is image-based)
podman run --rm -i quay.io/coreos/butane:release \
  --strict < ignition/ucore-hci.bu > ignition/ucore-hci.ign

# 2. Embed into a working copy of the ISO
cp ~/Downloads/fedora-coreos-*-live.x86_64.iso ~/Downloads/fedora-coreos-lefthand.iso

podman run --rm \
  -v ~/Downloads:/data:z \
  -v $(pwd)/ignition:/ign:z \
  quay.io/coreos/coreos-installer:release \
  iso ignition embed /data/fedora-coreos-lefthand.iso \
  --ignition-file /ign/ucore-hci.ign

# 3. Verify the embed before writing to USB
podman run --rm \
  -v ~/Downloads:/data:z \
  quay.io/coreos/coreos-installer:release \
  iso ignition show /data/fedora-coreos-lefthand.iso | python3 -m json.tool > /dev/null \
  && echo "Valid JSON" || echo "INVALID — do not write to USB"

# 4. Write to USB
sudo dd if=~/Downloads/fedora-coreos-lefthand.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Note: `coreos-installer iso ignition embed` modifies a file, not a block device. Work
on the ISO file, then verify, then `dd` to USB — not the other way around.

### The install

The live ISO requires *some* Ignition config to boot — without one,
`ignition-fetch-offline.service` fails and pulls the system into emergency mode.
The fix: serve a minimal config just to get the live environment up, then run
`coreos-installer` from there with the real config.

**Step 1 — serve two configs from aurora:**
```bash
cd /var/home/blyons/workspace/soc-lab/ignition
python3 -m http.server 8080
```

`live-boot.ign` — minimal config, just adds your SSH key to the `core` user:
```json
{"ignition":{"version":"3.4.0"},"passwd":{"users":[{"name":"core","sshAuthorizedKeys":["YOUR_SSH_PUBKEY"]}]}}
```

**Step 2 — at the GRUB menu on the target machine, press `e` and add:**
```
ignition.config.url=http://<aurora-ip>:8080/live-boot.ign
```
`Ctrl+X` to boot. The live environment comes up and your SSH key is authorised.

**Step 3 — SSH in from aurora and run the installer:**
```bash
ssh core@<lefthand-ip>
lsblk   # confirm disk name
sudo coreos-installer install /dev/nvme0n1 \
  --ignition-url http://<aurora-ip>:8080/ucore-hci.ign \
  --insecure-ignition
```

`--insecure-ignition` is required when fetching over plain HTTP (not HTTPS).
The installer writes CoreOS + your ignition config to disk and exits cleanly.

**Step 4 — reboot, remove USB.** Three automatic reboots for the ucore-hci
autorebase, then the machine is fully provisioned.

Three boots later: fully provisioned ucore-hci hypervisor, all lab services running.

### Why this matters for a SOC lab

The hypervisor is the most tedious machine to rebuild. Every config detail that lives
only in your head is technical debt. Ignition moves that debt into a git repo. When
(not if) the hardware dies or gets wiped, recovery is: compile, embed, boot. The VMs
come back via rsync from a backup. No tribal knowledge required.

### Gotchas

- `.ign` files are JSON and contain your SSH pubkey in plaintext — gitignore them if
  your repo is public. The `.bu` source (no secrets) is what you commit.
- SecureBoot: if the machine has it enabled, you'll need to enroll the ublue-os MOK key
  after the first successful boot (`sudo mokutil --import /etc/pki/akmods/certs/akmods-ublue.der`).
  Easiest to just disable SecureBoot in BIOS on a lab machine.
- `--bypass-driver` flag in the rebase commands: required because rpm-ostree's default
  driver detection can fail on first boot before the image is fully settled.
- **Don't use `2>&1` when compiling Butane.** `podman run ... > ucore-hci.ign 2>&1` mixes
  podman's image pull progress messages into the output file. The `.ign` ends up starting
  with `Trying to pull...` instead of `{`, and Ignition fails with "invalid character T
  at line 1 col 2". Always redirect only stdout: `> ucore-hci.ign` with no `2>&1`.
- The `sleep 8` in `soc-lab-routes.service`: virtnetworkd.service reports active before
  virbr0 is actually up. Without the sleep, `ip route replace` races and loses.
  Ugly but reliable.

---

## Post 5: Log Analysis — Splunk

### Setup notes (in progress)

**Version:** Splunk Enterprise 10.2.1

**Install method:** .deb package, manual download from splunk.com (requires free account)
- URL format: `https://download.splunk.com/products/splunk/releases/<ver>/linux/splunk-<ver>-<hash>-linux-amd64.deb`
- The build hash in the filename is version-specific — get the exact URL from the download page

**Running as root is deprecated in 10.x.**
Create a dedicated `splunk` system user and start with `-u splunk`:
```sh
sudo useradd -r -m -s /bin/bash splunk
sudo chown -R splunk:splunk /opt/splunk
sudo -u splunk /opt/splunk/bin/splunk start --accept-license --answer-yes --no-prompt
```

**Setting admin password non-interactively:**
The `--seed-passwd` flag didn't work reliably in testing. Use `user-seed.conf` instead:
```ini
# /opt/splunk/etc/system/local/user-seed.conf
[user_info]
USERNAME = admin
PASSWORD = YourPasswordHere
```
Create this file before first start. Splunk reads it on startup and removes it.

**Boot-start:**
```sh
sudo /opt/splunk/bin/splunk enable boot-start -user splunk
```
Installs an init.d script. Splunk starts as the splunk user on boot.

**UF receiver:**
```sh
sudo -u splunk /opt/splunk/bin/splunk enable listen 9997 -auth admin:password
```


### Dual-forwarding EVE JSON to Wazuh AND Splunk

rsyslog supports multiple `action()` blocks in a single `if` block. Adding Splunk
as a second target is as simple as adding a second `omfwd` action before the `stop`:

```
if $syslogfacility-text == 'local3' then {
    action(type="omfwd" Target="192.168.10.10" Port="514" ...)   # Wazuh
    action(type="omfwd" Target="192.168.10.40" Port="5514" ...)  # Splunk
    stop
}
```

Both Tier 1 (fw-router rsyslog) and Tier 2 (rsyslog container on aurora) use
this pattern. No agent needed on either host.

**Splunk input config:**
- Index: `suricata`
- TCP input: port 5514
- Sourcetype: `suricata:eve`
- props.conf: `KV_MODE = json` — Splunk auto-extracts all EVE JSON fields
- transforms.conf: regex to strip syslog header, leaving clean JSON as `_raw`

**Splunk port choice:** Used 5514 (not 514) to avoid collision with Wazuh's
syslog receiver. Both listen on their respective VMs so there's no actual
conflict, but different ports make firewall rules and troubleshooting cleaner.

### First SPL queries to verify data

```spl
| Confirm data is flowing
index=suricata | stats count by event_type

| Recent alerts only
index=suricata event_type=alert | table _time, src_ip, dest_ip, dest_port, alert.signature, alert.severity

| Top talkers by destination
index=suricata event_type=flow | stats sum(flow.bytes_toserver) as bytes by dest_ip | sort -bytes

| DNS queries seen by Suricata
index=suricata event_type=dns dns.type=query | table _time, src_ip, dns.rrname, dns.rcode

| TLS connections with SNI
index=suricata event_type=tls | table _time, src_ip, dest_ip, tls.sni, tls.version
```

