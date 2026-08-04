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

# The small Google Meet and Google Chat popups must stay visible while the
# browser is buried, and open under the webcam so the faces on screen keep the
# eyeline on the lens.
#
# Chrome stamps every browser window with wmclass=google-chrome, so the class
# cannot tell a popup from an ordinary window. The discriminator is the caption:
# Chrome appends " - Google Chrome" to normal browser windows only, and drops it
# for popup/app windows. Meet is not installed as a PWA here, so it never gets a
# private chrome-<app-id>-Default class to match on instead.
#
# The wmclass match also keeps the full-size Google Chat PWA window out: that
# one runs under its own chrome-<app-id>-Default class, so only the popup
# matches. A plain chat.google.com tab is excluded by the caption suffix.
#
# Rule enums (kwin/src/rules.h):
#   SetRule     1=DontAffect 2=Force 3=Apply(Initially) 4=Remember 5=ApplyNow
#   StringMatch 0=Unimportant 1=Exact 2=Substring 3=RegExp
# Geometry uses Apply(3), not Force(2): Force re-pins on every change, which
# makes the window immovable. Apply places it at open time, then lets go.
# "above" stays Force(2) so the popup cannot lose its always-on-top status.
echo "----> Pinning the Google Meet and Chat popups above other windows"

# DP-3, the middle monitor carrying the webcam (logical px, 1.45 scale).
popup_monitor_x=2649
popup_monitor_width=2648
popup_monitor_height=1490

popup_width=$((popup_monitor_width / 2))
popup_height=$((popup_monitor_height / 3))
popup_top_margin=$((popup_monitor_height / 40))
popup_x=$((popup_monitor_x + (popup_monitor_width - popup_width) / 2))

popup_rule() {
    kwriteconfig6 --file kwinrulesrc --group google-popups-above --key "$1" "$2"
}

popup_rule Description "Google Meet/Chat popups - keep above, open under the webcam"
popup_rule wmclass google-chrome
popup_rule wmclassmatch 1
popup_rule wmclasscomplete false
popup_rule title '^(Meet|Google Chat)\b(?!.* - Google Chrome$).*$'
popup_rule titlematch 3
popup_rule above true
popup_rule aboverule 2
popup_rule position "$popup_x,$popup_top_margin"
popup_rule positionrule 3
popup_rule size "$popup_width,$popup_height"
popup_rule sizerule 3

popup_rules="$(kreadconfig6 --file kwinrulesrc --group General --key rules 2>/dev/null || true)"
case ",$popup_rules," in
    *",google-popups-above,"*) ;;
    ,,) popup_rules="google-popups-above" ;;
    *) popup_rules="$popup_rules,google-popups-above" ;;
esac
kwriteconfig6 --file kwinrulesrc --group General --key rules "$popup_rules"
kwriteconfig6 --file kwinrulesrc --group General --key count \
    "$(awk -F, '{print NF}' <<<"$popup_rules")"

if qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null; then
    echo "     KWin reloaded"
else
    echo "     KWin not running — applies on next login"
fi
