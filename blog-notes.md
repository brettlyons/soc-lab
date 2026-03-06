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

