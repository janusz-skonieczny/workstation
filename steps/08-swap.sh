#!/usr/bin/env bash

# No swap — a runaway fails fast instead of dragging the desktop down.
#
# The 16G /swapfile added after the 2026-08-25 OOM delays rather than
# prevents a freeze: earlyoom only fires once both RAM *and* swap are
# nearly gone, so 16G of swap pushes the kill out past the point where
# the desktop is already crawling through page-ins. With 128G of RAM
# there is nothing worth paging out; a process that outgrows RAM is the
# bug. Without swap earlyoom judges RAM alone and acts at ~10% free, and
# steps/63-node-reaper.sh culls node swarms before they get that far.
#
# Idempotent: swapoff every active device (pages come back into RAM, so
# this needs as much free memory as swap is in use), drop swap lines
# from fstab, delete the file, and mask swap.target so nothing — a stray
# systemd-gpt-auto swap partition, a reinstalled package — turns it back
# on at boot.

echo "----> Swap (disabled)"

if [ -n "$(swapon --show --noheadings)" ]; then
    in_use_kib=$(awk '/^SwapTotal/ {t=$2} /^SwapFree/ {f=$2} END {print t-f}' /proc/meminfo)
    available_kib=$(awk '/^MemAvailable/ {print $2}' /proc/meminfo)
    if [ "$in_use_kib" -ge "$available_kib" ]; then
        echo "!!!! ${in_use_kib}K swapped out, only ${available_kib}K RAM available —" >&2
        echo "!!!! swapoff would trigger an OOM. Free memory and re-run." >&2
        exit 1
    fi
    echo "     swapoff -a (${in_use_kib}K to page back in)"
    sudo swapoff -a
fi

if grep -qE '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab; then
    echo "     commenting out swap entries in /etc/fstab"
    sudo sed -i -E 's|^([^#].*[[:space:]]swap[[:space:]].*)$|# disabled by workstation/steps/08-swap.sh: \1|' /etc/fstab
fi

sudo rm -f /swapfile
sudo systemctl mask --quiet swap.target

echo "----> swap devices: $(swapon --show --noheadings | wc -l), SwapTotal $(awk '/^SwapTotal/ {print $2 $3}' /proc/meminfo)"
