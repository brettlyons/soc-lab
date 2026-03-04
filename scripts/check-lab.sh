#!/usr/bin/env bash
# check-lab.sh — SOC Lab health check
# Verifies VMs are running, networks are active, and key services are reachable.

set -euo pipefail

VIRSH="virsh --connect qemu:///system"
SSH_KEY="$HOME/.ssh/fw-router-key"
SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes"

PASS=0
FAIL=0

ok()   { echo "  [OK]  $*"; PASS=$((PASS+1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL+1)); }
header() { echo; echo "=== $* ==="; }

# ── VMs ──────────────────────────────────────────────────────────────────────
header "VMs"
for vm in fw-router wazuh; do
    state=$($VIRSH domstate "$vm" 2>/dev/null || echo "missing")
    if [[ "$state" == "running" ]]; then
        ok "$vm: $state"
    else
        fail "$vm: $state"
    fi
done

# ── Networks ─────────────────────────────────────────────────────────────────
header "Libvirt networks"
for net in default lab-net; do
    state=$($VIRSH net-info "$net" 2>/dev/null | awk '/^Active:/{print $2}')
    if [[ "$state" == "yes" ]]; then
        ok "net/$net: active"
    else
        fail "net/$net: $state"
    fi
done

# ── IP reachability ───────────────────────────────────────────────────────────
header "Ping"
# fw-router blocks ICMP on eth0 (by design); check with nc instead
if nc -z -w2 192.168.122.10 22 2>/dev/null; then
    ok "fw-router (192.168.122.10): port 22 reachable"
else
    fail "fw-router (192.168.122.10): port 22 unreachable"
fi
if ping -c1 -W2 192.168.10.10 &>/dev/null; then
    ok "wazuh (192.168.10.10): reachable"
else
    fail "wazuh (192.168.10.10): unreachable"
fi
# Verify fw-router correctly drops ICMP on its WAN (eth0/virbr0) interface.
# ping returning non-zero (no reply within timeout) is the expected passing state.
if ping -c1 -W2 192.168.122.10 &>/dev/null; then
    fail "fw-router ICMP block: responded to ping (firewall may be down)"
else
    ok "fw-router ICMP block: no reply (correctly dropped)"
fi

# ── fw-router services ────────────────────────────────────────────────────────
header "fw-router (SSH + services)"
if ssh $SSH_OPTS root@192.168.122.10 true 2>/dev/null; then
    ok "SSH to fw-router"

    nft_status=$(ssh $SSH_OPTS root@192.168.122.10 "rc-service nftables status 2>/dev/null | awk '/status:/{print \$3}'")
    if [[ "$nft_status" == "started" ]]; then
        ok "fw-router nftables: $nft_status"
    else
        fail "fw-router nftables: ${nft_status:-unknown}"
    fi

    chain_count=$(ssh $SSH_OPTS root@192.168.122.10 "nft list ruleset 2>/dev/null | grep -c 'chain'" || echo 0)
    if [[ "$chain_count" -ge 4 ]]; then
        ok "fw-router nft chains: $chain_count loaded"
    else
        fail "fw-router nft chains: $chain_count (expected >=4)"
    fi

    ip_fwd=$(ssh $SSH_OPTS root@192.168.122.10 "cat /proc/sys/net/ipv4/ip_forward")
    if [[ "$ip_fwd" == "1" ]]; then
        ok "fw-router ip_forward: enabled"
    else
        fail "fw-router ip_forward: disabled"
    fi
else
    fail "SSH to fw-router"
fi

# ── Tier 1: Suricata on fw-router ────────────────────────────────────────────
header "Tier 1 Suricata (fw-router)"
if ssh $SSH_OPTS root@192.168.122.10 true 2>/dev/null; then
    suri_status=$(ssh $SSH_OPTS root@192.168.122.10 "rc-service suricata status 2>/dev/null | awk '/status:/{print \$3}'")
    if [[ "$suri_status" == "started" ]]; then
        ok "fw-router Suricata: $suri_status"
    else
        fail "fw-router Suricata: ${suri_status:-unknown}"
    fi

    eve_lines=$(ssh $SSH_OPTS root@192.168.122.10 "wc -l < /var/log/suricata/eve.json 2>/dev/null || echo 0")
    if [[ "$eve_lines" -gt 0 ]]; then
        ok "fw-router EVE JSON: $eve_lines events"
    else
        fail "fw-router EVE JSON: empty or missing"
    fi

    rsys_status=$(ssh $SSH_OPTS root@192.168.122.10 "rc-service rsyslog status 2>/dev/null | awk '/status:/{print \$3}'")
    if [[ "$rsys_status" == "started" ]]; then
        ok "fw-router rsyslog: $rsys_status"
    else
        fail "fw-router rsyslog: ${rsys_status:-unknown}"
    fi
else
    fail "fw-router SSH unreachable — skipping Tier 1 checks"
fi

# ── Tier 2: Suricata container on aurora ──────────────────────────────────────
header "Tier 2 Suricata (aurora host)"
if systemctl is-active --quiet suricata-internal.service 2>/dev/null; then
    ok "suricata-internal.service: active"
else
    fail "suricata-internal.service: not active"
fi

if systemctl is-active --quiet rsyslog-suricata.service 2>/dev/null; then
    ok "rsyslog-suricata.service: active"
else
    fail "rsyslog-suricata.service: not active"
fi

eve2_lines=$(sudo wc -l < /var/log/suricata/internal/eve.json 2>/dev/null || echo 0)
if [[ "$eve2_lines" -gt 0 ]]; then
    ok "aurora EVE JSON (internal): $eve2_lines events"
else
    fail "aurora EVE JSON (internal): empty or missing"
fi

# Verify rsyslog container has an established connection to Wazuh:514
if sudo ss -tnp 2>/dev/null | grep -q "192.168.10.10:514"; then
    ok "rsyslog-suricata → Wazuh :514: connection established"
else
    fail "rsyslog-suricata → Wazuh :514: no connection"
fi

# ── Wazuh dashboard ───────────────────────────────────────────────────────────
header "Wazuh dashboard (https://192.168.10.10)"
http_code=$(curl -sk --max-time 8 -o /dev/null -w "%{http_code}" https://192.168.10.10 2>/dev/null || echo 0)
if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
    ok "Wazuh dashboard: HTTP $http_code"
else
    fail "Wazuh dashboard: HTTP $http_code (expected 200/302)"
fi

# ── Host routes ───────────────────────────────────────────────────────────────
header "Host routes"
if ip route show 192.168.10.0/24 | grep -q "192.168.10.0"; then
    ok "route 192.168.10.0/24 present"
else
    fail "route 192.168.10.0/24 missing (run: bash scripts/host-setup/host-network-setup.sh)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo
echo "─────────────────────────────"
echo "  Passed: $PASS   Failed: $FAIL"
echo "─────────────────────────────"
[[ "$FAIL" -eq 0 ]]
