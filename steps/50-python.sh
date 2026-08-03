#!/usr/bin/env bash

# Python tooling: pipx apps + spellcheck dicts + shared venv home.
cd "$(dirname "$0")/.." || exit 1

echo "----> Ensuring pipx"
sudo apt-get install -y pipx
pipx ensurepath

echo "----> Installing from lists/pipx.txt"
total=$(grep -cve '^[[:space:]]*$' lists/pipx.txt)
i=0
while read -r package || [ -n "$package" ]; do
    [ -z "$package" ] && continue
    i=$((i + 1))
    echo "**** [$i/$total] Installing $package with pipx"
    pipx install --force "$package"
done <lists/pipx.txt

echo "----> IDE spellchecker dictionaries"
aspell --lang pl dump master | aspell --lang pl expand | tr ' ' '\n' | sudo tee /usr/share/dictionaries-common/polish.dic

echo "----> Shared virtualenv home"
sudo mkdir -p /home/venvs
sudo chown -R "$USER:$USER" /home/venvs
mkdir -p "$HOME/.config/plasma-workspace/env/"
echo "export WORKON_HOME=/home/venvs/" >"$HOME/.config/plasma-workspace/env/workon_home.sh"
