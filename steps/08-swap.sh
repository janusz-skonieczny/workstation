#!/usr/bin/env bash

# Real swap — room for the kernel to maneuver under memory pressure.
#
# The installer's 512M /swapfile gives the kernel nowhere to evict
# anonymous pages on a 128G machine. In the 2026-08-25 OOM, ~123G of
# anonymous memory squeezed the file cache down to ~76M and the desktop
# froze thrashing on executable pages long before the OOM killer acted.
# 16G of swap converts that instant freeze into a gradual slowdown that
# earlyoom (steps/12-earlyoom.sh) has time to act on.
#
# The file is grown in place: fallocate extends /swapfile (ext4, no
# NOCOW gymnastics needed), and mkswap must re-run after any resize.

swap_size=16G
swap_bytes=$((16 * 1024 * 1024 * 1024))

echo "----> Swapfile ($swap_size)"

if [ -f /swapfile ] && [ "$(stat -c %s /swapfile)" -ge "$swap_bytes" ]; then
    echo "     /swapfile already ≥ $swap_size"
else
    sudo swapoff /swapfile 2> /dev/null || true
    sudo fallocate -l "$swap_size" /swapfile
    sudo chmod 600 /swapfile
    sudo mkswap /swapfile
    sudo swapon /swapfile
fi

if ! grep -q '^/swapfile' /etc/fstab; then
    echo "/swapfile swap swap defaults 0 0" | sudo tee -a /etc/fstab > /dev/null
fi

echo "----> $(swapon --show --noheadings)"
