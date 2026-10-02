# MiWRT

OpenWrt firmware for the Xiaomi BE7000 (board RC06, Qualcomm IPQ9554), tuned to get the most out of the hardware.

MiWRT is built on [Beam WRT](https://github.com/timofey-maykov/be7000-openwrt) by timofey-maykov, which in turn stands on the kravasuper port of OpenWrt to this router. Everything Beam WRT does, MiWRT does: native boot from flash (no kexec), the stock firmware kept in the second slot, two-slot updates with automatic fallback, Wi-Fi 7 on 5 GHz, the 2.5 Gbit/s ports, USB 3, NFC, the split 5 GHz modes and the PPE offload work. The original documentation is kept in [docs/upstream](docs/upstream/README.en.md).

Current version: **1.4.0.2**, based on Beam WRT 1.4.0 (OpenWrt main d958caf, kernel 6.18.52). Images are in [Releases](https://github.com/iroham/be7000-openwrt/releases), checksums in `sha256sums.txt`.

## What MiWRT changes

### The radios run on Xiaomi's own board data

Board data tells a Wi-Fi chip about the board it sits on: the RF front end, antennas, power targets per channel. Beam WRT 1.4.0 loads Qualcomm's generic reference-board data for both radios in their normal mode. MiWRT ships the files Xiaomi built for this router, taken from the stock firmware:

| Radio | Board data | Measured on a test unit |
|---|---|---|
| 5 GHz (QCN9274) | `bdwlan.b0002` (single radio) and `bdwlan.b1008` (split mode) | transmit power on channel 36 rises to the full UK/EU limit (19 → 23 dBm); downlink to a 2×2 Wi-Fi 6E laptop at 160 MHz ~800 → ~1,000 Mbit/s |
| 2.4 GHz (IPQ9554) | `bdwlan.b20`, with the generic file's regulatory table kept | loads cleanly, no measurable change; it is the data the board shipped with |

A boot service (`be7000-board-data`) puts the Xiaomi files back if a package reinstall ever restores the generic ones.

### Radar channels and 160 MHz work out of the box

OpenWrt only enables radar detection (DFS) when a country is set. Without one, channels 52-144 and every 160 MHz setting are silently unavailable. MiWRT sets a country on first boot for radios that have none (`GB` by default; change it under Network, Wireless).

### Split-mode fix

Returning from the two-radio 5 GHz mode to one radio left the upper radio's channel (149) behind; combined with 160 MHz that is a setting hostapd cannot start, and 5 GHz stayed down. The split script now saves the single-radio channel and width and restores them.

### Shipped in the image

`sqm-scripts` and its LuCI page (cake), `nlbwmon` and its page (per-device traffic accounting), `banip` and its page (IP block lists), `umdns` (mDNS for separated networks) and `tcpdump-mini`. They survive every sysupgrade without depending on the feed.

### Name

The system calls itself MiWRT in LuCI, the console banner and `/etc/openwrt_release`; the default hostname is `MiWRT`. Image file names stay `openwrt-qualcommbe-ipq95xx-xiaomi_be7000-…`, which the installer and the update page look up by name.

## Installing, updating, going back

The procedures are the same as Beam WRT's and come with every release archive:

- [Install from stock](docs/instruction/1-install-en.txt) (needs root SSH on the stock firmware)
- [Update](docs/instruction/2-update-en.txt): System, Build update in LuCI, or `be7000-update apply`, or sysupgrade with the `…-sysupgrade.bin` from a release. Settings are kept.
- [Back to stock, and troubleshooting](docs/instruction/3-rollback-and-problems-en.txt): System, Slots in LuCI switches to the stock firmware in the other slot.

Coming from Beam WRT: install the MiWRT `sysupgrade.bin` over it. Package feed and update page then follow this repository.

Never write to the bootloader partitions `0:APPSBL` and `0:APPSBL_1`.

## Building

GitHub Actions builds everything: a tag `v*` produces the images, the signed package feed on this repository's GitHub Pages, and a release. The workflow needs one secret, `APK_SIGNING_KEY` (an EC P-256 private key in PEM); images trust its public key. Details in [docs/building.en.md](docs/building.en.md).

## Licence and credits

Patches under `patches/` are GPL-2.0-only, like the Linux kernel; scripts and text can be used freely. Images are built from OpenWrt sources, the kravasuper port, the Beam WRT patches and the changes above. Xiaomi's board data files are redistributed in the form kravasuper's board repository and the stock firmware carry them.

Thanks to timofey-maykov for Beam WRT, to kravasuper for the port, and to everyone listed on the System, Credits page.
