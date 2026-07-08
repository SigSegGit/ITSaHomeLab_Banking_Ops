#!/usr/bin/env bash
# The actual "show, don't tell" demo: ramps the exact same synthetic
# load against the ledger-service on BOTH banking_app_nodes at once —
# the Pi (weakest) and MorePower (strongest) — while Grafana
# (http://smallrevolt.local:3000, the "Homelab overview" dashboard)
# shows the two nodes' CPU/memory/load side by side in real time. The
# whole point of running the same workload on genuinely different
# hardware: the weaker node visibly saturates first, which is the
# concrete argument for ramping up (more nodes, or cloud burst
# capacity) instead of a hand-wavy claim.
#
# Prerequisites: both nodes have already pulled the banking-app role
# (see STATUS.md) and are reachable by their mDNS names. Run this from
# any machine on the same LAN — it only needs Python + httpx
# (pip install httpx), not the app's own dependencies.
#
# Usage: ./run-demo.sh [max-rps] [step-seconds]

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

MAX_RPS="${1:-100}"
STEP_SECONDS="${2:-15}"

NODES=("ITSaRevolution.local" "MorePower.local")

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
