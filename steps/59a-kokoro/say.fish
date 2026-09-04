function say --description 'Speak its arguments aloud with Kokoro TTS'
    # The voice is the `kokoro` wrapper's business, not this function's — it
    # defaults to af_heart and honours KOKORO_VOICE, so setting one here would
    # only be a second place to forget to change.
    if test (count $argv) -eq 0
        # No arguments: speak whatever is piped in, so `git log -1 | say` works.
        kokoro - --stream
    else
        printf '%s\n' "$argv" | kokoro - --stream
    end
end
