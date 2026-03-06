#!/usr/bin/env bash
# generate-traffic.sh — Generate lab traffic to produce Suricata EVE events
#
# Use this to populate Suricata EVE JSON with realistic events for:
#   - Verifying rsyslog → Wazuh / Splunk forwarding is working
#   - Seeding Splunk/Wazuh with data before writing SPL/KQL queries
#   - Smoke-testing detection coverage after changes
#
# All traffic routes through fw-router (Tier 1) and across virbr-lab (Tier 2).
# Run from aurora host.

set -euo pipefail

WAZUH="192.168.10.10"
SPLUNK="192.168.10.40"
FW_ROUTER="192.168.122.10"
SSH_FW="ssh -i $HOME/.ssh/fw-router-key -o StrictHostKeyChecking=no -o BatchMode=yes root@${FW_ROUTER}"

echo "=== Generating lab traffic ==="

echo "[1] HTTPS to Wazuh dashboard (TLS + HTTP events)..."
for i in $(seq 5); do curl -sk "https://${WAZUH}" > /dev/null; done

echo "[2] HTTP to Splunk web UI (HTTP events)..."
for i in $(seq 5); do curl -sk "http://${SPLUNK}:8000" > /dev/null; done

echo "[3] DNS lookups via fw-router (DNS events)..."
$SSH_FW "nslookup google.com 8.8.8.8 > /dev/null 2>&1; \
         nslookup github.com 8.8.8.8 > /dev/null 2>&1; \
         nslookup example.com 1.1.1.1 > /dev/null 2>&1" || true

echo "[4] ICMP from fw-router to internet (flow events)..."
$SSH_FW "ping -c3 8.8.8.8 > /dev/null 2>&1" || true

echo "[5] SSH probe to fw-router (SSH events on Tier 1)..."
for i in $(seq 3); do
    nc -z -w2 "${FW_ROUTER}" 22 > /dev/null 2>&1 || true
done

echo "[6] Internal east-west traffic (Tier 2 virbr-lab events)..."
ping -c3 "${WAZUH}" > /dev/null 2>&1 || true
ping -c3 "${SPLUNK}" > /dev/null 2>&1 || true

echo ""
echo "=== Traffic generation complete ==="
echo "Wait ~10–15 seconds for rsyslog to ship events, then query:"
echo "  Splunk: index=suricata | stats count by event_type"
echo "  Wazuh:  check /var/ossec/logs/archives/archives.log on Wazuh VM"
