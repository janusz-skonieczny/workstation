#!/usr/bin/env bash

echo "----> OpenVPN 3 Linux"
echo "----> https://community.openvpn.net/openvpn/wiki/OpenVPN3Linux"

# Rewritten 2026-07-30. The previous version broke in four ways on 26.04:
#
# 1. `apt-key add` — apt-key is REMOVED from Ubuntu, not merely deprecated.
#    Keys now go in /usr/share/keyrings and are named per-repo via signed-by.
# 2. It wget'd the key into the CWD, which is the repo root during bootstrap,
#    leaving openvpn-repo-pkg-key.pub{,.1} behind as tracked-looking junk.
# 3. `wget -O /etc/apt/sources.list.d/openvpn3.list <url>` writes the
#    response body even when the server 404s, so a missing release poisons
#    apt with an HTML error page until someone deletes the file by hand.
# 4. apt update / apt install ran without sudo.
#
# The vendor publishes per-codename lists but has none for noble (24.04) or
# resolute (26.04) — verified 404, while jammy still returns 200. So this
# step must be able to decline cleanly rather than half-install a repo.

KEYRING=/usr/share/keyrings/openvpn3.gpg
BASE=https://swupdate.openvpn.net/community/openvpn3/repos

# shellcheck source=/dev/null
source /etc/os-release
CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"

if [[ -z "$CODENAME" ]]; then
    echo "**** Cannot determine the distro codename — skipping." >&2
    exit 0
fi

# Ask before touching apt: no published repo means nothing to install.
if ! curl -fsI "$BASE/openvpn3-$CODENAME.list" > /dev/null 2>&1; then
    echo "**** No OpenVPN 3 repo published for '$CODENAME' — skipping."
    echo "     Check $BASE/ for a newer release, then re-run this step."
    exit 0
fi

echo "**** Installing signing key -> $KEYRING"
TMP_KEY="$(mktemp)"
trap 'rm -f "$TMP_KEY"' EXIT
curl -fsSL -o "$TMP_KEY" "https://swupdate.openvpn.net/repos/openvpn-repo-pkg-key.pub"

# The published key is ASCII-armoured; dearmor so the .gpg name is honest.
sudo gpg --batch --yes --dearmor -o "$KEYRING" "$TMP_KEY"
sudo chmod 644 "$KEYRING"

echo "**** Registering repo for $CODENAME"
printf 'deb [signed-by=%s] %s %s main\n' "$KEYRING" "$BASE" "$CODENAME" \
    | sudo tee /etc/apt/sources.list.d/openvpn3.list > /dev/null

sudo apt-get update
sudo apt-get install -y openvpn3
