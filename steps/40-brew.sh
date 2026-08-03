#!/usr/bin/env bash

# Homebrew (Linuxbrew) + formulae listed in lists/brew.txt.
# Some casks (lm-studio, codex, gcloud-cli) do install on Linuxbrew and are
# used here — prefix such a line with "--cask".
cd "$(dirname "$0")/.." || exit 1

if ! command -v brew >/dev/null 2>&1; then
    echo "----> Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

echo "----> Installing from lists/brew.txt"
total=$(grep -cve '^[[:space:]]*$' lists/brew.txt)
i=0
while read -r package || [ -n "$package" ]; do
    [ -z "$package" ] && continue
    i=$((i + 1))
    echo "**** [$i/$total] Installing $package"
    # A fully qualified owner/tap/formula no longer auto-taps — tap it first.
    case "$package" in
        */*/*) brew tap "${package%/*}" ;;
    esac
    brew install $package
done <lists/brew.txt
