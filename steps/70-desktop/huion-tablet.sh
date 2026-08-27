#!/usr/bin/env bash

# Huion Q620M pen tablet, plus the screen-annotation setup its pad buttons
# drive.
#
# Two things had to be fixed on Plasma 6 / Wayland:
#
#  1. MapToWorkspace=true (the Plasma default) confined the pen to a centered
#     band spanning the whole workspace instead of one screen. false maps the
#     tablet surface to a single output, which is what makes the pen land
#     where the cursor is.
#
#  2. KWin's Mouse Mark effect ignores tablet pens on Wayland (KDE bug 505414,
#     still open), so it cannot be used for drawing on screen with the pen.
#     gromit-mpx takes that job. Mouse Mark stays enabled for the mouse.
#
# The old X11 approach — an htablet fish function driving xinput/xsetwacom,
# formerly ~/.config/fish/conf.d/huion.fish — is dead under Wayland and is
# fully replaced by this script. migrate/backup.sh no longer carries it.

echo "----> Configuring the Huion Q620M tablet"

# Group path is [Libinput][<vendor>][<product>][<name>]; 9580/65535 is the
# Q620M's pen device. A tablet that never enumerated on this machine yet
# still gets the right config — kcminputrc is read when it appears.
kwriteconfig6 --file kcminputrc \
    --group Libinput --group 9580 --group 65535 --group "Huion Tablet" \
    --key MapToWorkspace false

# The output is identified by a KWin UUID derived from the monitor's EDID and
# connector — so it is machine- and screen-specific. Apply the recorded one
# only when KWin knows that output; anywhere else the right move is to pick
# the screen in System Settings > Drawing Tablet, since a stale UUID would
# silently map the pen to nothing.
#
# kwinoutputconfig.json is the only place these UUIDs surface: kscreen-doctor
# reports connector names and numeric ids, never the UUID kcminputrc wants.
tablet_output_uuid=1bdd5aaf-9618-43af-9294-96b86cf1548b   # DP-3, middle Samsung 4K

if grep -q "$tablet_output_uuid" "$HOME/.config/kwinoutputconfig.json" 2>/dev/null; then
    kwriteconfig6 --file kcminputrc \
        --group Libinput --group 9580 --group 65535 --group "Huion Tablet" \
        --key OutputUuid "$tablet_output_uuid"
    echo "     pen mapped to the recorded output ($tablet_output_uuid)"
else
    echo "     recorded output not on this machine — pick the screen in"
    echo "     System Settings > Drawing Tablet (mapping mode is already"
    echo "     set to a single screen)"
fi

echo "----> Binding the Huion pad buttons"

# Pad buttons drive gromit-mpx and KWin's Mouse Mark:
#   7 (F9)             toggle gromit-mpx drawing
#   6 (Shift+F9)       clear what gromit-mpx drew
#   8 (Meta+Shift+F12) clear the last KWin Mouse Mark
pad_rebind() {
    kwriteconfig6 --file kcminputrc \
        --group ButtonRebinds --group Tablet \
        --group "HUION Huion tablet_Q620M Pad" \
        --key "$1" "Key,$2"
}

pad_rebind 6 "Shift+F9"
pad_rebind 7 "F9"
pad_rebind 8 "Meta+Shift+F12"

# Mouse Mark is useless for the pen (bug 505414 above) but still the quickest
# way to scribble with the mouse, and button 8 clears it — keep it on.
kwriteconfig6 --file kwinrc --group Plugins --key mousemarkEnabled true

if qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null; then
    echo "     KWin reloaded"
else
    echo "     KWin not running — applies on next login"
fi

echo "----> Autostarting gromit-mpx"

# gromit-mpx must already be running for the pad's F9 to toggle anything —
# it has no activation-on-demand. The package ships no autostart entry, so
# copy its own launcher into the user autostart dir unmodified.
gromit_desktop=/usr/share/applications/net.christianbeier.Gromit-MPX.desktop
if [ -f "$gromit_desktop" ]; then
    install -Dm644 "$gromit_desktop" \
        "$HOME/.config/autostart/net.christianbeier.Gromit-MPX.desktop"
    echo "     autostart entry installed"
else
    echo "     gromit-mpx not installed — see lists/apt.txt (universe)"
fi

# STATUS: the Ubuntu gromit-mpx build runs under XWayland (no layer-shell),
# so whether the F9 hotkey reaches it from a Wayland session is still
# unverified. If it does not fire, bind KDE global shortcuts to
# `gromit-mpx --toggle` / `--clear` instead of the F9 key rebinds above.
