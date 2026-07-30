#!/usr/bin/env bash

# Restore supplementary group membership on a fresh install.
#
# Usage: migrate/restore-groups.sh <BACKUP_DIR> [--apply]
#        (e.g. /work/migration/hagrid-2026-07-29)
#
# Dry-run by default: prints what it would change. Pass --apply to run the
# usermod calls (prompts for sudo once).
#
# Group membership is the one thing neither the file copy nor the package
# reinstall brings back. It lives in /etc/group, which the fresh install
# owns, and backup.sh only records it as a manifest. Names are what carry
# over — GIDs are assigned by whichever package creates the group and will
# differ between installs.
#
# Safe to re-run: only ever adds, never removes. Membership takes effect on
# next login, not immediately.

set -euo pipefail

SRC="${1:?Usage: restore-groups.sh <BACKUP_DIR> [--apply]}"
APPLY=0
[[ "${2:-}" == "--apply" ]] && APPLY=1

MANIFEST="$SRC/manifests/groups.txt"
[[ -f "$MANIFEST" ]] || {
    echo "No $MANIFEST — was this backup taken before groups were captured?" >&2
    exit 1
}

if [[ "${EUID}" -eq 0 ]]; then
    echo "Run as the target user, not root — membership is restored for whoever" >&2
    echo "invokes this, and sudo would target root instead." >&2
    exit 1
fi

USER_NAME="$(id -un)"

say() { printf '\n»»»» %s\n' "$*"; }

# The primary group (same name as the user on Debian/Ubuntu) is created by
# the installer and must not be passed to usermod -aG.
PRIMARY="$(id -gn)"

mapfile -t WANTED < "$MANIFEST"

to_add=()
missing=()
already=()

for g in "${WANTED[@]}"; do
    [[ -n "$g" ]] || continue
    [[ "$g" == "$PRIMARY" ]] && continue

    if id -nG "$USER_NAME" | tr ' ' '\n' | grep -qxF "$g"; then
        already+=("$g")
    elif getent group "$g" >/dev/null 2>&1; then
        to_add+=("$g")
    else
        missing+=("$g")
    fi
done

say "Group membership for $USER_NAME (from $MANIFEST)"

printf '  already a member (%d): %s\n' "${#already[@]}" "${already[*]:-—}"
printf '  will be added   (%d): %s\n' "${#to_add[@]}" "${to_add[*]:-—}"

# A group named in the backup but absent from /etc/group means the package
# that creates it is not installed yet — docker, nordlayer, sambashare and
# friends. Re-run this script after the software set is back.
if (( ${#missing[@]} )); then
    printf '  group does not exist yet (%d): %s\n' \
        "${#missing[@]}" "${missing[*]}"
    echo "    -> install the owning package first, then re-run this script."
fi

if (( ${#to_add[@]} == 0 )); then
    say "Nothing to add."
    exit 0
fi

if (( APPLY == 0 )); then
    say "Dry run. Command that --apply would execute:"
    printf '  sudo usermod -aG %s %s\n' \
        "$(IFS=,; echo "${to_add[*]}")" "$USER_NAME"
    say "Re-run with --apply to make the change."
    exit 0
fi

say "Applying"
sudo usermod -aG "$(IFS=,; echo "${to_add[*]}")" "$USER_NAME"

say "Added: ${to_add[*]}"
say "Log out and back in for this to take effect (or: exec newgrp <group>)."
