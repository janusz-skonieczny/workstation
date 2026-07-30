# OS Migration Procedure

Moving to a fresh Kubuntu install on a new disk, without losing
configs, credentials, or shell history. Pairs with `migrate/backup.sh`
and `migrate/restore.sh`.

Assumptions: project data lives on a separate disk (e.g. `/work`) that
survives the reinstall; the backup is staged there.

## Phase 1 — Backup (old system)

```bash
# 1. Stage configs, credentials, histories, /etc and manifests:
migrate/backup.sh

# 2. Re-run with the sudo extras (Wi-Fi/VPN profiles, host keys,
#    docker daemon config) and optional user data:
WITH_SUDO=1 USER_DATA=1 migrate/backup.sh

# 3. Optionally include Claude Code per-project state (~2 GB):
FULL_CLAUDE=1 migrate/backup.sh
```

Then verify:

- `du -sh /work/migration/<host>-<date>/*` — sanity-check sizes.
- Spot-check `home/.local/share/fish/fish_history` is present.
- Confirm cloud-synced dirs (GDrive, Dropbox) do NOT need copying —
  they re-sync on the new install.
- Docker volumes are **not** backed up: containers here are disposable
  and every database that matters is remote. `manifests/docker-volumes.txt`
  lists the volume names so compose stacks can be recreated on demand.

## Phase 2 — Hardware

1. Install the new NVMe in the correct M.2 slot (see your board manual:
   prefer a CPU-attached slot that does **not** share lanes with the
   x16 GPU slot).
2. Physically disconnect any disk you plan to retire *before*
   installing — the installer can't put the bootloader on the wrong
   EFI partition if that disk isn't there.
3. Keep the data disk(s) connected only if you're confident; plugging
   them back in after the first successful boot is the safer order.

## Phase 3 — Fresh install

1. Install Kubuntu on the new disk. Prefer manual partitioning with
   `/home` as a **separate partition** — it survives future reinstalls
   and can later be moved to its own disk with one rsync + one fstab
   line. With plenty of RAM, skip swap: remove the installer-created
   `/swapfile` and its fstab entry after the first boot.
2. First boot: verify network. If the NIC needs an out-of-tree driver
   (e.g. Realtek r8125 DKMS), the source tree is in the backup under
   `home/realtek-r8125-dkms`. **Do not restore module blacklists before
   the module they exist for is built** — see below.
3. Re-add data-disk mounts to `/etc/fstab` **by UUID and with
   `nofail`** — never by `/dev/nvmeXnY` path, and never without
   `nofail`: NVMe enumeration order is not stable, and a missing disk
   must not hang boot. For NTFS disks use the in-kernel `ntfs3`
   fstype instead of the ntfs-3g FUSE driver.

### Module blacklists are a one-way trap on a fresh install

An out-of-tree NIC driver only wins the device if the in-tree driver is
kept out of the way. On this machine the RTL8125 2.5GbE port (`10ec:8125`)
is claimed by **both** in-tree `r8169` and the `r8125` DKMS module, and
`/etc/modprobe.d/blacklist.conf` carries a hand-appended `blacklist r8169`
so the DKMS one binds.

`blacklist <mod>` suppresses only *automatic, alias-driven* loading — udev
skips the module when resolving a device's modalias. An explicit `modprobe
r8169` still works, and so does loading as another module's dependency.
Full suppression needs `install r8169 /bin/false`.

Restoring that blacklist onto a fresh install **before** DKMS has built
`r8125` for the new kernel leaves *nothing* claiming the NIC: not a slow
link, not a down interface — no interface at all, on the machine you need
online to bootstrap.

Rules that follow:

- `restore.sh` never auto-restores `/etc`, so this cannot happen by
  accident. Keep it that way.
- Prefer the in-tree driver. `lspci -nnk` lists every module claiming a
  device (`Kernel modules: r8169, r8125`); if the in-tree one is listed,
  the fresh install will come up unaided and the DKMS module is a
  performance preference, not a requirement.
- If the out-of-tree driver is genuinely wanted: build it first, confirm
  `dkms status` shows it installed **for the running kernel**, and only
  then add the blacklist.
- Put it in **its own drop-in**, never in `blacklist.conf` — that file is
  dpkg-owned (`kmod`), so a package upgrade raises a conffile prompt and
  accepting the maintainer's version silently drops the line:

  ```
  # /etc/modprobe.d/r8125.conf
  # RTL8125 (10ec:8125) is claimed by both in-tree r8169 and the r8125
  # DKMS module. Blacklist r8169 so the DKMS driver binds the 2.5GbE port.
  blacklist r8169
  ```

  A separate file survives upgrades and explains itself. The line in
  `blacklist.conf` on the old system had no comment at all, wedged after
  an unrelated `amd76x_edac` entry.

## Phase 4 — Bootstrap + restore

```bash
# 1. Bootstrap the toolchain:
curl -L https://raw.githubusercontent.com/wooyek/workstation/master/get.sh | bash

# 2. Restore configs and credentials:
migrate/restore.sh /work/migration/<host>-<date>
```

**Before starting Docker for the first time:** if the old system kept
Docker's `data-root` on the surviving disk (check `etc/docker/daemon.json`
in the backup), restore that file first — otherwise the fresh Docker
initializes an empty `/var/lib/docker` and all images/volumes on the
data disk look "gone" until the config is pointed back at them:

```bash
sudo cp <backup>/etc/docker/daemon.json /etc/docker/daemon.json
sudo systemctl restart docker
```

## Phase 5 — Re-authentication & verification

`restore.sh` prints the checklist. The short version:

| Survives the copy | Needs re-auth |
|---|---|
| SSH keys, AWS profiles, kubeconfigs | gcloud login |
| GPG keyring, git config + hooks | GitHub CLI (verify) |
| fish/bash/psql/ipython history | Docker registries (first pull) |
| KDE Wallet / keyrings (same login password only) | Browser sign-in / sync |
| Claude Code skills, agents, memory | Anything TPM-bound |

Rotate any secret that was stored in plaintext configs before you
grant the backup copies long-term shelf life.

## Notes

- The backup is incremental — re-run `backup.sh` right before the
  final shutdown to catch last-minute changes.
- LLM model stores are cache, not settings — keep them on the
  surviving data disk, outside the backup, so they need neither
  copying nor re-downloading: `set -Ux OLLAMA_MODELS /work/ai/ollama`
  (fish universal vars transfer via `fish_variables`), optionally
  `HF_HOME=/work/ai/huggingface`, and LM Studio → Settings → Models
  directory.
- JetBrains IDEs restore their settings but **not** their plugins —
  those re-download from the marketplace. Work through
  `manifests/jetbrains-plugins.txt` to re-add them per IDE.
- Keep the retired OS disk untouched for a couple of weeks as a
  fallback before wiping it.
