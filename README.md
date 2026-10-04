# MiWRT

OpenWrt firmware for the Xiaomi BE7000 (board RC06, Qualcomm IPQ9554), tuned to get the most out of the hardware, with a built-in service for a phone app.

MiWRT is built on [Beam WRT](https://github.com/timofey-maykov/be7000-openwrt) by timofey-maykov, which in turn stands on the kravasuper port of OpenWrt to this router. Everything Beam WRT does, MiWRT does: native boot from flash (no kexec), the stock firmware kept in the second slot, two-slot updates with automatic fallback, Wi-Fi 7 on 5 GHz, the 2.5 Gbit/s ports, USB 3, NFC, the split 5 GHz modes and the PPE offload work. The original documentation is kept in [docs/upstream](docs/upstream/README.en.md).

Released version: **1.4.0.2**, based on Beam WRT 1.4.0 (OpenWrt main d958caf, kernel 6.18.52). Images are in [Releases](https://github.com/iroham/be7000-openwrt/releases), checksums in `sha256sums.txt`.

The `miwrt` branch is ahead of that release: the app service, the new logo and theme colours described below are in the source and will ship with 1.4.0.3. They are not in the 1.4.0.2 images.

## Contents

- [What MiWRT changes in the firmware](#what-miwrt-changes-in-the-firmware)
- [The app service (next release)](#the-app-service-next-release)
- [The phone app](#the-phone-app)
- [Installing, updating, going back](#installing-updating-going-back)
- [Building](#building)
- [Licence and credits](#licence-and-credits)

## What MiWRT changes in the firmware

### The radios run on Xiaomi's own board data

Board data tells a Wi-Fi chip about the board it sits on: the RF front end, antennas, power targets per channel. Beam WRT 1.4.0 loads Qualcomm's generic reference-board data for both radios in their normal mode. MiWRT ships the files Xiaomi built for this router, taken from the stock firmware:

| Radio | Board data | Measured on a test unit |
|---|---|---|
| 5 GHz (QCN9274) | `bdwlan.b0002` (single radio) and `bdwlan.b1008` (split mode) | transmit power on channel 36 rises to the full UK/EU limit (19 → 23 dBm); downlink to a 2×2 Wi-Fi 6E laptop at 160 MHz ~800 → ~1,000 Mbit/s |
| 2.4 GHz (IPQ9554) | `bdwlan.b20`, with the generic file's regulatory table kept | loads cleanly, no measurable change; it is the data the board shipped with |

A boot service (`be7000-board-data`) puts the Xiaomi files back if a package reinstall ever restores the generic ones.

One 2.4 GHz firmware crash was seen on the test unit 46 minutes after first boot with `b20`, and none in the days after. A single event does not show the board data caused it. The app service below restarts the router if a radio crashes and stays down.

### Radar channels and 160 MHz work out of the box

OpenWrt only enables radar detection (DFS) when a country is set. Without one, channels 52-144 and every 160 MHz setting are silently unavailable. MiWRT sets a country on first boot for radios that have none (`GB` by default; change it under Network, Wireless).

### Split-mode fix

Returning from the two-radio 5 GHz mode to one radio left the upper radio's channel (149) behind; combined with 160 MHz that is a setting hostapd cannot start, and 5 GHz stayed down. The split script now saves the single-radio channel and width and restores them.

### Shipped in the image

`sqm-scripts` and its LuCI page (cake), `nlbwmon` and its page (per-device traffic accounting), `banip` and its page (IP block lists), `umdns` (mDNS) and `tcpdump-mini`. They survive every sysupgrade without depending on the feed.

### Name and look

The system calls itself MiWRT in LuCI, the console banner and `/etc/openwrt_release`; the default hostname is `MiWRT`. From the next release the web interface carries the MiWRT mark (a roof line that turns into a signal) and indigo accent colours. Image file names stay `openwrt-qualcommbe-ipq95xx-xiaomi_be7000-…`, which the installer and the update page look up by name.

## The app service (next release)

A small service on the router that a phone app talks to. Nothing else is needed on the network, and nothing goes through a cloud. It is written in ucode and shell, lives in `overlay-files`, and uses only what the image already has (uhttpd, rpcd, umdns, nlbwmon, banIP, Lua with nixio).

| File | Purpose |
|---|---|
| `/usr/share/ucode/miwrt/hub.uc` | state collection, device list, alerts, pausing, access keys |
| `/usr/share/ucode/miwrt/extras.uc` | Wi-Fi settings, guest Wi-Fi, firmware check, blocked threats, connection test, speed test, Wi-Fi check, summaries |
| `/www/cgi-bin/miwrt` | the HTTPS API |
| `/usr/sbin/miwrt-hubd`, `/etc/init.d/miwrt` | one pass every 30 s, the network announcement, the discovery relay |
| `/usr/sbin/miwrt-ctl` | `token <name>`, `tokens`, `revoke-all` |
| `/usr/sbin/miwrt-push` | hands alerts to a notification relay, if one is set |
| `/usr/sbin/miwrt-discovery-relay` | repeats smart-home discovery broadcasts from an IoT network to the main one |
| `/usr/sbin/miwrt-wol` | Wake-on-LAN |
| `/usr/share/miwrt/oui.txt` | maker per MAC prefix |
| `/etc/miwrt/` | settings and state, kept across sysupgrade |

### Finding and pairing

- The router announces `_miwrt._tcp` (port 443) on the main network through umdns. The app finds it by itself.
- Pairing asks for the router's administrator password, the same one LuCI uses. The router checks it with its own login service and hands the phone a random 256-bit access key. Only the key's hash is stored. Five wrong passwords lock pairing for 10 minutes.
- The API is served over HTTPS with the router's own certificate. The app remembers that certificate at pairing and refuses any other afterwards.
- Every phone has its own key; keys can be listed and revoked from the app or with `miwrt-ctl`.
- The API is reachable from the main network only. Guest and IoT zones and the WAN side are rejected by the firewall.

### What it does

| Area | Details |
|---|---|
| Status | internet up or down with live rates, both radios, temperature, memory, uptime, firmware |
| Devices | online and offline, maker, network, band and signal, live rate, today and month totals, 30 days of daily history |
| Names, categories, icons | a name set in the app becomes a DHCP host entry (`miwrt_h_<mac>`), so LuCI and `name.lan` use it; optional fixed address |
| Pausing | per device: until resumed, or for a set time. One list feeds one firewall rule (`/etc/miwrt/blocked.nft`, placed ahead of the established-connection rule so running streams stop too) |
| Approve new devices | optional, off by default: a device the router has never seen gets no internet until it is allowed |
| People and rooms | groups of devices; pause a group; a person counts as home when one of their phones is on Wi-Fi |
| Schedules | internet off for chosen devices or groups at set times and days, including overnight |
| Wi-Fi | view networks, change name or password, switch a network off, hand out the details for a QR code |
| Guest Wi-Fi | created on first use: own bridge, subnet and firewall zone, client isolation, optional auto-off |
| Alerts | radio crashed or recovered, internet down or back, DNS failing, new device, a device failing to join repeatedly, radar on 5 GHz, kernel errors, phone paired or unpaired |
| Notifications | alerts are handed to a relay that passes them to Apple; off by default, per alert type |
| Wi-Fi recovery | if a Wi-Fi core crashes and stays down for about 90 s, the router restarts itself: not in the first 10 minutes after boot, at most three times a day |
| Ad blocker link | links an AdGuard Home on the network: on, off, pause, statistics, recent activity, allow or block a site, block lists |
| Checks | connection test, speed test from the router, Wi-Fi channel check, blocked threats (banIP), protection overview, weekly summary, 48 hours of health samples |
| Maintenance | settings backup download, lights on, off or off at night, restart, firmware version and update check |
| Discovery relay | where an IoT network exists (`br-iot`), smart-home announcements (UDP 6666 and 6667) are repeated onto the main network so phone apps still find their devices |

### API

Base: `https://<router>/cgi-bin/miwrt`. `GET /health` and `POST /pair` need no key; everything else needs `Authorization: Bearer <key>`.

| Method and path | Purpose |
|---|---|
| `GET /v1/status`, `/v1/devices`, `/v1/alerts`, `/v1/meta` | the main screens |
| `POST /v1/devices/<mac>` | `name`, `category`, `icon`, `blocked`, `pause_minutes`, `approve`, `fixed_ip` |
| `POST /v1/devices/<mac>/wake` | Wake-on-LAN |
| `GET`/`POST /v1/groups`, `/v1/schedules` | people and rooms, schedules |
| `POST /v1/settings` | `approve_new`, `watchdog`, `night`, `push` |
| `GET /v1/wifi`, `/v1/wifi/secret?id=`, `/v1/wifi/check`; `POST /v1/wifi/<id>` | Wi-Fi |
| `GET`/`POST /v1/guest` | guest Wi-Fi |
| `GET /v1/protection`, `/v1/protection/lists`, `/v1/protection/log`, `/v1/protection/check`; `POST /v1/protection/connect`, `disconnect`, `pause`, `lists`, `rules` | ad blocker link |
| `GET /v1/usage`, `/v1/week`, `/v1/history`, `/v1/threats`, `/v1/overview`, `/v1/diagnose`, `/v1/firmware`, `/v1/speedtests`; `POST /v1/speedtest` | insight |
| `GET /v1/phones`; `POST /v1/phones/revoke` | paired phones |
| `GET /v1/push`; `POST /v1/push/register`, `/v1/push/test` | notifications |
| `GET /v1/router/backup`; `POST /v1/router/leds`, `/v1/router/watchdog`, `/v1/router/reboot` | maintenance |

### Design notes

- The 30 s pass writes only to memory. Flash is written when something changes (a rename, a new device, an alert) and once a day for traffic totals.
- Every value that reaches a shell command is a constant or checked against a strict pattern; request bodies go through files.
- One writer at a time: the background pass and API requests share a file lock.
- If the pause-list file is missing or malformed the firewall ignores it and still starts.
- Notifications: Apple only delivers a push signed with the app publisher's key, which cannot be put into firmware. A router therefore sends the alert's title and text to a relay that holds the key. No relay is configured by default.

## The phone app

A native iPhone app (SwiftUI) for this service exists and is in testing; it is not in this repository yet. It finds the router, pairs with the administrator password, and covers everything in the table above.

## Installing, updating, going back

The procedures are the same as Beam WRT's and come with every release archive:

- [Install from stock](docs/instruction/1-install-en.txt) (needs root SSH on the stock firmware)
- [Update](docs/instruction/2-update-en.txt): System, Build update in LuCI, or `be7000-update apply`, or sysupgrade with the `…-sysupgrade.bin` from a release. Settings are kept.
- [Back to stock, and troubleshooting](docs/instruction/3-rollback-and-problems-en.txt): System, Slots in LuCI switches to the stock firmware in the other slot.

Coming from Beam WRT: install the MiWRT `sysupgrade.bin` over it. Package feed and update page then follow this repository.

Never write to the bootloader partitions `0:APPSBL` and `0:APPSBL_1`.

## Building

GitHub Actions builds everything: a tag `v*` produces the images, the signed package feed on this repository's GitHub Pages, and a release. The workflow needs one secret, `APK_SIGNING_KEY` (an EC P-256 private key in PEM); images trust its public key. Details in [docs/building.en.md](docs/building.en.md).

Pushing to the branch does not build. Only a version tag does.

## Licence and credits

Patches under `patches/` are GPL-2.0-only, like the Linux kernel; scripts and text can be used freely. Images are built from OpenWrt sources, the kravasuper port, the Beam WRT patches and the changes above. Xiaomi's board data files are redistributed in the form kravasuper's board repository and the stock firmware carry them. The maker list (`oui.txt`) is derived from the IEEE's public registry.

Thanks to timofey-maykov for Beam WRT, to kravasuper for the port, and to everyone listed on the System, Credits page.
