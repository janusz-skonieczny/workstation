#!/usr/bin/env bash

# Install apt packages listed in lists/apt.txt
cd "$(dirname "$0")/.." || exit 1

echo "----> Installing from lists/apt.txt"
total=$(grep -cve '^[[:space:]]*$' lists/apt.txt)
i=0
while read -r package || [ -n "$package" ]; do
    [ -z "$package" ] && continue
    i=$((i + 1))
    echo "**** [$i/$total] Installing $package"
    sudo apt-get install -ymf "$package"
done <lists/apt.txt
