#!/usr/bin/env bash

# Desktop polish. Several items remain manual — see README
# "Manual settings" (Nerd Fonts, Dracula scheme, Papirus icons,
# disabling the boot splash).

echo "----> Reconfiguring locales"
sudo dpkg-reconfigure locales

# KWin's edge barrier (Plasma 6, default 100px) makes the cursor resist
# crossing between screens — painful on a 3-monitor desk. A restored kwinrc
# from Plasma 5 carries no override, so the new default silently applies.
# Schema: /usr/share/config.kcfg/kwin.kcfg, group [EdgeBarrier].
# CornerBarrier is left at its default (true) on purpose: it helps hit a
# maximized window's close button on a boundary screen.
echo "----> Disabling the KWin edge barrier between screens"
kwriteconfig6 --file kwinrc --group EdgeBarrier --key EdgeBarrier 0
if qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null; then
    echo "     KWin reloaded"
else
    echo "     KWin not running — applies on next login"
fi
