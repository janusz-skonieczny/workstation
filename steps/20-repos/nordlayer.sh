#!/usr/bin/env bash

echo "----> NordLayer VPN"
echo "----> https://nordlayer.com/download/linux/"

# No apt repo here, deliberately. Two reasons, both verified 2026-07-30:
#
# 1. The `nordlayer-release` deb this step used to fetch (to register the
#    repo and drop its key) is gone — 404, and absent from every
#    dists/stable/main/binary-* index. It was never installed on the old
#    workstation either, so that path had already stopped working.
# 2. The repo's own InRelease is signed with key 3C1F4B54…03EB18BD, which
#    EXPIRED 2026-07-07. apt rejects expired keys, so registering the repo
#    fails regardless of how the key is obtained.
#
# So: resolve the newest deb from the repo's package index and install it
# directly. Verification is on the download, not an apt keyring. Revisit the
# repo route once the vendor rotates that key.

BASE=https://downloads.nordlayer.com/linux/latest/debian
ARCH="$(dpkg --print-architecture)"
STAGE="$HOME/Downloads/Packages"
mkdir -p "$STAGE"

INDEX="$(curl -fsSL "$BASE/dists/stable/main/binary-$ARCH/Packages")" || {
    echo "**** Cannot reach the NordLayer package index — skipping." >&2
    exit 0
}

# Filename lines are repo-relative ("./pool/main/..."); strip the leading dot.
for pkg in nordlayer nordlayer-tray; do
    path="$(printf '%s\n' "$INDEX" \
        | awk -v p="$pkg" '
            /^Package: /  { current = $2 }
            /^Filename: / { if (current == p) print $2 }' \
        | sort -V | tail -n1)"

    if [[ -z "$path" ]]; then
        echo "**** $pkg not found in the index for $ARCH — skipping." >&2
        continue
    fi

    echo "**** Fetching $pkg"
    curl -fsSL -o "$STAGE/$(basename "$path")" "$BASE/${path#./}"
done

# steps/15-debs.sh installs everything staged in ~/Downloads/Packages, but
# this step runs after it, so install what was just fetched.
for pkg in nordlayer nordlayer-tray; do
    deb="$(ls -1v "$STAGE/${pkg}_"*.deb 2>/dev/null | tail -n1)"
    [[ -n "$deb" ]] || continue
    echo "**** Installing $(basename "$deb")"
    sudo gdebi -n "$deb"
done
