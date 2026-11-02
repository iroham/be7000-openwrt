# Redmi AC2100: hardware test protocol (Phase 2)

What has to be true before `ac2100-v1.0.0` leaves pre-release. One router, one tester, one log. Every step records the command, the output and the date. Nothing here has been run yet.

## 0. Before the router

- Compare `docs/instruction/ac2100/1-install-en.txt` step 3 (boot flags, partitions) with the OpenWrt wiki page for the Redmi Router AC2100. Correct the text first, then flash.
- Confirm the model on the label: RM2100. Photograph the label (serial, MAC).
- Have a recovery path ready and tried in your head: serial console cable, or Breed, or the TFTP procedure from the wiki.
- Take a full stock dump if you can (the reference repository's `inspect-stock` method), keep it off the router.

## 1. RAM boot (if the bootloader allows it)

OpenWrt publishes an initramfs image for this device (`openwrt-25.12.6-ramips-mt7621-xiaomi_redmi-router-ac2100-initramfs-kernel.bin`). Booting it from the bootloader over TFTP runs plain OpenWrt without touching the flash: a cheap way to confirm the kernel, the switch and both radios work on this unit. Skip if the bootloader cannot do it; note that.

## 2. Flash and first boot

| Check | Pass when |
|---|---|
| First boot time | LAN answers within 3 minutes |
| `hw-report.sh` identity | `MODEL=Redmi AC2100`, description "MiWRT 1.0.0 ... (Redmi AC2100, OpenWrt 25.12.6)", serial readable |
| Memory after boot, idle 10 minutes | `MemAvailable` above 50 MB |
| Flash | `ubi0` has `rootfs` and `rootfs_data`; `/overlay` mounted; no bad-block growth between reports |
| Wi-Fi defaults | both bands up as `MiWRT`, password is the serial, country GB on both radios, `wpa_group_rekey=0` on the 5 GHz interface; the marker `/etc/.miwrt_wifi_defaults` exists |
| Services | `miwrt`, `be7000-update-check`, `umdns`, `uhttpd`, `rpcd` running; `/cgi-bin/miwrt/health` answers |
| LuCI | Nimbus theme, System, Build update page opens, Overview shows the MiWRT version, Russian and Chinese translations load |

## 3. Network

| Check | Pass when |
|---|---|
| WAN DHCP and PPPoE | both connect; `wan_speed_mbit` in `/v1/status` is 1000 on a gigabit link, `null` on PPPoE |
| Routing throughput, software offload on, hardware off (the default) | wired LAN to WAN iperf3, 3 runs, median noted; expect 500 to 900 Mbit/s |
| Same with hardware offload on | median noted; the app's speed limit is then expected not to apply to offloaded flows, confirm and note |
| SQM | cake at 100 Mbit/s each way holds the limit within 10 percent; CPU load noted |
| Per-device accounting | `nlbw -c json` counts a known download |
| Link flap | unplug and replug WAN five times; LAN stays reachable, `softirq` load returns to idle |

## 4. Wi-Fi

| Check | Pass when |
|---|---|
| 2.4 GHz | a phone connects, 20 Mbit/s or more at 5 m |
| 5 GHz, 80 MHz | a laptop connects, 200 Mbit/s or more at 5 m; note the channel |
| DFS channel | set channel 100; the radio comes up after the CAC wait; the app shows the radar alert if one fires |
| Radio-down alert | `wifi down radio1` for two minutes raises "Wi-Fi radio is down" in the app, `wifi up` raises "back" |
| Clients that are slow on mt7615 | record any device below 10 Mbit/s with its model (known upstream issue) |

## 5. The app

| Check | Pass when |
|---|---|
| Discovery and pairing | the phone finds the router by mDNS and pairs with the administrator password |
| `capabilities` | `slots:false`, `split5g:false`, `usb:false`, `temperature:false`, `wifi_cores:false`, `sqm:true`, `banip:false` |
| Devices, pause, approve, people and rooms, guest Wi-Fi with schedule | each works once |
| Speed test, Wi-Fi check, summaries | each runs once; memory after a speed test noted |
| WOL and laptop power | one wired PC wakes; one laptop sleeps and wakes |
| Push and relay | one alert reaches the phone through the relay |
| Threats card | hidden (banIP absent); after `apk add banip` with a small list it appears |

## 6. Update and reset

| Check | Pass when |
|---|---|
| `miwrt-update check` | finds the pre-release (PRERELEASE_OK), reports `device` and `tag_prefix` |
| `miwrt-update apply` from `ac2100-v1.0.0` to a later pre-release | downloads from the Pages mirror, verifies the signature, upgrades, settings and `/etc/miwrt` kept, Wi-Fi not reset |
| sysupgrade by hand | same result |
| Factory reset by button and by `firstboot` | settings wiped, Wi-Fi defaults applied again on the next boot |
| Power cut during an update | the router comes back with the old or the new system; note which, and whether recovery was needed |

## 7. Soak

Seven days of normal use with `hw-report.sh` taken daily. Pass when no "NETDEV WATCHDOG" in `dmesg`, no unplanned reboot, `MemAvailable` not trending down, Wi-Fi clients not dropped, the app reachable every day.

## 8. Decision

All of sections 2 to 7 passed, or every failure has an issue with a cause: `ac2100-v1.0.0` becomes a release, the install text loses its TESTING banner, and Phase 3 starts.
