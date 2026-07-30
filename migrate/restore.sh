#!/usr/bin/env bash

# Migration restore — run on the FRESH install, after bootstrap.sh,
# to bring back configs, credentials and shell history staged by
# migrate/backup.sh.
#
# Usage: migrate/restore.sh <BACKUP_DIR>
#        (e.g. /work/migration/hagrid-2026-07-25)

set -euo pipefail

SRC="${1:?Usage: restore.sh <BACKUP_DIR>}"
[[ -d "$SRC/home" ]] || { echo "No home/ under $SRC — wrong dir?"; exit 1; }

say() { printf '\n»»»» %s\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Home restore — never clobber newer files created since the restore.
# ---------------------------------------------------------------------------
say "Restoring home files -> $HOME"
rsync -a --update "$SRC/home/" "$HOME/"

say "Fixing permissions on credential material"
chmod 700 "$HOME/.ssh" "$HOME/.gnupg" 2>/dev/null || true
find "$HOME/.ssh" -type f ! -name '*.pub' -exec chmod 600 {} + 2>/dev/null || true
chmod 600 "$HOME/.netrc" "$HOME/.claude.json" 2>/dev/null || true
chmod 600 "$HOME/.aws/credentials" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. /etc restore — review, don't blindly copy. Print a diff-style guide.
# ---------------------------------------------------------------------------
say "/etc is NOT auto-restored. Review these against the new system:"
echo "  $SRC/etc/fstab                 -> merge mount entries (see below)"
echo "  $SRC/etc/apt/sources.list.d/   -> re-add third-party repos you still use"
echo "  $SRC/etc/NetworkManager/       -> sudo copy Wi-Fi/VPN profiles you need"
echo "  $SRC/etc/hosts                 -> merge custom host entries"
echo "  $SRC/etc/default/grub          -> re-apply GRUB_CMDLINE tweaks + update-grub"
echo "  $SRC/etc/docker/daemon.json    -> restore BEFORE first docker start when"
echo "                                    data-root lives on a surviving disk"

# ---------------------------------------------------------------------------
# 3. Data-disk mounts: generate CLEAN fstab lines from live UUIDs.
#    (The old fstab had stale device-path entries that caused boot
#    timeouts — do not copy it verbatim.)
# ---------------------------------------------------------------------------
say "Suggested fstab lines for surviving data disks (verify labels):"
for mp in work arch; do
    dev="$(lsblk -rno NAME,MOUNTPOINT | awk -v m="/$mp" '$2==m {print $1}')"
    if [[ -n "$dev" ]]; then
        echo "  (already mounted: /$mp on $dev)"
    fi
done
lsblk -rno NAME,FSTYPE,UUID,MOUNTPOINT | awk '$2=="ext4" && $4=="" && $3!="" {
    printf "  UUID=%s  /mnt/%s  ext4  defaults,nofail  0 2\n", $3, $1
}'
echo "  Use 'nofail' on every non-root data disk so a missing disk can"
echo "  never hang boot again. For NTFS disks use fstype 'ntfs3'"
echo "  (in-kernel driver) instead of ntfs/ntfs-3g."

# ---------------------------------------------------------------------------
# 4. Bulk cloud-synced trees, pulled straight off the old disk.
#
#    backup.sh deliberately skips these (~109 GB) — they live in the cloud
#    and would double the staging footprint. But re-downloading 103 GB of
#    Drive takes hours and Google throttles, while NVMe->NVMe copy is
#    minutes and leaves the sync clients only a local index pass.
#
#    The old drive is not wiped by the install, only disconnected — so
#    reconnect it, mount the old /home read-only, and point OLD_HOME at
#    your old home directory on it.
# ---------------------------------------------------------------------------
say "Bulk data from the old disk"

BULK_PATHS=(GDrive Dropbox Videos Downloads)
OLD_HOME="${OLD_HOME:-}"

if [[ -z "$OLD_HOME" ]]; then
    echo "  OLD_HOME not set — skipped. To pull them across:"
    echo "    sudo mkdir -p /mnt/oldhome"
    echo "    sudo mount -o ro UUID=<old-home-uuid> /mnt/oldhome"
    echo "    OLD_HOME=/mnt/oldhome/$(id -un) migrate/restore.sh $SRC"
    echo "  Old /home UUID, recorded by backup.sh at capture time:"
    awk '$0 ~ /\/home$/ {printf "    %s\n", $0}' \
        "$SRC/manifests/disks.txt" 2>/dev/null || true
elif [[ ! -d "$OLD_HOME" ]]; then
    echo "  OLD_HOME=$OLD_HOME not found — is the old disk mounted?" >&2
    exit 1
else
    # Both clients rewrite their trees as they reconcile. Copying into a
    # live sync folder races them and can push half-copied state upward.
    for proc in insync dropbox; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            echo "  $proc is running — quit it before copying, then re-run." >&2
            exit 1
        fi
    done

    # --no-inc-recursive costs an upfront metadata scan but is what makes
    # the percentage and ETA real; worth it on a copy this size.
    for p in "${BULK_PATHS[@]}"; do
        if [[ -d "$OLD_HOME/$p" ]]; then
            echo "  $p"
            rsync -a --info=progress2 --no-inc-recursive \
                "$OLD_HOME/$p/" "$HOME/$p/"
        else
            echo "  $p  (absent on old disk, skipped)"
        fi
    done
    echo "  Done — start Insync/Dropbox now and let them index, not re-download."
fi

# ---------------------------------------------------------------------------
# 5. Re-authentication checklist — things a file copy cannot preserve.
# ---------------------------------------------------------------------------
say "Re-authentication checklist (run per tool as needed):"
cat <<'CHECKLIST'
  gh auth login             # GitHub CLI (or verify restored hosts.yml works)
  gcloud auth login         # Google Cloud
  aws-vault list            # if KDE Wallet didn't carry over: aws-vault add <profile>
  docker login              # ECR/DO registries re-auth on first pull
  gpg --list-secret-keys    # verify GPG keyring restored
  kwalletmanager5           # confirm wallet opens with your old login password
  ssh -T git@github.com     # verify SSH keys accepted
CHECKLIST

say "Restore done. Log out/in once so KDE picks up restored configs."
