PART_NAME=firmware
REQUIRE_IMAGE_METADATA=1

RAMFS_COPY_BIN='fw_printenv fw_setenv head cmp sha256sum tr mktemp'
RAMFS_COPY_DATA='/etc/fw_env.config /var/lock/fw_printenv.lock'

# A line on the console and in the upgrade log.
be7000_log() {
	echo "$*"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> /tmp/be7000-upgrade.log
}

# Keep the upgrade log where the next boot (of either slot) can read it: the
# settings volume "cfg", which no slot write touches. MiWRT reads it from
# /etc/miwrt/last-upgrade.log. Nothing happens when that volume is not there.
be7000_save_log() {
	local u dev="" mnt=/tmp/be7000-cfg
	for u in /sys/class/ubi/ubi*_*; do
		[ "$(cat "$u/name" 2>/dev/null)" = cfg ] && dev="${u##*/}"
	done
	[ -n "$dev" ] || return 0
	mkdir -p "$mnt"
	mount -t ubifs "/dev/$dev" "$mnt" 2>/dev/null || return 0
	if [ -d "$mnt/upper/etc" ]; then
		mkdir -p "$mnt/upper/etc/miwrt"
		cp /tmp/be7000-upgrade.log "$mnt/upper/etc/miwrt/last-upgrade.log"
		[ -f /tmp/be7000-upgrade.out ] && tail -n 60 /tmp/be7000-upgrade.out > "$mnt/upper/etc/miwrt/last-upgrade.out"
	fi
	sync
	umount "$mnt"
}

# Does the slot now carry the two volumes the bootloader needs?
be7000_slot_ok() {
	local part="$1" mtdnum="$2" ubidev
	ubidev="$(nand_find_ubi "$part")"
	[ -n "$ubidev" ] || { ubiattach -m "$mtdnum" >/dev/null 2>&1; ubidev="$(nand_find_ubi "$part")"; }
	[ -n "$ubidev" ] || return 1
	[ -n "$(nand_find_volume "$ubidev" kernel)" ] && [ -n "$(nand_find_volume "$ubidev" ubi_rootfs)" ]
}

