#!/usr/bin/env bash

# Migration backup — stage everything valuable from this OS onto a
# surviving disk before a fresh install wipes / and /home.
#
# Usage:   migrate/backup.sh [TARGET_DIR]
# Default: /work/migration/<hostname>-<date>
#
# Flags are environment variables and must be exactly "1":
#   USER_DATA=1    also stage Documents, Pictures, Desktop, Templates,
#                  Public, KB (~4 GB)
#   WITH_SUDO=1    also stage the root-only configs — NetworkManager wifi
#                  PSKs, /etc/ssh host keys, /etc/docker. Prompts once.
#   FULL_CLAUDE=1  also stage ~/.claude/projects session transcripts (~1.9 GB)
#
# Run as yourself, NOT under sudo — see the guard below.
# Quit Signal first: its SQLCipher db is copied live from .config/Signal.
#
# Safe to re-run: rsync is incremental, manifests are regenerated.
# Nothing here is machine-specific — device UUIDs, serials and secrets
# are captured into the TARGET at run time, never into this repo.

set -euo pipefail

# Run as yourself, never under sudo: sudo rewrites HOME to /root, so the
# allowlist would silently stage root's dotfiles instead of yours and
# leave a root-owned target. WITH_SUDO=1 elevates only the one step that
# needs it, from inside.
if [[ "${EUID}" -eq 0 ]]; then
    printf 'Refusing to run as root — HOME would be %s, not your home.\n' "$HOME" >&2
    printf 'Run as your own user; use WITH_SUDO=1 for the root-only step.\n' >&2
    exit 1
fi

TARGET="${1:-/work/migration/$(hostname)-$(date +%F)}"
HOME_SRC="${HOME}"

mkdir -p "$TARGET"/{home,etc,manifests}

# A target left behind by an earlier root-owned run is still readable, so
# mkdir -p succeeds and every rsync then dies on a bare mkstemp "Permission
# denied". Name the real problem and the fix instead.
for d in home etc manifests; do
    if [[ ! -w "$TARGET/$d" ]]; then
        printf 'Target %s is not writable by %s (owned by %s).\n' \
            "$TARGET/$d" "$(id -un)" "$(stat -c '%U' "$TARGET/$d")" >&2
        printf 'Left over from a run under sudo? Remove it and retry:\n' >&2
        printf '  sudo rm -rf %s\n' "$TARGET" >&2
        exit 1
    fi
done

SECTION=0
SECTIONS=4                                    # home, /etc, root-only, manifests
[[ "${USER_DATA:-0}" == "1" ]] && SECTIONS=5   # + user data directories

say() {
    SECTION=$((SECTION + 1))
    printf '\n»»»» [%d/%d] %s\n' "$SECTION" "$SECTIONS" "$*"
}

note() { printf '\n»»»» %s\n' "$*"; }

# Per-item progress. The counter is exact — these are fixed-length
# allowlists. rsync's own --info=progress2 byte percentage is NOT: with
# incremental recursion it only knows the files it has scanned so far, so
# it climbs, resets and overshoots on big trees. Treat it as "still
# moving", not as "how far along".
RSYNC_PROGRESS=()
[[ -t 1 ]] && RSYNC_PROGRESS=(--info=progress2)

step() {
    printf '  [%2d/%2d] %s\n' "$1" "$2" "$3"
}

# ---------------------------------------------------------------------------
# 1. Home: configs, credentials, histories — the curated allowlist.
#    Caches, venvs and build artifacts are deliberately absent.
# ---------------------------------------------------------------------------
say "Home configs, credentials and histories -> $TARGET/home"

