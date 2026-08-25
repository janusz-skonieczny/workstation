#!/usr/bin/env bash

# earlyoom — kill the biggest memory hog while the desktop still responds.
#
# On 2026-08-25 concurrent AI-agent sessions spawned ~76 vitest workers
# holding 82 GB; the kernel OOM killer fired far too late, picked a Chrome
# renderer (browsers self-raise oom_score_adj to 300), and the thrash took
# down journald before the UI ever came back. earlyoom acts at ~10% free,
# before the thrash zone, and can be biased toward the real culprits.
#
# Config is a systemd drop-in, not an edit to /etc/default/earlyoom: that
# file is a dpkg conffile, so a package upgrade raises a conffile prompt
# and accepting the maintainer's version silently drops the settings —
# same reasoning as steps/05-sysctl.sh. The stock EnvironmentFile= must be
# cleared, because variables it sets override Environment= from drop-ins.
#
# Two quoting layers, easy to get wrong (the first attempt crash-looped
# the service): the Environment= directive splits an unquoted value on
# spaces into separate assignments (EARLYOOM_ARGS became just "-r"), so
# the whole VAR=value must sit inside double quotes. The value itself
# must contain NO quotes: $EARLYOOM_ARGS expands with word-splitting but
# no quote removal, so quoted regexes reach earlyoom with literal quote
# characters and silently match nothing. Single-word regexes need none.

echo "----> earlyoom (userspace OOM killer)"

if ! command -v earlyoom > /dev/null; then
    sudo apt-get install -y earlyoom
fi

sudo mkdir -p /etc/systemd/system/earlyoom.service.d

sudo tee /etc/systemd/system/earlyoom.service.d/50-workstation.conf > /dev/null <<'CONF'
# Managed by workstation/steps/12-earlyoom.sh — edit there, not here.
[Service]
EnvironmentFile=
# -r 60: memory report every minute in the journal — post-mortem trail.
# -n: desktop notification when something gets killed.
# prefer test runners and node workers, protect the session and the shell
# that would be needed to recover it.
Environment="EARLYOOM_ARGS=-r 60 -n --prefer (^|/)(node|vitest|pytest) --avoid (^|/)(plasmashell|kwin_wayland|Xwayland|sshd|systemd|dbus-daemon)$"
CONF

sudo systemctl daemon-reload
# A prior crash-loop trips the start rate limit; clear it or restart is a no-op.
sudo systemctl reset-failed earlyoom 2> /dev/null || true
sudo systemctl enable --now earlyoom
sudo systemctl restart earlyoom

# A bad EARLYOOM_ARGS exits within milliseconds — catch it, don't report
# success on a dead safety net.
sleep 2
if ! systemctl is-active --quiet earlyoom; then
    echo "!!!! earlyoom failed to start:" >&2
    systemctl status earlyoom --no-pager -n 5 >&2
    exit 1
fi
echo "----> earlyoom running as: $(ps -o args= -C earlyoom)"
