# workstation

Scripts for partially unattended setup of my Linux workstation

## Setup

These scripts help me get a new OS to install ready for work quickly:

	curl -L https://raw.githubusercontent.com/wooyek/workstation/master/get.sh | bash

I currently run Kubuntu.

## Layout

`bootstrap.sh` runs the numbered steps in order; each step is
idempotent and safe to re-run:

| Step | Purpose | Source |
|------|---------|--------|
| `00-base.sh` | dirs, apt update/upgrade, ssh | — |
| `10-apt.sh` | apt packages | `lists/apt.txt` |
| `15-debs.sh` | local `.deb`s | `~/Downloads/Packages` |
| `20-repos/*.sh` | repo-gated installers (docker, gh, …) | — |
| `30-snap.sh` | snaps | `lists/snap.txt` |
| `40-brew.sh` | Homebrew + formulae | `lists/brew.txt` |
| `50-python.sh` | pipx apps | `lists/pipx.txt` |
| `55-vendor.sh` | self-managing installers (rustup, uv, starship, zoxide, tx, pyenv) | `steps/55-vendor/` |
| `56-go.sh` | go CLIs | `lists/go.txt` |
| `57-cargo.sh` | cargo crates | `lists/cargo.txt` |
| `58-uv.sh` | uv-managed CLI tools | `lists/uv.txt` |
| `59-piper.sh` | Piper TTS voice model | — |
| `60-shell.sh` | fish + oh-my-fish | `fish_setup.fish` |
| `70-desktop.sh` | fonts, theme, locales | — |

`components/` keeps reference scripts (`archive/`, `experimental/`,
`optional/`) that are **not** auto-run.

## Migration

`migrate/backup.sh` stages configs, credentials and shell history onto
a surviving disk before an OS reinstall; `migrate/restore.sh` brings
them back after bootstrap. Full procedure: [docs/MIGRATION.md](docs/MIGRATION.md).

## No splash screen on boot

Replace `GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"` with `GRUB_CMDLINE_LINUX_DEFAULT=""` in `/etc/default/grub` then run `sudo update-grub`.


## Kubuntu widgets

- https://github.com/orblazer/plasma-applet-resources-monitor
- https://github.com/Zren/plasma-applet-volumewin7mixer
- https://github.com/Zren/plasma-applet-eventcalendar

## TODO

These require manual settings (help getting them scripted is appreciated):

1. Setup terminal to use [Sauce Code Pro Nerd Font Complete Mono](https://github.com/ryanoasis/nerd-fonts/blob/master/patched-fonts/SourceCodePro/Regular/complete/Sauce%20Code%20Pro%20Nerd%20Font%20Complete%20Mono.ttf)
2. Setup [Dracula color scheme](https://store.kde.org/p/1001521)
3. Setup Papirus icon set
4. Disable [quiet splash during boot](https://askubuntu.com/questions/33416/how-do-i-disable-the-boot-splash-screen-and-only-show-kernel-and-boot-text-inst)

