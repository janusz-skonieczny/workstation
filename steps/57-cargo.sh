#!/usr/bin/env bash

# Install cargo crates listed in lists/cargo.txt
cd "$(dirname "$0")/.." || exit 1

if [ -f "$HOME/.cargo/env" ]; then
    source "$HOME/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo not found — skipping (see steps/55-vendor/rust.sh)"
    exit 0
fi

echo "----> Installing crates from lists/cargo.txt"
total=$(grep -cve '^[[:space:]]*#' -e '^[[:space:]]*$' lists/cargo.txt)
i=0
while read -r crate || [ -n "$crate" ]; do
    case "$crate" in
        ''|\#*) continue ;;
    esac
    i=$((i + 1))
    echo "**** [$i/$total] Installing $crate with cargo"
    cargo install "$crate"
done <lists/cargo.txt
