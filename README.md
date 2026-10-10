# MiWRT

OpenWrt firmware for the Xiaomi BE7000 (board RC06, Qualcomm IPQ9554), tuned to get the most out of the hardware, with a built-in service for a phone app.

MiWRT is built on [Beam WRT](https://github.com/timofey-maykov/be7000-openwrt) by timofey-maykov, which in turn stands on the kravasuper port of OpenWrt to this router. Everything Beam WRT does, MiWRT does: native boot from flash (no kexec), the stock firmware kept in the second slot, two-slot updates with automatic fallback, Wi-Fi 7 on 5 GHz, the 2.5 Gbit/s ports, USB 3, NFC, the split 5 GHz modes and the PPE offload work. The original documentation is kept in [docs/upstream](docs/upstream/README.en.md).

Released version: **1.4.7.1**, based on Beam WRT 1.4.7 (OpenWrt main d958caf, kernel 6.18.52). What came from Beam WRT since 1.4.0 is listed [below](#beam-wrt-141-to-147). Images are in [Releases](https://github.com/iroham/be7000-openwrt/releases), checksums in `sha256sums.txt`. What changed: [release notes](docs/release-notes/v1.4.7.1.md).

## Contents

- [What MiWRT changes in the firmware](#what-miwrt-changes-in-the-firmware)
- [The app service](#the-app-service)
- [The phone app](#the-phone-app)
- [Privacy](PRIVACY.md)
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

### 5 GHz: no daily group key renewal

hostapd renews the group (broadcast) key every 24 hours. On a test unit that renewal failed for every 5 GHz client, three days running at the same minute: all of them were disconnected at once ("group key handshake failed after 4 tries"), and one phone could not pass traffic again until the radio restarted. 2.4 GHz renewed without trouble. MiWRT sets `wpa_group_rekey 0` on 5 GHz networks on first boot (a value set by hand is kept). A restart of the radio still makes a fresh key.

### Split-mode fix

Returning from the two-radio 5 GHz mode to one radio left the upper radio's channel (149) behind; combined with 160 MHz that is a setting hostapd cannot start, and 5 GHz stayed down. The split script now saves the single-radio channel and width and restores them.

### Shipped in the image

`curl` with HTTP/2 (the notification sender needs it), `sqm-scripts` and its LuCI page (cake), `nlbwmon` and its page (per-device traffic accounting), `banip` and its page (IP block lists), `umdns` (mDNS) and `tcpdump-mini`. They survive every sysupgrade without depending on the feed.

### Beam WRT 1.4.1 to 1.4.7

MiWRT 1.4.7.1 carries everything Beam WRT released up to 1.4.7. It adds to what MiWRT 1.4.0.3 did and changes none of it: the app service, the radio settings and the packages in the image are the same.

| From Beam WRT | What it brings | In the image |
|---|---|---|
| 1.4.1, 1.4.3 | MLO (one network on both 5 GHz halves) starts reliably: no scan while the network is created, a retry when one link fails, a longer allowance before falling back to two radios, correct display on the Wireless and Overview pages, the 5 GHz LED follows the MLO interface | yes |
| 1.4.1, 1.4.3 | Docker: the data directory is tested before it is accepted, containers reach the internet and their ports open from the LAN, `be7000-docker firewall` and `diag` | Docker itself is installed on request |
| 1.4.2 to 1.4.4 | An overlay on a USB disk is mounted again after a firmware update (one extra reboot, guarded against a loop); packages are restored with direct DNS when a DNS add-on is not back yet | yes |
| 1.4.2 | The official OpenWrt target snapshot is no longer a package source; kernel modules come only from the feed built for this kernel | yes |
| 1.4.2 | Zapret Manager on Services, Add-ons, with Zapret, Zapret2, ByeDPI, NetShift, sing-box and hev-socks5-tunnel in the signed feed. These are tools against provider-side blocking; nothing is installed or switched on until chosen. **Treat them as third-party software you install at your own risk:** only the first install comes from the signed feed. Zapret Manager opens its own unencrypted web port (7788) on the router and some of its menus download and run files from their authors' repositories without a check; the update buttons of Zapret, Zapret2 and NetShift install unsigned packages from their authors' releases | optional packages |
| 1.4.3 | The router checks for a new MiWRT release once a day and shows a notice in the top bar and on Overview; the switch is on System, Build update. It asks GitHub for this repository's releases and sends nothing else | yes |
| 1.4.3 | A "State (MiWRT)" LED trigger: any LED can show whether a process runs, an address answers or a command succeeds. Beam WRT also assigns the amber network LED to 2.4 GHz traffic by default; MiWRT leaves that LED alone (`/usr/libexec/be7000-leds seed` assigns it) | yes |
| 1.4.5 | System, Slots: switching to the factory firmware no longer fails with an empty reason | yes |
| 1.4.6 | Importing settings from stock also works when the router was the main unit of a Xiaomi mesh | yes |
| 1.4.7 | AmneziaWG interfaces made in LuCI come up; GRE, L2TP, PPTP, IPIP, VXLAN, 6in4, 6rd, 6to4, DS-Lite, MAP, 464XLAT, relayd, bonding, SSTP, OpenConnect, vpnc, OpenFortiVPN and MBIM/NCM modem pages are in the feed | optional packages |
| 1.4.7 | The build no longer stops on the archive hash of the 2.4 GHz radio firmware package | build only |

The third-party sources behind the optional packages are pinned to exact commits in `feeds-extra.conf`. At the time of the merge three of the four pins were the newest commit of their repository; NetShift had moved on and stays on the commit Beam WRT built and tested.

Nothing in these releases changes the Wi-Fi drivers, hostapd, the kernel or dnsmasq.

### Name and look

The system calls itself MiWRT in LuCI, the console banner and `/etc/openwrt_release`; the default hostname is `MiWRT`. The web interface carries the MiWRT mark (a roof line that turns into a signal) and indigo accent colours. Image file names stay `openwrt-qualcommbe-ipq95xx-xiaomi_be7000-…`, which the installer and the update page look up by name.

## The app service

A small service on the router that a phone app talks to. Nothing else is needed on the network, and nothing goes through a cloud. It is written in ucode and shell, lives in `overlay-files`, and uses only what the image already has (uhttpd, rpcd, umdns, nlbwmon, banIP, Lua with nixio).

| File | Purpose |
|---|---|
| `/usr/share/ucode/miwrt/hub.uc` | state collection, device list, alerts, pausing, access keys |
| `/usr/share/ucode/miwrt/extras.uc` | Wi-Fi settings and schedule, guest Wi-Fi, firmware check and install, blocked threats, connection test, speed test, Wi-Fi check, speed shaping, IoT watch, summaries |
| `/usr/share/ucode/miwrt/power.uc` | remote power for laptops: sleep and restart over SSH with a restricted key, setup scripts for macOS and Windows |
| `/www/cgi-bin/miwrt` | the HTTPS API |
| `/usr/sbin/miwrt-hubd`, `/etc/init.d/miwrt` | one pass every 30 s, the network announcement, the two relays |
| `/usr/sbin/miwrt-ctl` | `token <name>`, `tokens`, `revoke <name>`, `revoke-all`, `apns <key file> <key id> <team id>`, `apns-remove` |
| `/usr/sbin/miwrt-push` | encrypts alerts for each phone and sends them as notifications: straight to Apple when the router holds a push key, otherwise through the relay |
| `/usr/sbin/miwrt-discovery-relay` | repeats smart-home discovery broadcasts from an IoT network to the main one |
| `/usr/sbin/miwrt-mdns-reflector` | repeats mDNS (AirPlay, Chromecast, printers) between the main and the IoT network |
| `/usr/sbin/miwrt-upload` | the upload half of the speed test |
| `/usr/sbin/miwrt-wol` | Wake-on-LAN, as a broadcast and straight to the device's own address |
| `/usr/sbin/miwrt-tuya` | switches a Tuya Wi-Fi plug on the local network (protocol 3.3, 3.4, 3.5), without Tuya's cloud |
| `/usr/share/miwrt/oui.txt` | maker per MAC prefix |
| `/etc/miwrt/` | settings and state, kept across sysupgrade |

### Finding and pairing

- The router announces `_miwrt._tcp` (port 443) on the main network through umdns. The app finds it by itself.
- Pairing asks for the router's administrator password, the same one LuCI uses, and the password stays on the phone. The router keeps it as a salted hash (`/etc/shadow`); `POST /pair/start` gives the app the salt and a random value, the app computes the same hash and answers `POST /pair/finish` with an HMAC-SHA256 over both sides' random values and the fingerprint of the certificate it is talking to, and the router answers with its own. A device in between with another certificate gets a proof the router refuses; a device only posing as the router cannot produce the router's answer, and the app then saves nothing. On success the phone gets a random 256-bit access key; only the key's hash is stored. Wrong passwords are counted per address (5 in 10 minutes) and overall (40). The older `POST /pair`, which takes the password itself, stays for app versions that know nothing else.
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
| Wi-Fi | view networks, change name or password, switch a network off, hand out the details for a QR code; optional schedule that switches a network off at set times and days |
| Guest Wi-Fi | created on first use: own bridge, subnet and firewall zone, client isolation, optional auto-off |
| Alerts | radio crashed or recovered, internet down or back, DNS failing, new device, a device failing to join repeatedly, radar on 5 GHz, kernel errors, phone paired or unpaired |
| Notifications | off by default, per alert type, one switch in the app. Alert text is encrypted on the router with a key only the phone has; the relay and Apple carry it without being able to read it |
| Address service guard | if dnsmasq (addresses for devices, lookups sent to the router) stops, the next 30 s pass starts it again and raises an alert. The service's own reloads of dnsmasq are done one at a time by that pass |
| Wi-Fi recovery | if a Wi-Fi core crashes and stays down for about 90 s, the router restarts itself: not in the first 10 minutes after boot, at most three times a day |
| Ad blocker link | links an AdGuard Home on the network: on, off, pause, statistics, recent activity, allow or block a site, block lists, ad blocking off for a single device |
| IoT watch | with an ad blocker linked: the sites each device on a separate network (IoT, guest) looks up, grouped by main name. After a device's first day, a site it never used before raises an alert |
| Speed shaping | switch SQM (cake) on or off and set the download and upload limits |
| Checks | connection test, speed test from the router (download and upload), Wi-Fi channel check, blocked threats (banIP), protection overview, weekly summary, 48 hours of health samples |
| Laptop power | sleep, restart and wake for Mac and Windows laptops. The router holds one SSH key; each laptop accepts it only from the router and only for a fixed script (status, sleep, restart). A laptop is added with one setup command, valid once for 30 minutes, whose download is checked against a checksum. Wake uses Wake-on-LAN and needs the laptop asleep on its charger; a sleep or restart request wakes a sleeping laptop first. The setup also prepares the laptop for this on mains power: wake for network access and no deep power-off sleep on macOS; on Windows, wake on magic packet, no hibernation, and a closed lid no longer sleeps the PC |
| Smart plug power-on | for laptops whose Wi-Fi is off while they sleep: a Tuya plug on the charger, linked with its device ID and local key, is switched off for 45 seconds (a shorter cut is not noticed by a laptop that is off, because its charger holds its charge) to start a laptop that powers on when its charger is connected. Works from shutdown and from hibernation; with a plug linked, "sleep" on Windows means hibernate. The Windows setup can also make the PC hibernate wherever it used to sleep (idle time, lid on battery, sleep button, Start menu), for laptops that cannot be woken from sleep. The plug's power reading is taken every 5 minutes: 24 hours of readings and 60 days of energy per day are kept |
| Maintenance | settings backup download, lights on, off or off at night, restart, firmware version, update check and install (through `be7000-update`, into the second slot) |
| Discovery relay | where an IoT network exists (`br-iot`), smart-home announcements (UDP 6666 and 6667) are repeated onto the main network so phone apps still find their devices |
| Casting across networks | where an IoT network exists, mDNS is repeated both ways so phones on the main network find AirPlay and Chromecast devices, printers and speakers on the IoT side. Discovery only: the firewall still decides what may connect. The IoT zone needs an input rule for UDP 5353 |

### API

Base: `https://<router>/cgi-bin/miwrt`. `GET /health`, `POST /pair/start`, `POST /pair/finish` and the older `POST /pair` need no key; everything else needs `Authorization: Bearer <key>`.

| Method and path | Purpose |
|---|---|
| `GET /v1/status`, `/v1/devices`, `/v1/alerts`, `/v1/meta` | the main screens |
| `POST /v1/devices/<mac>` | `name`, `category`, `icon`, `blocked`, `pause_minutes`, `approve`, `fixed_ip`, `filtering` (`on` or `off`) |
| `POST /v1/devices/<mac>/wake` | Wake-on-LAN |
| `GET /v1/devices/<mac>/power`, `/power/plug`, `/power/usage`; `POST /v1/devices/<mac>/power` (`action`: `sleep`, `hibernate`, `restart`, `shutdown`, `poweron`, `status`), `/power/setup` (`os`: `mac`, `windows`), `/power/plug` (`plug`, `device_id`, `local_key`, or `remove`), `/power/remove` | laptop power |
| `GET /power/s?c=<code>`, `POST /power/register` | used by the laptop's setup script, authorised by the one-time code, no access key |
| `GET`/`POST /v1/groups`, `/v1/schedules` | people and rooms, schedules |
| `POST /v1/settings` | `approve_new`, `watchdog`, `night`, `push` |
| `GET /v1/wifi`, `/v1/wifi/secret?id=`, `/v1/wifi/check`; `POST /v1/wifi/<id>` | Wi-Fi: `ssid`, `key`, `enabled`, `schedule` (`enabled`, `from`, `to`, `days`) |
| `GET`/`POST /v1/guest` | guest Wi-Fi |
| `GET /v1/protection`, `/v1/protection/lists`, `/v1/protection/log`, `/v1/protection/check`; `POST /v1/protection/connect`, `disconnect`, `pause`, `lists`, `rules` | ad blocker link |
| `GET /v1/usage`, `/v1/week`, `/v1/history`, `/v1/threats`, `/v1/overview`, `/v1/diagnose`, `/v1/firmware`, `/v1/speedtests`, `/v1/iotwatch`; `POST /v1/speedtest`, `/v1/firmware/install` | insight, firmware |
| `GET`/`POST /v1/shaping` | speed shaping: `enabled`, `down_kbit`, `up_kbit` |
| `GET /v1/phones`; `POST /v1/phones/revoke` | paired phones |
| `GET /v1/push` (`enabled`, `kinds`, `mode`, `registered`, `this_phone`); `POST /v1/push/register` (`token`, `env`, `key`), `/v1/push/test` | notifications |
| `POST /v1/router/backup` (with the administrator password); `POST /v1/router/leds`, `/v1/router/watchdog`, `/v1/router/reboot` | maintenance |

### Design notes

- The 30 s pass writes only to memory. Flash is written when something changes (a rename, a new device, an alert) and once a day for traffic totals.
- Every value that reaches a shell command is a constant or checked against a strict pattern; request bodies go through files.
- One writer at a time: the background pass and API requests share a file lock.
- If the pause-list file is missing or malformed the firewall ignores it and still starts.
- Notifications: Apple only delivers a push signed with the key of the app's publisher. That key is a secret and is not in this repository or in the images: anything shipped in firmware can be read out by anyone. So there are two ways, and the router picks by itself:
  - **Direct.** `miwrt-ctl apns AuthKey_XXXXXXXXXX.p8 <key id> <team id>` stores a key under `/etc/miwrt/apns/` (root only, kept across sysupgrade, never served by the API). The router then talks to Apple itself and nothing else is involved. This is for whoever publishes the app build the phone runs: the key must belong to that app.
  - **Relay.** A router without a key sends to a relay that holds it: the Cloudflare Worker in [miwrt-relay](miwrt-relay/README.md). The firmware's default relay is `DEFAULT_RELAY` in `hub.uc` (`https://miwrt-relay.iroham.cloud`, run by the app's publisher); `settings.push.relay` overrides it.
- Notification privacy: at registration the phone makes a random 64-byte key and gives it to the router over the pinned HTTPS connection. For each alert and each phone the router encrypts title and text (AES-256-CBC, then HMAC-SHA256 over IV and ciphertext). The notification that travels says only "Your router has an alert"; the app's notification extension checks the seal, decrypts, and shows the real text. A relay therefore sees notification addresses, the alert's kind, and ciphertext.
- Security review of 10 Oct 2026 (in the source after 1.4.7.1, in the next image):
  - Pairing counts wrong passwords per address (5 in 10 minutes) and overall (40), under the file lock; it is only taken over HTTPS and as JSON, which a web page cannot send from a browser on the network.
  - At most 600 devices are remembered. When the list is full the oldest device nobody named makes room. More than ten new devices in an hour raise one alert, not one each.
  - IoT watch remembers at most 300 sites per device and raises at most three alerts per device per pass.
  - Alerts read from the system log only count lines written by hostapd or the kernel, so a device cannot fake one through the name it gives when it asks for an address.
  - Laptop power: the laptop's SSH host key is stored with the laptop at setup and checked on every request, at whatever address the laptop has that day. The account name may not start with a dash. The macOS setup command downloads into a private folder, and when it is the one switching Remote Login on, Remote Login accepts keys only.
  - Notifications: each alert carries its time, id and kind inside the encrypted text; the app shows only the generic line for one stamped more than two hours away from now. A relay must be `https://`; plain `http://` is accepted only for a relay at a private address.
  - The app service's files and `/etc/miwrt` are readable by root only.
  - Firmware updates: the build signs `sha256sums.txt` with the key every image carries (`sha256sums.txt.sig`). The updater takes files only from this repository's releases and refuses a release whose signature does not match the key in its own ROM. 1.4.7.1 and older do not check this yet.
  - The relay Worker counts every notification against the sending home (an IPv6 home counts as one /64), sends nothing when its limiter is unavailable, and checks the size before reading a request.
  - A settings backup (`POST /v1/router/backup`) needs the administrator password as well as the access key: it holds the Wi-Fi passwords and the router's own keys.
  - The relay keeps a fingerprint per phone and accepts that phone's notifications only with the random value the phone gave its router (`sender` at registration, `auth` towards the relay).
  - Fresh installs: the Wi-Fi password is the unit's serial number from its label, without the slash, instead of one password shared by every router. Only a unit whose serial cannot be read falls back to the old one.
  - The Hybrid Failover feed is rebuilt only when started by hand: that build runs the upstream project's script within reach of the feed signing key.
- Android: the same split would apply to Firebase Cloud Messaging (a service-account key instead of the Apple key). There is no Android app yet, so the router has no FCM sender yet.

## The phone app

A native iPhone app (SwiftUI) for this service exists and is in testing; its source is not in this repository. It finds the router by itself, pairs with the administrator password (which stays on the phone), and covers everything in the table above. Before the password is sent, the app checks that the address it found is the router the phone is actually connected through, and warns if it is not. It also has a home-screen and lock-screen widget (internet and Wi-Fi state, devices online, current rates) and Siri shortcuts.

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
