#!/usr/bin/env bash
# fw-setup.sh — Configure fw-router after Alpine install
# Run via: ssh -i ~/.ssh/fw-router-key root@<ip> 'bash -s' < fw-setup.sh
set -euo pipefail

echo "=== fw-router setup ==="

# Static IPs for lab interfaces
cat >> /etc/network/interfaces << 'EOF'

auto eth1
iface eth1 inet static
    address 192.168.10.1
    netmask 255.255.255.0

auto eth2
iface eth2 inet static
    address 192.168.40.1
    netmask 255.255.255.0
EOF

# IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# Bring up interfaces
ifup eth1
ifup eth2

# Install nftables
apk add nftables

# Write nftables ruleset
cat > /etc/nftables.nft << 'NFTEOF'
#!/usr/sbin/nft -f
# eth0=WAN, eth1=lab-net (10.0/24), eth2=lab-sandbox (40.0/24)

flush ruleset

table inet filter {
    chain input {
        type filter hook input priority 0; policy drop;
        iif lo accept
        ct state established,related accept
        iif eth1 accept
        iif eth2 ip daddr 192.168.10.10 accept
        iif eth2 drop
    }

    chain forward {
        type filter hook forward priority 0; policy drop;
        ct state established,related accept
        iif eth1 oif eth0 accept
        iif eth2 oif eth1 ip daddr 192.168.10.10 accept
        iif eth2 drop
    }

    chain output {
        type filter hook output priority 0; policy accept;
    }
}

table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100;
        oif eth0 masquerade
    }
}
NFTEOF

# Load and enable nftables
nft -f /etc/nftables.nft
rc-update add nftables default
rc-service nftables start

echo "=== Done. Verify with: nft list ruleset ==="
