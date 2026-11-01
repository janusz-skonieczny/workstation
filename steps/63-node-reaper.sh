#!/usr/bin/env bash

# node-reaper — a hard cap on node process count and their combined RAM.
#
# agents.slice (steps/62-agents.sh) only caps fish-launched `claude`;
# IDE-embedded agents, dev servers and ad-hoc `npx` runs escape it. The
# 2026-08-25 freeze was ~76 vitest workers, all node. With swap gone
# (steps/08-swap.sh), a swarm like that would hit earlyoom's 10% line
# within seconds; the reaper culls it first, by count (newest go) and by
# total RSS (largest go). MCP servers are exempt — every agent session
# spawns a few and killing them breaks the session, not the swarm.
#
# 2026-11-01 repeat: load average ~206 on 32 threads with 13G of 16G
# swap in use, cleared only by killing node processes by hand. A load
# that far above the thread count is tasks blocked on page-ins, not CPU:
# the slow swap death steps/08-swap.sh removes.
#
# Limits live in /etc/default/node-reaper, written once and then left to
# hand-tuning; re-running this step does not overwrite them.
cd "$(dirname "$0")/.." || exit 1

echo "----> node-reaper (node process count + RSS cap)"

sudo install -Dm755 steps/63-node-reaper/node-reaper /usr/local/bin/node-reaper
sudo install -Dm644 steps/63-node-reaper/node-reaper.service /etc/systemd/system/node-reaper.service

if [ ! -f /etc/default/node-reaper ]; then
    sudo tee /etc/default/node-reaper > /dev/null <<CONF
# Read by node-reaper.service. Restart it after editing:
#   sudo systemctl restart node-reaper
NODE_REAPER_USER=$USER
# vitest is capped at 8 workers per run (steps/62-agents.sh); 48 leaves
# room for ~4 concurrent runs plus language servers and dev servers.
NODE_REAPER_MAX_PROCS=48
# 64G of combined node RSS, half the box: two full vitest runs (~28G
# each) fit, a third concurrent one does not.
NODE_REAPER_MAX_RSS_MB=65536
NODE_REAPER_INTERVAL=2
# MCP servers: one set per agent session. desktop-commander is one too,
# but its command line never says "mcp" (2026-11-01: 13 copies running).
NODE_REAPER_EXEMPT=mcp|desktop-commander
NODE_REAPER_DRY_RUN=0
CONF
fi

sudo systemctl daemon-reload
sudo systemctl enable --now node-reaper
sudo systemctl restart node-reaper

sleep 1
if ! systemctl is-active --quiet node-reaper; then
    echo "!!!! node-reaper failed to start:" >&2
    systemctl status node-reaper --no-pager -n 5 >&2
    exit 1
fi
echo "----> $(journalctl -u node-reaper -n 1 -o cat --no-pager)"
