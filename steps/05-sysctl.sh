#!/usr/bin/env bash

# Kernel tunables that desktop tooling outgrows.
#
# A drop-in, not an edit to /etc/sysctl.conf: that file is dpkg-owned, so a
# release upgrade raises a conffile prompt and accepting the maintainer's
# version silently drops the lines. The same reasoning applies here as to
# modprobe.d — see docs/MIGRATION.md.
#
# The 99- prefix matters. sysctl.d applies in lexical order, last wins, and
# on KDE `kde-inotify-survey` generates
# /etc/sysctl.d/50-kde-inotify-survey-max_user_instances.conf capping
# max_user_instances at 256. That file is regenerated at runtime and says
# so, so it must be overridden rather than edited.

echo "----> Kernel tunables (inotify limits)"

sudo tee /etc/sysctl.d/99-workstation.conf > /dev/null <<'CONF'
# Managed by workstation/steps/05-sysctl.sh — edit there, not here.

# Insync, the JetBrains IDEs and webpack-style watchers each hold a watch
# per file across large trees; the ~1M default is reached in practice.
fs.inotify.max_user_watches=1048576

# One instance per watching process. kind/Kubernetes clusters spawn enough
# of them to exhaust the KDE-imposed 256.
fs.inotify.max_user_instances=8192
CONF

sudo sysctl --system > /dev/null

echo "----> inotify now: $(sysctl -n fs.inotify.max_user_watches) watches, $(sysctl -n fs.inotify.max_user_instances) instances"
