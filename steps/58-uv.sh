#!/usr/bin/env bash

# uv-managed CLI tools (uv itself comes from 40-brew.sh).
cd "$(dirname "$0")/.." || exit 1

echo "----> Installing from lists/uv.txt"
total=$(grep -cve '^[[:space:]]*$' lists/uv.txt)
i=0
while read -r package || [ -n "$package" ]; do
    [ -z "$package" ] && continue
    i=$((i + 1))
    echo "**** [$i/$total] Installing $package with uv"
    # Unquoted on purpose, as in 40-brew.sh: a line may carry flags, e.g.
    # "poetry --with poetry-bumpversion" puts the plugin in poetry's tool
    # env declaratively. `poetry self add` would not survive a reinstall.
    # shellcheck disable=SC2086
    uv tool install --force $package
done <lists/uv.txt

# dev10x is distributed out-of-band — install per its private instructions.
