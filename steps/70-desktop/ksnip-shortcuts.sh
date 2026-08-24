#!/usr/bin/env bash

# Screenshots go through ksnip, which has the better preview and annotation
# editor, but ksnip cannot be driven from the keyboard on its own here.
# Its in-app Global Hotkeys page is dead under Wayland (the compositor refuses
# background keyboard grabs), and under Wayland ksnip loads WaylandImageGrabber,
# which exposes only --fullscreen/--current/--windowundercursor on the command
# line: no rectangle, no active window. ksnip-capture bridges the gap by letting
# Spectacle grab headlessly and handing the file to `ksnip --edit`, so ksnip
# stays the only visible UI.
#
# Spectacle keeps its remaining defaults and stays usable as the secondary
# tool: Print opens its GUI, Meta+Ctrl+Print grabs the window under the cursor.
# Only the three bindings ksnip takes over are released below.

echo "----> Installing the ksnip capture launchers"

step_dir="$(cd "$(dirname "$0")" && pwd)"
install -Dm755 "$step_dir/ksnip-capture" "$HOME/.local/bin/ksnip-capture"

applications_dir="$HOME/.local/share/applications"
mkdir -p "$applications_dir"

# NoDisplay keeps these out of the application menu — they are shortcut
# targets, not apps. It does not hide them from System Settings > Shortcuts,
# which lists whatever has a [services] group in kglobalshortcutsrc.
ksnip_launcher() {
    cat >"$applications_dir/ksnip-capture-$1.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=$2
Exec=$HOME/.local/bin/ksnip-capture $1
Icon=ksnip
Terminal=false
NoDisplay=true
EOF
}

ksnip_launcher rect "ksnip — Capture Rectangular Region"
ksnip_launcher window "ksnip — Capture Active Window"
ksnip_launcher screen "ksnip — Capture Current Screen"

# kglobalaccel resolves a [services] group to a .desktop file through ksycoca,
# so a brand-new launcher stays unlaunchable until the cache is rebuilt.
kbuildsycoca6 --noincremental >/dev/null 2>&1 || true

echo "----> Binding the ksnip capture shortcuts"

# kglobalaccel holds kglobalshortcutsrc in memory and flushes it on exit, so
# anything written underneath a running daemon is silently reverted. Stop it,
# rewrite, start it again.
kglobalaccel_was_running=false
if systemctl --user is-active --quiet plasma-kglobalaccel.service; then
    kglobalaccel_was_running=true
    systemctl --user stop plasma-kglobalaccel.service
fi

# Value format is "active,default[,friendly name]"; "none" leaves a key
# unbound while preserving the default, so Reset to Defaults still works.
ksnip_shortcut() {
    kwriteconfig6 --file kglobalshortcutsrc \
        --group services --group "ksnip-capture-$1.desktop" \
        --key _launch "$2,$2,$3"
}

ksnip_shortcut rect Meta+Shift+Print "ksnip — Capture Rectangular Region"
ksnip_shortcut window Meta+Print "ksnip — Capture Active Window"
ksnip_shortcut screen Shift+Print "ksnip — Capture Current Screen"

spectacle_release() {
    kwriteconfig6 --file kglobalshortcutsrc \
        --group services --group org.kde.spectacle.desktop \
        --key "$1" "none,$2"
}

spectacle_release RectangularRegionScreenShot Meta+Shift+Print
spectacle_release ActiveWindowScreenShot Meta+Print
spectacle_release FullScreenScreenShot Shift+Print

if [ "$kglobalaccel_was_running" = true ]; then
    systemctl --user start plasma-kglobalaccel.service
    echo "     kglobalaccel restarted"
else
    echo "     kglobalaccel not running — applies on next login"
fi
