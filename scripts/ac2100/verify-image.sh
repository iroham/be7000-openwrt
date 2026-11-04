#!/bin/sh
# Checks the Redmi AC2100 build output before it is kept or published: the
# right device and only that device, the sizes the flash layout allows, the
# packages that must and must not be in the image, and the checksums.
#
#   scripts/ac2100/verify-image.sh OUTDIR
set -u

DIR=$1
DEVICE=openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100
BOARD=xiaomi_redmi-router-ac2100     # the profile name, as sysupgrade's CONTROL file carries it
KERNEL_MAX=$((4 * 1024 * 1024))     # the kernel partition is 4 MiB
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
ok() { echo "ok: $*"; }

cd "$DIR" || { echo "no such directory: $DIR" >&2; exit 1; }

# only this device, never the Mi Router AC2100 (different flash layout, bricks).
# OpenWrt names that one xiaomi_mi-router-ac2100; ours is xiaomi_redmi-router-ac2100.
for f in *; do
	case "$f" in
	*xiaomi_mi-router*|*mi_router*) bad "an image for another router is present: $f" ;;
	esac
done

for f in "$DEVICE-squashfs-sysupgrade.bin" "$DEVICE-squashfs-kernel1.bin" "$DEVICE-squashfs-rootfs0.bin" "$DEVICE.manifest" sha256sums.txt; do
	[ -s "$f" ] && ok "present: $f ($(wc -c < "$f") bytes)" || bad "missing or empty: $f"
done

# the kernel has to fit its partition
if [ -s "$DEVICE-squashfs-kernel1.bin" ]; then
	k=$(wc -c < "$DEVICE-squashfs-kernel1.bin")
	[ "$k" -le "$KERNEL_MAX" ] && ok "kernel1.bin $k bytes fits the 4 MiB partition" || bad "kernel1.bin is $k bytes, more than the 4 MiB partition"
fi

# the sysupgrade image names the board it is for
if [ -s "$DEVICE-squashfs-sysupgrade.bin" ]; then
	ctl=$(tar -xOf "$DEVICE-squashfs-sysupgrade.bin" --wildcards 'sysupgrade-*/CONTROL' 2>/dev/null || true)
	case "$ctl" in
	*"BOARD=$BOARD"*) ok "sysupgrade.bin is for $BOARD" ;;
	*) bad "sysupgrade.bin CONTROL does not name $BOARD: $(printf '%s' "$ctl" | tr '\n' ' ')" ;;
	esac
fi

# packages that must be there, and the ones that must not
if [ -s "$DEVICE.manifest" ]; then
	for p in luci luci-ssl uhttpd rpcd rpcd-mod-ucode ucode ucode-mod-digest lua luci-lib-nixio umdns nlbwmon sqm-scripts curl openssl-util ca-bundle coreutils-timeout iwinfo dropbear kmod-mt7603 kmod-mt7615-firmware wpad-basic-mbedtls; do
		grep -q "^$p " "$DEVICE.manifest" && ok "manifest has $p" || bad "manifest lacks $p"
	done
	for p in banip docker dockerd kmod-usb-storage kmod-usb3 luci-app-be7000-slots; do
		grep -q "^$p " "$DEVICE.manifest" && bad "manifest has $p, which this image must not carry" || true
	done
fi

# checksums over the shipped files, and their signature where one was made
if [ -s sha256sums.txt ]; then
	sha256sum -c --quiet sha256sums.txt && ok "sha256sums.txt verifies" || bad "sha256sums.txt does not verify"
fi
if [ -s sha256sums.txt.sig ]; then
	[ -s "${PUBKEY:-/nonexistent}" ] && { openssl dgst -sha256 -verify "$PUBKEY" -signature sha256sums.txt.sig sha256sums.txt >/dev/null 2>&1 && ok "signature verifies with $PUBKEY" || bad "signature does not verify"; }
fi

[ "$fail" = 0 ] && echo "verify-image: all checks passed" || { echo "verify-image: FAILED" >&2; exit 1; }
