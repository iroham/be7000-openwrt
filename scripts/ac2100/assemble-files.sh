#!/bin/sh
# Builds the files/ directory the ImageBuilder copies into the Redmi AC2100
# image: the MiWRT pieces shared with the BE7000, taken from overlay-files and
# the LuCI packages by an explicit list, then overlay-ac2100 on top, then the
# release file. Nothing in overlay-files is changed; the BE7000 build does not
# read this script.
#
#   scripts/ac2100/assemble-files.sh OUT VERSION TAG BUILD OPENWRT
#     OUT      directory to create (must not exist or be empty)
#     VERSION  "1.0.0" for a release, "dev" otherwise
#     TAG      the git tag the image is built from, or empty
#     BUILD    a build identifier (the CI run id)
#     OPENWRT  the OpenWrt release the ImageBuilder came from, e.g. 25.12.6
set -eu

OUT=$1 VERSION=$2 TAG=${3:-} BUILD=${4:-} OPENWRT=$5
REPO=$(cd "$(dirname "$0")/../.." && pwd)
DEVICE=openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100
TAG_PREFIX=ac2100-v
MODEL="Redmi AC2100"

[ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && { echo "$OUT is not empty" >&2; exit 1; }
mkdir -p "$OUT"

# copy one path (file or directory) from the repository, keeping modes and symlinks
take() {
	src=$REPO/$1 dst=$OUT/$2
	[ -e "$src" ] || [ -L "$src" ] || { echo "missing in the repository: $1" >&2; exit 1; }
	mkdir -p "$(dirname "$dst")"
	cp -a "$src" "$dst"
}

# --- the app service and its first-boot wiring (shared with the BE7000) ---
take overlay-files/etc/init.d/miwrt                      etc/init.d/miwrt
take overlay-files/etc/miwrt/blocked.nft                 etc/miwrt/blocked.nft
take overlay-files/etc/uci-defaults/94_be7000_hostname   etc/uci-defaults/94_miwrt_hostname
take overlay-files/etc/uci-defaults/96-miwrt-app         etc/uci-defaults/96-miwrt-app
take overlay-files/lib/upgrade/keep.d/miwrt              lib/upgrade/keep.d/miwrt
take overlay-files/usr/share/miwrt/oui.txt               usr/share/miwrt/oui.txt
take overlay-files/www/cgi-bin/miwrt                     www/cgi-bin/miwrt
for f in extras hub power; do
	take overlay-files/usr/share/ucode/miwrt/$f.uc       usr/share/ucode/miwrt/$f.uc
done
for f in ctl discovery-relay hubd mdns-reflector push tuya upload wol; do
	take overlay-files/usr/sbin/miwrt-$f                 usr/sbin/miwrt-$f
done

# --- the LuCI translations of every MiWRT page (the sources are Russian) ---
for l in en zh-cn; do
	take overlay-files/usr/lib/lua/luci/i18n/be7000.$l.lmo usr/lib/lua/luci/i18n/be7000.$l.lmo
done

# --- the Nimbus theme with the MiWRT mark, as luci.mk would install it ---
take luci-theme-nimbus/htdocs/luci-static/nimbus                      www/luci-static/nimbus
take luci-theme-nimbus/htdocs/luci-static/resources/menu-nimbus.js    www/luci-static/resources/menu-nimbus.js
take luci-theme-nimbus/root/etc/uci-defaults/30_luci-theme-nimbus    etc/uci-defaults/30_luci-theme-nimbus
take luci-theme-nimbus/ucode/template/themes/nimbus                   usr/share/ucode/luci/template/themes/nimbus

# --- System, Build update: the page, its backend and the updater ---
U=awg-feed/luci-app-be7000-update
take $U/htdocs/luci-static/resources/view/be7000-update                 www/luci-static/resources/view/be7000-update
take $U/htdocs/luci-static/resources/view/status/include/04_be7000_update.js www/luci-static/resources/view/status/include/04_be7000_update.js
take $U/root/etc/init.d/be7000-update-check                              etc/init.d/be7000-update-check
take $U/root/etc/uci-defaults/luci-app-be7000-update                     etc/uci-defaults/luci-app-be7000-update
take $U/root/usr/sbin/miwrt-update                                       usr/sbin/miwrt-update
take $U/root/usr/sbin/be7000-update                                      usr/sbin/be7000-update
take $U/root/usr/share/luci/menu.d/luci-app-be7000-update.json           usr/share/luci/menu.d/luci-app-be7000-update.json
take $U/root/usr/share/rpcd/acl.d/luci-app-be7000-update.json            usr/share/rpcd/acl.d/luci-app-be7000-update.json
take $U/root/usr/share/rpcd/ucode/be7000-update                          usr/share/rpcd/ucode/be7000-update

# --- everything only this router has ---
cp -a "$REPO/overlay-ac2100/." "$OUT/"
rm -f "$OUT/README.md"

# --- the release file miwrt-update, the banner and the identity script read ---
mkdir -p "$OUT/etc"
{
	echo "VERSION=$VERSION"
	echo "TAG=$TAG"
	echo "DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "BUILD=$BUILD"
	echo "DEVICE=$DEVICE"
	echo "TAG_PREFIX=$TAG_PREFIX"
	echo "MODEL=$MODEL"
	echo "BASE=OpenWrt $OPENWRT"
	# every AC2100 release is a pre-release until the hardware phase is through
	echo "PRERELEASE_OK=1"
} > "$OUT/etc/miwrt-release"

# the shared scripts expect to be executable and the app's state directory to be private
chmod 755 "$OUT"/etc/init.d/* "$OUT"/etc/uci-defaults/* "$OUT"/usr/sbin/* "$OUT"/www/cgi-bin/miwrt
chmod 700 "$OUT/etc/miwrt"

echo "assembled $(find "$OUT" -type f | wc -l) files and $(find "$OUT" -type l | wc -l) links into $OUT"
