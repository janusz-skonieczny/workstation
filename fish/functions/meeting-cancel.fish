function meeting-cancel --description 'Stop the current meeting and discard it (prompts before deleting)'
    voxtype meeting stop
    if test $status -ne 0
        echo "No active meeting to cancel (meeting-status)." >&2
        return 1
    end
    rm -f "$HOME/.local/state/voxtype-meeting.state"

    read -l -P 'Delete the just-stopped meeting permanently? [y/N]: ' ok
    if string match -qi 'y' -- "$ok"
        voxtype meeting delete latest --force
        and echo "Discarded."
    else
        echo "Kept — export later with: voxtype meeting export latest -o <file>.md"
    end
end
