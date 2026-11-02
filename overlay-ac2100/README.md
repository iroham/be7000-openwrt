# overlay-ac2100

Files only the Xiaomi Redmi Router AC2100 image gets. `scripts/ac2100/assemble-files.sh` copies the MiWRT pieces shared with the BE7000 (the app service, the Nimbus theme, System, Build update, the translations) from `overlay-files` by an explicit list, then this directory on top, and the ImageBuilder puts the result into the image.

Nothing here is read by the BE7000 build, and nothing in `overlay-files` is changed for this router.

| File | Purpose |
|---|---|
| `etc/banner` | the console greeting |
| `etc/uci-defaults/10-miwrt-identity` | writes "MiWRT <version> ..." into the description fields people read, leaving the OpenWrt release in the fields third-party scripts check |
| `etc/uci-defaults/90-miwrt-ac2100-network` | software flow offloading on, packet steering explicitly off |
| `etc/uci-defaults/91-miwrt-wifi-defaults` | enables the Wi-Fi defaults service after an update |
| `etc/init.d/miwrt-wifi-defaults`, `etc/rc.d/S99miwrt-wifi-defaults` | on a fresh install: both radios on, SSID `MiWRT`, the serial number as the password, country GB, no group-key renewal on 5 GHz |
| `etc/sysupgrade.conf` | what an update keeps besides the defaults |

The release file `/etc/miwrt-release` (version, tag, device, tag prefix, `PRERELEASE_OK=1` while in testing) is written by the assemble script, not kept here; the workflow adds `/etc/apk/keys/public-key.pem`, the MiWRT signing key, when the secret is available.
