#!/usr/bin/env bash

# Piper TTS voice models, declared in lists/piper-voices.txt. The `piper` CLI
# itself comes from lists/uv.txt via 58-uv.sh; only the voice data is fetched
# here.
#
# The downloader is a module *inside* the tool venv and is not exposed on
# PATH, so it has to be run with that venv's python — `piper.download_voices`
# is not reachable through the `piper` entry point. It takes any number of
# voice names, so the whole missing set is fetched in one call.
#
# migrate/backup.sh carries .local/share wholesale, so a restored machine
# already has the models and this step is a no-op. The download is the
# fallback for a machine built without a restore.

set -euo pipefail

cd "$(dirname "$0")/.." || exit 1

VOICE=${PIPER_VOICE:-en_US-ryan-medium}
VOICE_DIR="$HOME/.local/share/piper/voices"

echo "----> Piper TTS voices in $VOICE_DIR"

# Both files or neither: an interrupted download can leave the 60 MB .onnx
# without its .json, and piper needs both — treat that as "not present".
missing=()
while read -r voice || [ -n "$voice" ]; do
    case "$voice" in '' | \#*) continue ;; esac
    if [ -f "$VOICE_DIR/$voice.onnx" ] && [ -f "$VOICE_DIR/$voice.onnx.json" ]; then
        echo "     $voice already present"
    else
        missing+=("$voice")
    fi
done <lists/piper-voices.txt

if [ ${#missing[@]} -gt 0 ]; then
    tool_python="$(uv tool dir)/piper-tts/bin/python"
    if [ ! -x "$tool_python" ]; then
        echo "!!!! piper-tts venv missing — run steps/58-uv.sh first" >&2
        exit 1
    fi
    mkdir -p "$VOICE_DIR"
    echo "**** fetching ${#missing[@]}: ${missing[*]}"
    "$tool_python" -m piper.download_voices --download-dir "$VOICE_DIR" "${missing[@]}"
fi

# Synthesis is silent, not broken, when the default sink is a monitor that
# has no speakers — a fresh install commonly lands on HDMI. Sink names are
# PCI-path specific, so this only reports; pick the analog one from
# `pactl list short sinks` and set it with:
#   pactl set-default-sink <name>
# WirePlumber persists that choice in
# ~/.local/state/wireplumber/default-nodes (default.configured.audio.sink).
if command -v pactl > /dev/null; then
    echo "----> Default audio sink: $(pactl get-default-sink)"
fi

cat <<USAGE
----> Usage
  piper -m $VOICE --data-dir $VOICE_DIR \\
      -i text.txt -f out.wav
  # stream, no temp file (--length-scale 0.9 speaks faster, >1.0 slower)
  piper -m $VOICE --data-dir $VOICE_DIR \\
      -i text.txt -f - | mpv --no-video --quiet -
  # when diagnosing: --quiet, never --really-quiet (it hides errors too,
  # making a missing file look exactly like a successful play to a silent
  # sink). Check the audio itself with:
  #   ffmpeg -i out.wav -af volumedetect -f null -
USAGE
