#!/usr/bin/env bash

# Workstation bootstrap — runs steps/ in numeric order.
# Each step is idempotent and safe to re-run.

cd "$(dirname "$0")" || exit 1

run() {
    echo "»»»» $1"
    bash "$1"
}

run steps/00-base.sh
run steps/05-sysctl.sh
run steps/06-logging.sh
run steps/10-apt.sh
run steps/15-debs.sh

for repo in steps/20-repos/*.sh; do
    run "$repo"
done

run steps/30-snap.sh
run steps/40-brew.sh
run steps/50-python.sh
run steps/55-vendor.sh
run steps/56-go.sh
run steps/57-cargo.sh
run steps/58-uv.sh
run steps/60-shell.sh
run steps/70-desktop.sh