HOME_PATHS=(
    # Shell & tribal knowledge
    .bashrc .profile .zshrc .bash_history
    .config/fish .local/share/fish
    .config/starship.toml .local/share/zoxide
    .psql_history .python_history .rediscli_history .pdbhistory
    .lesshst .viminfo .ipython

    # Git identity & workflow
    .gitconfig .gitconfig-venvs .git-hooks .gitignore .huskyrc

    # Credentials & access (historical access is the point — keep old ones)
    .ssh .aws .kube .krew .gnupg .cert .pki .netrc .boto
    .docker/config.json
    .railway .sentry .frisco-cli .copilot .gemini .codex
    .claude.json signal-desktop-keyring.gpg supabase

    # Claude Code state (projects/ excluded below — opt in via FULL_CLAUDE=1)
    .claude

    # App config trees — whole dirs, caches stripped by EXCLUDES.
    # (.config carries KDE rc files, JetBrains, browsers, gh, gcloud;
    #  .local/share carries kwallet, keyrings, konsole profiles, fonts.)
    .config .local/share .local/bin

    # Browsers outside .config
    .mozilla

    # Editors, agents & misc tool state
    .vscode .idea .agents .ai .antigravity .junie .shotgun-sh .resto
    .fonts.conf .icons .face .face.icon

    # Out-of-tree NIC driver source — 2.5GbE port needs it (DKMS r8125)
    realtek-r8125-dkms
)

# Session transcripts, ~1.9 GB. Added as an exclude only when the caller
# has NOT asked for them — never removed after the fact, because each
# --exclude and its pattern are two separate array elements and slicing
# leaves the orphaned pattern behind as a bare rsync source argument.
EXCLUDES=()
[[ "${FULL_CLAUDE:-0}" == "1" ]] || EXCLUDES+=(--exclude '.claude/projects')

EXCLUDES+=(
    --exclude '**/Cache*' --exclude '**/cache*'
    --exclude '**/GPUCache' --exclude '**/Code Cache'
    --exclude '**/CachedData' --exclude '**/ShaderCache'
    # npm/corepack ship *inside* each fnm-managed node install as
    # lib/node_modules. The blanket node_modules exclude below matched them
    # and restored every node version with dangling npm/npx/yarn symlinks.
    # rsync is first-match-wins, so this include must precede that exclude.
    --include '.local/share/fnm/node-versions/**/lib/node_modules/***'
    --exclude '**/node_modules' --exclude '**/.venv'
    --exclude '**/__pycache__'
    --exclude '.local/share/Trash'
    --exclude '.local/share/baloo'
    --exclude '.local/share/pipx'
    --exclude '.local/share/uv'
    --exclude '.local/share/virtualenv'
    # Marketplace plugins, ~9 GB across stale per-version dirs — they
    # re-download. Settings live in .config/JetBrains; the caches and
    # indexes are in .cache/, which this allowlist never touches.
    # manifests/jetbrains-plugins.txt records which plugins to re-add.
    --exclude '.local/share/JetBrains'
    --exclude '.config/**/Service Worker'
    --exclude '.config/**/IndexedDB'
)

