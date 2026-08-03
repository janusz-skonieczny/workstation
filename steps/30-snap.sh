#!/usr/bin/env bash

# Install snaps listed in lists/snap.txt
cd "$(dirname "$0")/.." || exit 1

echo "----> Installing from lists/snap.txt"
total=$(grep -cve '^[[:space:]]*$' lists/snap.txt)
i=0
while read -r package || [ -n "$package" ]; do
    [ -z "$package" ] && continue
    i=$((i + 1))
    echo "**** [$i/$total] Installing $package"
    sudo snap install $package
done <lists/snap.txt