be7000_do_upgrade() {
	local image="$1"
	local mtdnum target_slot target_part

	# Upgrade the slot we are running from and never touch the other one.
	#
	# The other slot holds the stock firmware, and it is the only recovery
	# path there is: after a few failed boots the bootloader falls back to it.
	# The previous version always wrote rootfs_1, which silently destroyed
	# that fallback on units where OpenWrt had been installed into slot 0.
	#
	# The running slot comes from the kernel command line, which the
	# bootloader fills in, so it reflects what actually booted rather than
	# what the flags claim.
	#
	# Matched word by word on purpose: the command line carries a second
	# ubi.mtd= for the spare overlay partition, and a greedy match would
	# return that one instead of the slot.
	target_part=""
	for arg in $(cat /proc/cmdline); do
		case "$arg" in
		ubi.mtd=rootfs)   target_part="rootfs";   target_slot=0 ;;
		ubi.mtd=rootfs_1) target_part="rootfs_1"; target_slot=1 ;;
		esac
	done
	if [ -z "$target_part" ]; then
		echo "Cannot tell which slot is running from /proc/cmdline, refusing to flash"
		return 1
	fi

	# Escape hatch for deliberately staging an image into the other slot, e.g.
	# when testing a kernel that may not boot. Not used by a normal upgrade.
	case "$BE7000_TARGET_SLOT" in
	0) target_slot=0; target_part="rootfs" ;;
	1) target_slot=1; target_part="rootfs_1" ;;
	esac

	mtdnum="$(find_mtd_index "$target_part")"
	if [ -z "$mtdnum" ]; then
		echo "Unable to find target partition $target_part"
		return 1
	fi

	if ! command -v fw_setenv >/dev/null; then
		echo "fw_setenv is required to switch BE7000 boot slot"
		return 1
	fi

	echo "Writing OpenWrt image to Xiaomi OpenWrt UBI slot $target_part (slot $target_slot)"
	CI_UBIPART="$target_part"
	CI_ROOTPART="ubi_rootfs"
	# sysupgrade creates a "provisioning" volume by default since OpenWrt
	# 725a1dc534. It is made before the kernel volume and takes volume 0,
	# and the stock bootloader loads the kernel from volume 0: the slot
	# never boots again (amber LED until the bootloader gives up on it).
	UPGRADE_OPT_ADD_PROVISIONING=0

	# MiWRT: the slot is erased before it is written, so a write that stops
	# halfway leaves nothing to boot (seen once: an erased slot, no volumes,
	# and no record of why). The write is now checked, tried a second time,
	# and every step is noted in a log kept on the settings volume, which is
	# outside both slots. If both tries fail, the boot is pointed at the
	# other slot (the factory firmware) at once.
	be7000_log "upgrade of slot $target_part (mtd$mtdnum), image $(wc -c < "$image") bytes"
	nand_detach_ubi "$target_part" >>/tmp/be7000-upgrade.out 2>&1 || {
		be7000_log "could not detach the slot, nothing written"
		be7000_save_log
		return 1
	}
	local try=1
	while :; do
		if ubiformat "/dev/mtd$mtdnum" -y >>/tmp/be7000-upgrade.out 2>&1 &&
		   nand_do_flash_file "$image" "fwtool -q -i /tmp/sysupgrade.meta -T $image" >>/tmp/be7000-upgrade.out 2>&1 &&
		   be7000_slot_ok "$target_part" "$mtdnum"; then
			be7000_log "image written and checked (try $try)"
			break
		fi
		be7000_log "write failed (try $try): $(tail -n 6 /tmp/be7000-upgrade.out | tr '\n' ' ')"
		if [ "$try" -ge 2 ]; then
			local other=$((1 - target_slot))
			fw_setenv flag_boot_rootfs "$other"
			fw_setenv flag_last_success "$other"
			fw_setenv flag_ota_reboot 0
			be7000_log "giving up, next boot goes to slot $other (factory firmware)"
			be7000_save_log
			return 1
		fi
		try=$((try + 1))
		nand_detach_ubi "$target_part" >>/tmp/be7000-upgrade.out 2>&1
	done

	echo "Switching Xiaomi boot slot to $target_slot"
	fw_setenv flag_boot_rootfs "$target_slot" || return 1
	fw_setenv flag_last_success "$target_slot" || return 1
	fw_setenv flag_boot_success 1 || return 1
	fw_setenv flag_try_sys1_failed 0 || return 1
	fw_setenv flag_try_sys2_failed 0 || return 1
	fw_setenv flag_ota_reboot 0 || return 1

	nand_do_restore_config || { be7000_log "settings could not be carried over"; be7000_save_log; return 1; }
	be7000_log "done, rebooting into slot $target_slot"
	be7000_save_log
	sync

	return 0
}

platform_check_image() {
	case "$(board_name)" in
	linksys,ln6001)
		ln6001_preflight "$1" || {
			echo "LN6001 A/B preflight failed" >&2
			return 1
		}
		return 0
		;;
	*)
		return 0
		;;
	esac
}

platform_do_upgrade() {
	case "$(board_name)" in
	8devices,kiwi-dvk)
		CI_KERNPART="0:HLOS"
		CI_ROOTPART="rootfs"
		emmc_do_upgrade "$1"
		;;
	askey,sbe1v1k)
		CI_KERNPART="0:HLOS"
		CI_ROOTPART="rootfs"
		CI_DATAPART="rootfs_data"
		emmc_do_upgrade "$1"
		;;
	linksys,ln6001)
		ln6001_do_upgrade "$1" || return 1
		;;
	xiaomi,be7000)
		sync
		be7000_do_upgrade "$1" && {
			echo "sysupgrade successful"
			umount -a
			reboot -f
		}
		echo "sysupgrade failed"
		return 1
		;;
	*)
		default_do_upgrade "$1"
		;;
	esac
}

platform_copy_config() {
	case "$(board_name)" in
	8devices,kiwi-dvk|\
	askey,sbe1v1k)
		emmc_copy_config
		;;
	esac
}
