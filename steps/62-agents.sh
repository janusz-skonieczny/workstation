#!/usr/bin/env bash

# Guardrails for AI coding agents — cap what they can take from the box.
#
# In the 2026-08-25 OOM, concurrent agent sessions each launched a test
# suite and ~76 vitest workers held 82G between them. Two collective caps
# prevent a repeat, with earlyoom (steps/12-earlyoom.sh) as the backstop:
#
# 1. agents.slice — one shared cgroup for every claude session, so three
#    sessions share one budget instead of getting one each. MemoryHigh
#    throttles and reclaims first; MemoryMax is the hard wall, and the
#    kernel OOM kill then lands *inside* the slice (on a vitest worker),
#    not on a random Chrome renderer like the global OOM killer picked.
#    Sessions join it via a fish wrapper function, so only fish-launched
#    `claude` is capped — IDE-embedded agents rely on earlyoom alone.
#
# 2. Vitest worker caps — vitest sizes its pool to the CPU count (32
#    threads here → ~30 workers × ~3.5G per run). VITEST_MAX_THREADS and
#    VITEST_MAX_FORKS cover both pool types; fish universal variables
#    reach every fish-spawned process, no per-repo config to maintain.

echo "----> Agent guardrails (agents.slice + vitest worker caps)"

mkdir -p ~/.config/systemd/user

tee ~/.config/systemd/user/agents.slice > /dev/null <<'UNIT'
# Managed by workstation/steps/62-agents.sh — edit there, not here.
[Unit]
Description=AI coding agents — collective memory budget

[Slice]
MemoryHigh=80G
MemoryMax=96G
UNIT

systemctl --user daemon-reload

mkdir -p ~/.config/fish/functions

tee ~/.config/fish/functions/claude.fish > /dev/null <<'FISH'
# Managed by workstation/steps/62-agents.sh — edit there, not here.
function claude --wraps claude --description 'claude inside the memory-capped agents.slice'
    systemd-run --user --scope --quiet --collect \
        --slice=agents.slice \
        (command -v claude) $argv
end
FISH

fish -c "set -Ux VITEST_MAX_THREADS 8"
fish -c "set -Ux VITEST_MAX_FORKS 8"

echo "----> $(systemctl --user show agents.slice -p MemoryHigh -p MemoryMax | tr '\n' ' ')"
echo "----> vitest capped at 8 workers (threads and forks pools)"
