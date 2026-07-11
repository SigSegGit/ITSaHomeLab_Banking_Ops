#!/usr/bin/env bash
# The actual "show, don't tell" demo: ramps the exact same synthetic
# load against the ledger-service on every node in $DEMO_NODES at
# once, while Grafana (http://smallrevolt.local:3000, the "Homelab
# overview" dashboard) shows each node's CPU/memory/load side by side
# in real time. The whole point of running the same workload on
# genuinely different hardware: the weaker node visibly saturates
# first, which is the concrete argument for ramping up (more nodes, or
# cloud burst capacity) instead of a hand-wavy claim.
#
# Node list is env-driven (not hardcoded) because which machines are
# actually in banking_app_nodes changes — e.g. ITSaRevolution is out
# for now pending an SD card check (see STATUS.md/hosts.yml), and a
# GCP burst node may be in instead. Set DEMO_NODES to match whatever's
# actually up and enrolled before running this.
#
# Prerequisites: every node in DEMO_NODES has already pulled the
# banking-app role (see STATUS.md) and is reachable by name/IP from
# wherever you run this. Only needs Python + httpx (pip install httpx),
# not the app's own dependencies.
#
# Usage: DEMO_NODES="MorePower.local somenode.example.com" ./run-demo.sh [max-rps] [step-seconds]

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MAX_RPS="${1:-100}"
STEP_SECONDS="${2:-15}"

if [ -z "${DEMO_NODES:-}" ]; then
    echo "set DEMO_NODES to a space-separated list of reachable banking_app_nodes hosts, e.g.:" >&2
    echo "  DEMO_NODES=\"MorePower.local\" $0" >&2
    exit 1
fi
read -ra NODES <<< "$DEMO_NODES"

echo "==> open Grafana now and watch while this runs:"
echo "    http://smallrevolt.local:3000/d/homelab-overview"
echo ""

pids=()
for node in "${NODES[@]}"; do
    echo "==> ramping load against http://${node}:8000"
    python3 load-generator.py \
        --base-url "http://${node}:8000" \
        --start-rps 5 --max-rps "$MAX_RPS" --step-rps 10 \
        --step-seconds "$STEP_SECONDS" &
    pids+=("$!")
done

for pid in "${pids[@]}"; do
    wait "$pid"
done

echo "==> demo run complete — compare the two nodes' saturation points on Grafana"
