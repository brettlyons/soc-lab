#!/usr/bin/env sh
# suricata-setup.sh — Install and configure Suricata (Tier 1) on fw-router
#
# Run this on fw-router as root:
#   ssh -i ~/.ssh/fw-router-key root@192.168.122.10 'sh -s' < suricata-setup.sh
#
# Prerequisites:
#   - fw-router running Alpine Linux with internet access
#   - nftables already configured
#   - RAM bumped to 1GB (see host side: virsh --connect qemu:///system setmaxmem fw-router 1048576 --config)
#
# What this does:
#   1. Installs Suricata 8.x from Alpine edge/community
#      (not in Alpine 3.23 main — must use edge/community repo)
#   2. Switches af-packet interface from eth0 to eth1 (lab-net facing)
#   3. Enables community-id in EVE JSON output
#   4. Adds Suricata to default runlevel and starts it
#      (suricata-update runs automatically on install, fetches ET Open rules)
#   5. Installs rsyslog, configures imfile to tail eve.json, forwards to Wazuh
#      via TCP syslog on port 514 (facility local3)
#
# Wazuh side: ossec.conf must have a <remote> syslog stanza allowing 192.168.10.1
# (fw-router's eth1 IP is the source when connecting to Wazuh on lab-net).

set -e

WAZUH_IP="192.168.10.10"

echo "=== Installing Suricata from Alpine edge/community ==="
apk update
apk add --repository http://dl-cdn.alpinelinux.org/alpine/edge/community suricata

echo "=== Configuring Suricata ==="
# Switch af-packet interface from eth0 to eth1 (lab-net)
sed -i '/^af-packet:/,/^[^ ]/ s/- interface: eth0/- interface: eth1/' /etc/suricata/suricata.yaml
# Enable community-id for SIEM correlation
sed -i '157s/community-id: false/community-id: true/' /etc/suricata/suricata.yaml

echo "=== Testing Suricata config ==="
suricata -T -c /etc/suricata/suricata.yaml

echo "=== Enabling and starting Suricata ==="
rc-update add suricata default
rc-service suricata start
rc-service suricata status

echo "=== Installing rsyslog ==="
apk add rsyslog
mkdir -p /etc/rsyslog.d

echo "=== Configuring rsyslog to forward EVE JSON to Wazuh ==="
cat > /etc/rsyslog.d/50-suricata-wazuh.conf << EOF
# Forward Suricata EVE JSON to Wazuh syslog receiver
module(load="imfile" PollingInterval="5")

input(type="imfile"
      File="/var/log/suricata/eve.json"
      Tag="suricata-eve"
      Severity="info"
      Facility="local3"
      PersistStateInterval="10"
      ReadMode="0"
      FreshStartTail="on")

if \$syslogfacility-text == 'local3' then {
    action(type="omfwd"
           Target="${WAZUH_IP}"
           Port="514"
           Protocol="tcp"
           Template="RSYSLOG_SyslogProtocol23Format")
    stop
}
EOF

echo "=== Validating rsyslog config ==="
rsyslogd -N1

echo "=== Enabling and starting rsyslog ==="
rc-update add rsyslog default
rc-service rsyslog start
rc-service rsyslog status

echo "=== Done ==="
echo "Verify EVE events: tail -f /var/log/suricata/eve.json"
echo "Verify rsyslog forwarding: check Wazuh ossec.log for connections from 192.168.10.1"
