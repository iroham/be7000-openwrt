#!/bin/sh
# Shared by the scripts that reboot on purpose early in a boot, before
# be7000-bootconfirm (START=99) has confirmed it: bigoverlay and
# be7000-extroot boot-sync, both on the first boot after a sysupgrade.
#
# The bootloader adds one to the slot's flag_try_sys{N}_failed on every boot.
# Left alone, a planned reboot shows up on the next boot as a boot that broke
# off, and 76_be7000_extroot_guard starts that boot without USB. The callers
# have their own guards against looping, so the counter goes back to zero.

be7000_bootcount_clear() {
	local arg
	for arg in $(cat /proc/cmdline); do
		case "$arg" in
		ubi.mtd=rootfs)   fw_setenv flag_try_sys1_failed 0 ;;
		ubi.mtd=rootfs_1) fw_setenv flag_try_sys2_failed 0 ;;
		esac
	done 2>/dev/null
}