n=0
total=${#HOME_PATHS[@]}
for p in "${HOME_PATHS[@]}"; do
    n=$((n + 1))
    if [[ -e "$HOME_SRC/$p" ]]; then
        step "$n" "$total" "$p"
        rsync -aR "${RSYNC_PROGRESS[@]}" "${EXCLUDES[@]}" \
            "$HOME_SRC/./$p" "$TARGET/home/"
    else
        step "$n" "$total" "$p  (absent, skipped)"
    fi
done

# User data directories are intentionally NOT copied by default: review
# them manually (Documents, Pictures, Desktop, KB, work-summary-*) —
# run with USER_DATA=1 to include them.
if [[ "${USER_DATA:-0}" == "1" ]]; then
    say "User data directories -> $TARGET/home"
    USER_DATA_PATHS=(Documents Pictures Desktop Templates Public KB)
    n=0
    total=${#USER_DATA_PATHS[@]}
    for p in "${USER_DATA_PATHS[@]}"; do
        n=$((n + 1))
        step "$n" "$total" "$p"
        [[ -d "$HOME_SRC/$p" ]] && rsync -aR "${RSYNC_PROGRESS[@]}" \
            "$HOME_SRC/./$p" "$TARGET/home/"
    done
    rsync -aR "$HOME_SRC"/./work-summary-*.md "$TARGET/home/" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# 2. /etc: user-readable custom config + machine identity for reference.
# ---------------------------------------------------------------------------
say "/etc snapshot (readable parts) -> $TARGET/etc"

ETC_PATHS=(
    fstab hosts hostname environment
    apt/sources.list apt/sources.list.d apt/keyrings apt/trusted.gpg.d
    apt/preferences.d
    default/grub
    sysctl.conf sysctl.d security/limits.d udev/rules.d modprobe.d modules-load.d
    systemd/system docker/daemon.json
    sddm.conf.d X11/xorg.conf.d profile.d cron.d
)
n=0
total=${#ETC_PATHS[@]}
for p in "${ETC_PATHS[@]}"; do
    n=$((n + 1))
    step "$n" "$total" "$p"
    [[ -e "/etc/$p" ]] && rsync -aR "/etc/./$p" "$TARGET/etc/" 2>/dev/null || true
done

# Vendor apt signing keys living outside /etc (world-readable)
rsync -a /usr/share/keyrings/ "$TARGET/etc/usr-share-keyrings/"

# ---------------------------------------------------------------------------
# 3. Root-only files — the single sudo step, optional.
#
#    Deliberately absent: Docker volumes (containers are disposable and
#    every service that matters is remote — recreate from compose files,
#    see manifests/docker-volumes.txt), /etc/postgresql (bootstrap
#    reinstalls the server from lists/apt.txt; no local database here
#    holds anything worth carrying over), /etc/nordlayer and
#    /etc/sudoers.d (re-provisioned by the installer and by hand
#    respectively), /etc/netplan (a NetworkManager stub on this
#    desktop — the real profiles are in NetworkManager/).
# ---------------------------------------------------------------------------
if [[ "${WITH_SUDO:-0}" == "1" ]]; then
    say "Root-only configs -> $TARGET/etc (sudo)"
    sudo rsync -aR \
        /etc/./NetworkManager/system-connections \
        /etc/./ssh \
        /etc/./docker \
        "$TARGET/etc/" || true
    sudo chown -R "$(id -u):$(id -g)" "$TARGET/etc"
else
    say "Skipping root-only files (re-run with WITH_SUDO=1)"
fi

# ---------------------------------------------------------------------------
# 4. Manifests: package lists + hardware identity for the restore side.
# ---------------------------------------------------------------------------
say "Package + hardware manifests -> $TARGET/manifests"

# Each entry is "outfile:command". Single-quoted so $TARGET and $HOME_SRC
# expand at run time, and the {{.Name}} / %P\n literals survive intact.
# A missing tool leaves an empty manifest rather than aborting the run.
#
# JetBrains plugins are excluded from the file copy (9 GB of re-downloadable
# marketplace payload) — the irreplaceable part is knowing WHICH ones were
# installed, per IDE version. Most lines read "<Product><Version>/<plugin>";
# a few housekeeping dirs (Daemon/, consentOptions/) ride along harmlessly.
MANIFESTS=(
    'apt-manual.txt:apt-mark showmanual | sort'
    'dpkg-full.txt:dpkg -l'
    'snap.txt:snap list'
    'brew.txt:brew list --formula'
    'brew-cask.txt:brew list --cask'
    'pipx.txt:pipx list --short'
    'uv-tools.txt:uv tool list'
    'go-bin.txt:ls -1 "$HOME_SRC/go/bin"'
    'docker-volumes.txt:docker volume ls --format "{{.Name}}"'
    'vscode-ext.txt:code --list-extensions'
    'jetbrains-plugins.txt:find "$HOME_SRC/.local/share/JetBrains" -mindepth 2 -maxdepth 2 -type d -printf "%P\n" | sort'
    'disks.txt:lsblk -o NAME,MODEL,SERIAL,SIZE,FSTYPE,MOUNTPOINT,UUID'
    'fstab.txt:cat /etc/fstab'
    'board.txt:cat /sys/devices/virtual/dmi/id/board_name'
    # Group membership survives nowhere else: it lives in /etc/group, which
    # the fresh install owns. Names are what matter — GIDs are assigned by
    # whichever package creates the group, so they will differ.
    'groups.txt:id -nG | tr " " "\n" | sort'
    'groups-gid.txt:id'
)

n=0
total=${#MANIFESTS[@]}
for entry in "${MANIFESTS[@]}"; do
    n=$((n + 1))
    out="${entry%%:*}"
    cmd="${entry#*:}"
    step "$n" "$total" "$out"
    eval "$cmd" > "$TARGET/manifests/$out" 2>/dev/null || true
done

note "Backup staged in: $TARGET"
note "Verify size and spot-check before wiping anything:"
du -sh "$TARGET"/* 2>/dev/null || true
