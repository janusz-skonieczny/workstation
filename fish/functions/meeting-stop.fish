function meeting-stop --description 'Stop the voxtype meeting and export the transcript into Obsidian'
    set -l statefile "$HOME/.local/state/voxtype-meeting.state"

    voxtype meeting stop
    if test $status -ne 0
        echo "voxtype meeting stop failed (is a meeting active? meeting-status)." >&2
        return 1
    end

    # Obsidian vault dir (override with: set -Ux VOXTYPE_MEETINGS_VAULT <path>)
    set -l vault
    if set -q VOXTYPE_MEETINGS_VAULT
        set vault "$VOXTYPE_MEETINGS_VAULT"
    else
        set vault "$HOME/GDrive/janusz.skonieczny/KB/Meetings"
    end
    mkdir -p "$vault"

    # Recover the start stamp + title captured by meeting-start
    set -l stamp (date '+%Y-%m-%d-%H%M')
    set -l title ''
    if test -f "$statefile"
        set -l lines (cat "$statefile")
        test (count $lines) -ge 1; and test -n "$lines[1]"; and set stamp $lines[1]
        test (count $lines) -ge 2; and set title $lines[2]
    end

    set -l slug (string lower -- "$title" | string replace -ar '[^a-z0-9]+' '-' | string trim -c '-')
    test -z "$slug"; and set slug meeting
    set -l out "$vault/$stamp-$slug.md"

    voxtype meeting export latest --format markdown --speakers --metadata --output "$out"
    if test $status -ne 0
        echo "Export failed — transcript is still saved in voxtype (voxtype meeting list)." >&2
        return 1
    end

    rm -f "$statefile"
    echo "📝 Transcript → $out"
end
