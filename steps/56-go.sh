#!/usr/bin/env bash

# Install Go CLIs listed in lists/go.txt with `go install`.
#
# `go install <path>@<version>` compiles the binary into ~/go/bin
# ($GOPATH/bin). Unlike the pnpm shims, Go binaries there are relocatable,
# so we only need that dir on PATH — no wrapper needed. apt's golang-go may
# be older than a module requires; Go's default GOTOOLCHAIN=auto downloads
# the newer toolchain on demand (e.g. frisco needs Go 1.26+).
cd "$(dirname "$0")/.." || exit 1

if ! command -v go >/dev/null 2>&1; then
    echo "go not found — skipping (installed via lists/apt.txt: golang-go)"
    exit 0
fi

gobin="$(go env GOBIN)"
[ -n "$gobin" ] || gobin="$(go env GOPATH)/bin"
mkdir -p "$gobin"

# Put the Go bin dir on PATH in fish (the one shell whose default PATH does
# not include it). Guarded so re-runs stay idempotent.
if [ -d "$HOME/.config/fish/conf.d" ]; then
    cat >"$HOME/.config/fish/conf.d/go.fish" <<FISH
# Go install bin dir (managed by steps/56-go.sh)
if not contains -- $gobin \$PATH
    fish_add_path $gobin
end
FISH
fi

echo "----> Installing Go CLIs from lists/go.txt"
total=$(grep -cve '^[[:space:]]*#' -e '^[[:space:]]*$' lists/go.txt)
i=0
while read -r module || [ -n "$module" ]; do
    case "$module" in
        ''|\#*) continue ;;
    esac
    i=$((i + 1))
    echo "**** [$i/$total] Installing $module with go install"
    go install "$module"
done <lists/go.txt
