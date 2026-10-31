function meeting-start --description 'Start a voxtype meeting transcription (prompts for the active mic)'
    set -l config "$HOME/.config/voxtype/config.toml"
    set -l statefile "$HOME/.local/state/voxtype-meeting.state"

    if not test -f "$config"
        echo "voxtype config not found at $config — run steps/59b-voxtype.sh" >&2
        return 1
    end

    # --- pick the active microphone (the default source varies per session) ---
    set -l rows (pactl list sources | awk '/^\tName:/{n=$2} /^\tDescription:/{d=substr($0,index($0,": ")+2); if(n !~ /\.monitor$/) print n "\t" d}')
    if test (count $rows) -eq 0
        echo "No input sources found via pactl." >&2
        return 1
    end

    set -l current (sed -nE 's/^mic_device = "(.*)"/\1/p' "$config" | head -n1)
    set -l names
    echo "Select the active microphone for this meeting:"
    for i in (seq (count $rows))
        set -l parts (string split \t -- $rows[$i])
        set -a names $parts[1]
        set -l mark ' '
        test "$parts[1]" = "$current"; and set mark '*'
        printf '  [%d]%s %s\n' $i $mark "$parts[2]"
    end

    read -l -P 'Mic number (Enter = keep current): ' pick
    set -l chosen
    if test -n "$pick"
        if not string match -qr '^[0-9]+$' -- "$pick"; or test "$pick" -lt 1 -o "$pick" -gt (count $names)
            echo "Invalid selection." >&2
            return 1
        end
        set chosen $names[$pick]
    else if test -n "$current"
        set chosen $current
    else
        set chosen default
    end

    # --- apply mic: daemon has no hot-reload, so restart only when it changes ---
    if test "$chosen" != "$current"
        sed -i -E "s|^mic_device = .*|mic_device = \"$chosen\"|" "$config"
        echo "Mic → $chosen — restarting voxtype daemon…"
        systemctl --user restart voxtype
        for i in (seq 30)
            systemctl --user is-active -q voxtype; and break
            sleep 0.3
        end
        sleep 1
    end

    # --- start the meeting ---
    set -l title (string join ' ' -- $argv)
    if test -n "$title"
        voxtype meeting start --title "$title"
    else
        voxtype meeting start
    end
    if test $status -ne 0
        echo "voxtype meeting start failed (daemon may still be loading — retry in a moment)." >&2
        return 1
    end

    mkdir -p (dirname "$statefile")
    printf '%s\n%s\n' (date '+%Y-%m-%d-%H%M') "$title" >"$statefile"

    echo "🔴 Recording — You (mic: $chosen) + Remote (system audio, any app)."
    echo "   Others' voices are captured; get consent where the law requires it."
    echo "   Stop & save → meeting-stop   |   status → meeting-status"
end
