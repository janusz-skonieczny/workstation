#!/usr/bin/env bash

# Spin down the archive disk when idle.
#
# /arch lives on an ST2000DL004 HD204UI (Samsung SpinPoint F4 EG, 5400rpm,
# 2010 vintage) that is read rarely and written almost never — 15 writes in a
# 15-hour uptime when this was measured. Left alone it spins continuously for
# nothing.
#
# A udev rule, not a block appended to /etc/hdparm.conf: that file is a
# dpkg conffile owned by the hdparm package, so editing it raises a conffile
# prompt on release upgrade and accepting the maintainer's version silently
# drops the setting. Same reasoning as steps/05-sysctl.sh and modprobe.d —
# see docs/MIGRATION.md.
#
# `hdparm -S` is volatile: it is lost on reboot and on some power events, so
# it has to be reasserted whenever the device appears, which is exactly what
# udev gives us. Matching on ID_SERIAL means the rule no-ops on a machine
# without this disk rather than spinning down whatever landed on /dev/sda.
#
# 241 encodes 30 minutes: hdparm -S takes 1..240 as N*5 seconds and 241..251
# as (N-240)*30 minutes. A shorter timer would trade the idle power saving for
# load/unload cycles on a drive this old, which is the wear item that matters.
#
# The drive is the Seagate-rebadged model, whose smartmontools drivedb entry
# ("Seagate Samsung SpinPoint F4 EG (AF)") carries no warning. The warning
# about SMART/hdparm commands corrupting data applies to the Samsung-branded
# "SAMSUNG HD(155|204)UI" entry, which is a different unit — see drivedb.h.
# Buggy and fixed firmware both report 1AQ10001, so the model string, not the
# firmware version, is what distinguishes them.

echo "----> Idle spindown for the /arch archive disk"

archive_disk_serial=ST2000DL004_HD204UI_S2H7J90C549974
archive_disk_spindown=241

sudo tee /etc/udev/rules.d/85-archive-spindown.rules > /dev/null <<RULE
# Managed by workstation/steps/07-disks.sh — edit there, not here.
ACTION=="add|change", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", \\
    ENV{ID_SERIAL}=="$archive_disk_serial", \\
    RUN+="/usr/sbin/hdparm -S $archive_disk_spindown /dev/%k"
RULE

sudo udevadm control --reload-rules

if [ -e "/dev/disk/by-id/ata-$archive_disk_serial" ]; then
    sudo udevadm trigger --action=change --subsystem-match=block \
        --property-match=ID_SERIAL="$archive_disk_serial"
    echo "     $(sudo hdparm -C "/dev/disk/by-id/ata-$archive_disk_serial" | tail -1)"
else
    echo "     disk not present — rule installed for when it appears"
fi
