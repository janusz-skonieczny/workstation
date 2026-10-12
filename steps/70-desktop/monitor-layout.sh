#!/usr/bin/env bash

# Three monitors on a row, panel on the middle one, and the row must not
# reshuffle when a monitor drops off DisplayPort (power button, monitor
# sleep, cable). KWin (Plasma 6, Wayland) remembers one setup per
# combination of connected outputs in ~/.config/kwinoutputconfig.json and
# lays out an unseen combination from scratch, so a two-monitor setup it
# invented once puts the right monitor on the left and moves the panel.
#
# Plasma places the panel on screen 0, which is always the primary
# (priority 1) output. Making the middle monitor primary in every setup
# keeps the panel there whenever that monitor is on.
#
# Adaptive Sync stays off. With it on "automatic" KWin switches VRR on
# for any fullscreen surface — Spectacle's region-selection overlay,
# Gromit's annotation layer — and the AOC U32P2 drops the picture for a
# second while DisplayPort re-trains, then again when the surface closes.
# Nothing is logged by KWin or the kernel; reproduced and fixed live
# 2026-10-08 by setting vrrpolicy to never.
#
# kscreen-doctor only edits the setup that is live right now. The other
# combinations are rewritten in the JSON file (see monitor-layout.jq).
# KWin reads that file once at login and overwrites it from memory on any
# later change, so the rewrite applies after a relogin and must not be
# followed by display changes before then. KWin's own write after the
# kscreen-doctor call above is asynchronous and landed on top of the
# rewrite once, so the rewrite waits for it.

set -euo pipefail

# Left to right, logical width per monitor at scale 1.45 (3840 / 1.45).
monitor_order=(DP-2 DP-3 DP-1)
monitor_primary=(DP-3 DP-2 DP-1)
monitor_width=2649

echo "----> Pinning the monitor row and the primary screen"

# kscreen-doctor exits non-zero outside a Wayland session; an empty list
# just skips the live part below.
connected="$(kscreen-doctor -o 2>/dev/null | sed -n 's/^.*Output: .*[0-9] \(DP-[0-9]\+\|HDMI-[A-Z0-9-]\+\).*$/\1/p' || true)"

live_settings=()
column=0
for name in "${monitor_order[@]}"; do
    if grep -qx "$name" <<<"$connected"; then
        live_settings+=("output.$name.position.$((column * monitor_width)),0")
        live_settings+=("output.$name.vrrpolicy.never")
        column=$((column + 1))
    fi
done
rank=1
for name in "${monitor_primary[@]}"; do
    if grep -qx "$name" <<<"$connected"; then
        live_settings+=("output.$name.priority.$rank")
        rank=$((rank + 1))
    fi
done

if [ "${#live_settings[@]}" -gt 0 ]; then
    kscreen-doctor "${live_settings[@]}"
    echo "     live setup applied: ${live_settings[*]}"
    sleep 3
else
    echo "     no Wayland session — skipping the live setup"
fi

config="$HOME/.config/kwinoutputconfig.json"
if [ -f "$config" ]; then
    rewritten="$(mktemp)"
    jq --argjson order "$(printf '%s\n' "${monitor_order[@]}" | jq -R . | jq -s .)" \
       --argjson primary "$(printf '%s\n' "${monitor_primary[@]}" | jq -R . | jq -s .)" \
       --argjson width "$monitor_width" \
       -f "$(dirname "$0")/monitor-layout.jq" "$config" >"$rewritten"
    mv "$rewritten" "$config"
    echo "     remembered setups rewritten — relogin before changing displays"
else
    echo "     $config missing — KWin writes it on first login"
fi

# The login screen runs its own kwin_wayland as the sddm user, which keeps
# a separate kwinoutputconfig.json and lays the monitors out from scratch:
# DP-1 (physically right) lands on the left and the cursor leaves each
# screen on the wrong edge. Hand it the same setups and the same edge
# barrier as the session. Outputs are matched by EDID, so the file is
# portable between the two users on this machine.
sddm_config="$(getent passwd sddm | cut -d: -f6 || true)/.config"
if [ -f "$config" ] && [ "$sddm_config" != "/.config" ]; then
    echo "----> Copying the monitor row to the login screen"
    sudo install -d -o sddm -g sddm -m 755 "$sddm_config"
    sudo install -o sddm -g sddm -m 644 "$config" "$sddm_config/kwinoutputconfig.json"
    sudo -u sddm kwriteconfig6 --file "$sddm_config/kwinrc" --group EdgeBarrier --key EdgeBarrier 0
    echo "     applies on the next login screen"
fi

# Blank the screens after an hour idle on AC. Keys from
# powerdevilprofilesettings.kcfg, group [AC][Display]. The locked-screen
# timeout keeps its default so a locked desk still blanks quickly.
echo "----> Turning the displays off after an hour idle"
kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayWhenIdle true
kwriteconfig6 --file powerdevilrc --group AC --group Display --key TurnOffDisplayIdleTimeoutSec 3600
if qdbus6 org.kde.Solid.PowerManagement /org/kde/Solid/PowerManagement refreshStatus 2>/dev/null; then
    echo "     power management reloaded"
else
    echo "     powerdevil not running — applies on next login"
fi
