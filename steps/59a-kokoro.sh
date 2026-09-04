#!/usr/bin/env bash

# Kokoro TTS model data, CLI wrapper and `say` helper. The `kokoro-tts` CLI
# itself comes from lists/uv.txt via 58-uv.sh; only the data and the wrappers
# are handled here. Numbered 59a because this sits at the same tier as
# 59-piper.sh — both are TTS engines that need uv (58) and nothing later.
#
# That uv.txt line carries `--python 3.12` (58-uv.sh passes list lines
# unquoted, as it does for poetry's plugin flag): kokoro-tts declares
# Requires-Python <3.13 and Kubuntu ships something newer, so uv is told to
# fetch a managed 3.12 rather than resolve against the system interpreter.
# The comment lives here because 58-uv.sh's reader skips blank lines only —
# a #comment in uv.txt would be handed to `uv tool install` verbatim.
#
# Kokoro runs alongside Piper rather than replacing it: Dev10x:tts, which
# narrates qa-self walkthroughs, shells out to `piper` and is not wired to
# Kokoro, so dropping Piper would break narration.
#
# migrate/backup.sh carries .local/share wholesale (kokoro is not in its
# exclude list), so a restored machine already has the 350 MB of model data and
# this step is a no-op. The download is the fallback for a machine built
# without a restore.

set -euo pipefail

DATA_DIR="${KOKORO_DATA_DIR:-$HOME/.local/share/kokoro}"
RELEASE=https://github.com/nazdridoy/kokoro-tts/releases/download/v1.0.0

echo "----> Kokoro TTS model data in $DATA_DIR"

# Both files or neither: an interrupted download can leave the 310 MB .onnx
# without its voice pack, and kokoro-tts needs both — treat that as "not
# present". Same guard as 59-piper.sh, same reason.
if [ -f "$DATA_DIR/kokoro-v1.0.onnx" ] && [ -f "$DATA_DIR/voices-v1.0.bin" ]; then
    echo "     already present"
else
    mkdir -p "$DATA_DIR"
    # --continue so a re-run resumes a partial 310 MB fetch instead of
    # restarting it. It has to be --directory-prefix rather than -O: wget's -O
    # is analogous to shell redirection and truncates the file immediately,
    # which silently kills the resume. The asset basenames already match the
    # names we want, so nothing is lost by letting wget pick them.
    wget --continue --directory-prefix="$DATA_DIR" "$RELEASE/kokoro-v1.0.onnx"
    wget --continue --directory-prefix="$DATA_DIR" "$RELEASE/voices-v1.0.bin"
fi

step_dir="$(cd "$(dirname "$0")" && pwd)/59a-kokoro"

echo "----> Installing the kokoro wrapper"
install -Dm755 "$step_dir/kokoro" "$HOME/.local/bin/kokoro"

echo "----> Installing the fish say function"
install -Dm644 "$step_dir/say.fish" "$HOME/.config/fish/functions/say.fish"

cat <<USAGE
----> Usage
  say "the build is green"           # fish function, streams to the speakers
  git log -1 --format=%s | say       # or from a pipe
  kokoro notes.txt out.wav --voice af_heart
  kokoro notes.txt --stream --speed 1.2
  kokoro book.epub --split-output ./chunks/ --format mp3
  kokoro --help-voices               # 48 voices; en_US are af_* and am_*
  # blend two voices by weight
  kokoro notes.txt out.wav --voice "af_sarah:60,am_adam:40"

  # Inference is CPU-only — upstream still lists GPU support as a TODO, which
  # is fine for an 82M model. If nothing is audible, the sink is the usual
  # culprit before the synthesis is: see the note in 59-piper.sh and check
  #   pactl get-default-sink
USAGE
