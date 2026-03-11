#!/usr/bin/env bash
# nftables-deploy.sh — Push nftables.nft to fw-router and reload
#
# Run from the HOST:
#   bash scripts/fw-router/nftables-deploy.sh
#
# nftables.nft is the single source of truth. Alpine's nftables init service
# loads /etc/nftables.nft (not /etc/nftables.conf) — this script deploys there.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FW_SSH="ssh -i ~/.ssh/fw-router-key root@192.168.122.10"
FW_SCP="scp -i ~/.ssh/fw-router-key"

echo "==> Copying nftables.nft to fw-router..."
$FW_SCP "$SCRIPT_DIR/nftables.nft" root@192.168.122.10:/etc/nftables.nft

echo "==> Reloading nftables..."
$FW_SSH "nft -f /etc/nftables.nft && echo 'Rules loaded OK'"

echo "==> Verifying DNS rule present..."
$FW_SSH "nft list ruleset | grep -A1 'dport 53' | head -6"
