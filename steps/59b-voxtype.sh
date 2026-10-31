#!/usr/bin/env bash

# Voxtype — offline push-to-talk dictation AND meeting transcription.
#
# This step is idempotent:
#   1. Install the voxtype .deb (pinned) if the binary is missing.
#   2. Download the Whisper model if missing.
#   3. Enable the systemd user daemon.
#   4. Merge the [meeting] config block (call-listening wiring) if absent.
#   5. Install the meeting-* fish functions.
#   6. Pin the dictation settings (model, languages), install the
#      push-to-talk listener for the keyboard's Documents key, and start
#      ydotool so the text gets typed.
#
# Meeting mode captures SYSTEM audio (loopback_device="auto"), so it transcribes
# any call — Slack huddle, ad-hoc Google Chat/Meet, Zoom — into Obsidian via the
# `meeting-start` / `meeting-stop` fish functions.
#
# Numbered 59b: it sits at the TTS/speech tier next to 59-piper.sh and
# 59a-kokoro.sh, and a bare 59 would collide with Piper.
cd "$(dirname "$0")/.." || exit 1

VOXTYPE_VERSION="0.7.1"
DEB_URL="https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype_${VOXTYPE_VERSION}-1_amd64.deb"
# Multilingual, not small.en: dictation is in English and Polish. `small` is
# the smallest multilingual model whose Polish is usable; a 16-core desktop
# transcribes a push-to-talk clip in about a second on CPU.
MODEL="small"
# Constrained auto-detect: plain "auto" misreads short utterances as some
# third language, and the array limits Whisper's choice to the two we speak.
LANGUAGES='["en", "pl"]'
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
# Fetched straight from whisper.cpp rather than via `voxtype setup --download`:
# 0.7.1 resolves a bare "small" to SenseVoice, not Whisper, and fails. The
# daemon looks for exactly this ggml-<model>.bin name in MODEL_DIR.
# --directory-prefix, not -O, so --continue can resume a partial download.
MODEL_DIR="$HOME/.local/share/voxtype/models"
echo "----> Ensuring Whisper model '$MODEL' is present"
if [ -f "$MODEL_DIR/ggml-$MODEL.bin" ]; then
    echo "     already present"
else
    wget --continue --directory-prefix="$MODEL_DIR" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin" || \
        echo "     WARNING: model download failed — the daemon will not start until it is present"
fi

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
        cat steps/59b-voxtype/meeting.toml >>"$CONFIG"
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

# --- 6. dictation: push-to-talk key, typing, model ------------------------
# Hold-to-talk on the keyboard's Documents key, never toggle: a toggle hides
# whether the mic is still open. voxtype-ptt explains why it replaces both
# voxtype's own hotkey listener and keyd. It reads /dev/input directly, which
# needs the `input` group; membership only applies to new logins.
if id -nG "$USER" | grep -qw input; then
    echo "----> $USER already in the input group"
else
    echo "----> Adding $USER to the input group (log out and back in to apply)"
    sudo usermod -aG input "$USER"
fi

# python3-evdev comes from lists/apt.txt via 10-apt.sh.
echo "----> Installing the voxtype-ptt push-to-talk listener (Documents key)"
install -Dm755 steps/59b-voxtype/voxtype-ptt "$HOME/.local/bin/voxtype-ptt"
install -Dm644 steps/59b-voxtype/voxtype-ptt.service \
    "$HOME/.config/systemd/user/voxtype-ptt.service"
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable voxtype-ptt 2>/dev/null || \
    echo "     NOTE: could not enable voxtype-ptt user service"
systemctl --user restart voxtype-ptt 2>/dev/null || true

# voxtype types through wtype first, but KWin lacks the virtual-keyboard
# protocol wtype needs, so text only ever reached the clipboard. ydotool
# (from lists/apt.txt) types through uinput instead, via this daemon.
echo "----> Enabling the ydotool daemon so dictation types into KDE apps"
systemctl --user enable --now ydotool 2>/dev/null || \
    echo "     NOTE: could not enable ydotool user service"

# model and language are the only uncommented lines of their name in
# voxtype's config, so a line-anchored replace is enough — no TOML parser
# needed. `enabled` recurs in other sections, so that one is scoped to
# [hotkey]: voxtype-ptt drives recording through `voxtype record`.
if [ -f "$CONFIG" ]; then
    echo "----> Pinning dictation: model $MODEL, languages $LANGUAGES, own hotkey off"
    sed -i \
        -e '/^\[hotkey\]/,/^\[/ s/^#\? \?enabled = .*/enabled = false/' \
        -e "s/^model = .*/model = \"$MODEL\"/" \
        -e "s/^language = .*/language = $LANGUAGES/" \
        "$CONFIG"
    systemctl --user restart voxtype 2>/dev/null || true
fi
