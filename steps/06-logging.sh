#!/usr/bin/env bash

# Logging rate limits and size caps.
#
# Why this step exists: on 2026-07-30 /var/log/syslog reached 155G on a 194G
# root and took the machine to zero bytes free. `snap remove rambox` left its
# processes running; the orphaned Chromium lost /dev/shm and its netlink
# socket and retried both at ~143,000 lines/sec. All three defences below
# were absent, because all three are /etc state that a reinstall resets.
#
# Size caps alone would not have helped: logrotate only evaluates `maxsize`
# when it runs, and its timer is daily. At 1.7 GB/min the disk fills many
# times over first. Only the source-side rate limit stops a runaway logger.

set -euo pipefail

echo "----> Logging rate limits and size caps"

# ---------------------------------------------------------------------------
# 1. rsyslog imuxsock rate limit.
#
#    THE TRAP: this cannot be a /etc/rsyslog.d/ drop-in. imuxsock is loaded
#    from rsyslog.conf via RainerScript, and once loaded the legacy
#    $SystemLogRateLimit* directives are SILENTLY REFUSED — rsyslogd reports
#    "currently not permitted - did you already set it via a RainerScript
#    command", the service starts fine, and no limiting is active. The
#    parameters must sit on the module() line itself, so this edits a
#    dpkg-owned file in place rather than dropping a file in beside it.
# ---------------------------------------------------------------------------
RSYSLOG_CONF=/etc/rsyslog.conf
WANT_PARAMS='SysSock.RateLimit.Interval="5" SysSock.RateLimit.Burst="500"'

if [[ ! -f "$RSYSLOG_CONF" ]]; then
    echo "**** $RSYSLOG_CONF absent — rsyslog not installed, skipping."
elif grep -q 'SysSock.RateLimit.Interval' "$RSYSLOG_CONF"; then
    echo "**** rsyslog imuxsock rate limit already set"
else
    echo "**** Adding imuxsock rate limit to $RSYSLOG_CONF"
    sudo cp -a "$RSYSLOG_CONF" "$RSYSLOG_CONF.bak-$(date +%F)"

    # Match the module(load="imuxsock" ...) line whatever else it carries and
    # insert the two parameters before the closing paren. Anchored to
    # load="imuxsock" so no other module() line can be hit.
    sudo sed -i -E \
        "s|^(module\(load=\"imuxsock\"[^)]*)\)|\1 $WANT_PARAMS)|" \
        "$RSYSLOG_CONF"

    if grep -q 'SysSock.RateLimit.Interval' "$RSYSLOG_CONF"; then
        echo "**** Inserted"
    else
        echo "**** Could not patch the imuxsock module line — set it by hand:" >&2
        echo "     module(load=\"imuxsock\" $WANT_PARAMS)" >&2
    fi
fi

# A clean "End of config validation run" is the ONLY proof the config took.
if command -v rsyslogd > /dev/null 2>&1; then
    echo "**** Validating rsyslog config"
    if sudo rsyslogd -N1; then
        sudo systemctl restart rsyslog || true
    else
        echo "**** rsyslog config INVALID — not restarting. Fix before relying" >&2
        echo "     on rate limiting; the daemon would keep the old config." >&2
    fi
fi

# ---------------------------------------------------------------------------
# 2. journald caps. Default SystemMaxUse is 10% of the filesystem (~19G
#    here), which is a lot of disk to hand to a misbehaving logger.
# ---------------------------------------------------------------------------
echo "**** journald size and rate caps"
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-size-cap.conf > /dev/null <<'CONF'
[Journal]
SystemMaxUse=1G
RuntimeMaxUse=200M
RateLimitIntervalSec=10s
RateLimitBurst=2000
CONF
sudo systemctl restart systemd-journald || true

# ---------------------------------------------------------------------------
# 3. logrotate backstop. Not protection on its own — see the header — but it
#    bounds slow leaks between the daily timer firings.
# ---------------------------------------------------------------------------
LOGROTATE_RSYSLOG=/etc/logrotate.d/rsyslog

if [[ ! -f "$LOGROTATE_RSYSLOG" ]]; then
    echo "**** $LOGROTATE_RSYSLOG absent — skipping."
elif grep -q 'maxsize' "$LOGROTATE_RSYSLOG"; then
    echo "**** logrotate maxsize already set"
else
    echo "**** Adding daily rotation + maxsize to $LOGROTATE_RSYSLOG"
    sudo cp -a "$LOGROTATE_RSYSLOG" "$LOGROTATE_RSYSLOG.bak-$(date +%F)"
    # Ubuntu ships `weekly` with no size cap; tighten the first stanza only.
    sudo sed -i '0,/^\s*weekly\s*$/s//\tdaily\n\tmaxsize 500M/' \
        "$LOGROTATE_RSYSLOG"
    sudo logrotate --debug "$LOGROTATE_RSYSLOG" > /dev/null \
        && echo "**** logrotate config parses" \
        || echo "**** logrotate config did NOT parse — check it" >&2
fi

echo "----> Logging caps applied"
