function say --description 'Speak its arguments aloud with Kokoro TTS'
    # kokoro-tts defaults --voice to an *interactive* picker, which hangs a
    # one-shot command waiting on a menu, so a voice is always passed. Override
    # per-shell with `set -x KOKORO_VOICE am_adam`; blends work too, e.g.
    # "af_sarah:60,am_adam:40". `kokoro --help-voices` lists all 48.
    set -l voice $KOKORO_VOICE
    test -z "$voice"; and set voice af_heart

    if test (count $argv) -eq 0
        # No arguments: speak whatever is piped in, so `git log -1 | say` works.
        kokoro - --stream --voice $voice
    else
        printf '%s\n' "$argv" | kokoro - --stream --voice $voice
    end
end
