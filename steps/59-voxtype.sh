#!/usr/bin/env bash

# Voxtype — offline push-to-talk dictation AND meeting transcription.
#
# This step is idempotent:
#   1. Install the voxtype .deb (pinned) if the binary is missing.
#   2. Download the Whisper model if missing.
#   3. Enable the systemd user daemon.
#   4. Merge the [meeting] config block (call-listening wiring) if absent.
#   5. Install the meeting-* fish functions.
#
# Meeting mode captures SYSTEM audio (loopback_device="auto"), so it transcribes
# any call — Slack huddle, ad-hoc Google Chat/Meet, Zoom — into Obsidian via the
# `meeting-start` / `meeting-stop` fish functions.
cd "$(dirname "$0")/.." || exit 1

VOXTYPE_VERSION="0.7.1"
DEB_URL="https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype_${VOXTYPE_VERSION}-1_amd64.deb"
MODEL="base.en"
CONFIG="$HOME/.config/voxtype/config.toml"

# --- 1. install the .deb --------------------------------------------------
if ! command -v voxtype >/dev/null 2>&1; then
    echo "----> Installing voxtype ${VOXTYPE_VERSION} from GitHub release"
    deb="$(mktemp --suffix=.deb)"
    if curl -fL "$DEB_URL" -o "$deb"; then
        sudo gdebi -n "$deb"
    else
        echo "     WARNING: failed to download $DEB_URL — skipping voxtype install"
    fi
    rm -f "$deb"
else
    echo "----> voxtype already installed ($(voxtype --version 2>/dev/null))"
fi

if ! command -v voxtype >/dev/null 2>&1; then
    echo "     voxtype unavailable — skipping model/service/config setup"
    exit 0
fi

# --- 2. download the transcription model ----------------------------------
echo "----> Ensuring Whisper model '$MODEL' is present"
voxtype setup --download --model "$MODEL" --quiet || \
    echo "     WARNING: model download failed — run 'voxtype setup model' manually"

# --- 3. enable the daemon (also generates a default config on first run) ---
echo "----> Enabling voxtype systemd user service"
systemctl --user enable --now voxtype 2>/dev/null || \
    echo "     NOTE: could not enable user service (no systemd --user session here?)"

# --- 4. merge the meeting-mode config -------------------------------------
if [ -f "$CONFIG" ]; then
    if grep -q '^\[meeting\]' "$CONFIG"; then
        echo "----> [meeting] config already present"
    else
        echo "----> Appending [meeting] config (call-listening wiring)"
        printf '\n' >>"$CONFIG"
        cat steps/59-voxtype/meeting.toml >>"$CONFIG"
        systemctl --user restart voxtype 2>/dev/null || true
    fi
else
    echo "     WARNING: $CONFIG not found — run 'voxtype configure' once, then re-run this step"
fi

# --- 5. install the meeting-* fish functions ------------------------------
echo "----> Installing meeting-* fish functions"
mkdir -p "$HOME/.config/fish/functions"
cp fish/functions/meeting-*.fish "$HOME/.config/fish/functions/"
echo "     meeting-start | meeting-stop | meeting-status | meeting-pause | meeting-resume | meeting-cancel"
