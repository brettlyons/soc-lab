#!/usr/bin/env bash
# suricata-internal-setup.sh — Deploy Tier 2 Suricata + rsyslog on aurora host
#
# Run as root (or with sudo) on the aurora host.
#
# What this does:
#   1. Creates host directories for config, data, and logs
#   2. Patches suricata.yaml for virbr-lab interface + community-id
#   3. Runs suricata-update in container to fetch ET Open rules (~48k enabled)
#   4. Installs Quadlet units for suricata-internal and rsyslog-suricata
#   5. Installs rsyslog.conf for EVE → Wazuh forwarding
#   6. Starts both services
#
# Prerequisites:
#   - Podman installed on aurora
#   - virbr-lab bridge active (run host-network-setup.sh first if needed)
#   - Wazuh ossec.conf has syslog remote stanza allowing 192.168.122.1
#
# Images used:
#   - docker.io/jasonish/suricata:latest  (Tier 2 NIDS)
#   - docker.io/rsyslog/syslog_appliance_alpine:latest  (EVE log forwarder)
#
# Notes:
#   - Suricata watches virbr-lab (east-west / internal bridge), NOT an internet interface
#   - rsyslog tails /var/log/suricata/internal/eve.json and forwards via TCP syslog
#     to Wazuh at 192.168.10.10:514 (facility local4)
#   - Source IP seen by Wazuh: 192.168.122.1 (aurora's virbr0 gateway IP)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/suricata-internal"
WAZUH_IP="192.168.10.10"

echo "=== Creating host directories ==="
mkdir -p /etc/suricata-internal
mkdir -p /var/lib/suricata-internal
mkdir -p /var/log/suricata/internal
mkdir -p /etc/rsyslog-suricata
mkdir -p /var/lib/rsyslog-suricata

echo "=== Pulling container images ==="
podman pull docker.io/jasonish/suricata:latest
podman pull docker.io/rsyslog/syslog_appliance_alpine:latest

echo "=== Extracting default Suricata config from container ==="
podman run --rm docker.io/jasonish/suricata:latest \
    cat /etc/suricata/suricata.yaml > /tmp/suricata-internal.yaml

echo "=== Patching Suricata config for virbr-lab + community-id ==="
python3 - << 'PYEOF'
import re
content = open('/tmp/suricata-internal.yaml').read()
# Switch af-packet interface from eth0 to virbr-lab
content = re.sub(r'(af-packet:\n  - interface: )eth0', r'\1virbr-lab', content)
# Enable community-id
content = content.replace('      community-id: false\n', '      community-id: true\n', 1)
open('/etc/suricata-internal/suricata.yaml', 'w').write(content)
print("Patched: af-packet=virbr-lab, community-id=true")
PYEOF

echo "=== Updating ET Open rules (suricata-update in container) ==="
# update-sources fetches the sources index from openinfosecfoundation.org
podman run --rm --network host \
    -v /etc/suricata-internal:/etc/suricata:z \
    -v /var/lib/suricata-internal:/var/lib/suricata:z \
    --entrypoint /usr/bin/suricata-update \
    docker.io/jasonish/suricata:latest \
    update-sources

# enable-source adds ET Open to the enabled sources list
podman run --rm --network host \
    -v /etc/suricata-internal:/etc/suricata:z \
    -v /var/lib/suricata-internal:/var/lib/suricata:z \
    --entrypoint /usr/bin/suricata-update \
    docker.io/jasonish/suricata:latest \
    enable-source et/open

# Download and install rules
podman run --rm --network host \
    -v /etc/suricata-internal:/etc/suricata:z \
    -v /var/lib/suricata-internal:/var/lib/suricata:z \
    -v /var/log/suricata/internal:/var/log/suricata:z \
    --entrypoint /usr/bin/suricata-update \
    docker.io/jasonish/suricata:latest

echo "=== Installing rsyslog config ==="
cp "${SCRIPT_DIR}/rsyslog.conf" /etc/rsyslog-suricata/rsyslog.conf

echo "=== Installing Quadlet container units ==="
cp "${SCRIPT_DIR}/suricata-internal.container" /etc/containers/systemd/
cp "${SCRIPT_DIR}/rsyslog-suricata.container" /etc/containers/systemd/

echo "=== Starting services ==="
systemctl daemon-reload
systemctl start suricata-internal.service
systemctl start rsyslog-suricata.service

echo "=== Status ==="
systemctl status suricata-internal.service --no-pager | head -8
systemctl status rsyslog-suricata.service --no-pager | head -8

echo ""
echo "=== Done ==="
echo "Tier 2 Suricata watching virbr-lab → EVE: /var/log/suricata/internal/eve.json"
echo "rsyslog forwarding EVE to Wazuh at ${WAZUH_IP}:514"
echo "Verify: podman logs rsyslog-suricata (should show no connection errors)"
echo "Verify: on Wazuh, grep '192.168.122.1' /var/ossec/logs/ossec.log"
