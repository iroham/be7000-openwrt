# Plan: MiWRT for the Xiaomi Redmi Router AC2100

Status: Phases 0 and 1 (section 10) are done and merged; the `ac2100 image` workflow built and verified an image (run 41494479657, ImageBuilder 25.12.6, 192 packages). Phase 2 is prepared but needs a router: the signed pre-release path for `ac2100-v*` tags, the public key in the image, the install, update and recovery texts in `docs/instruction/ac2100/`, the test protocol in `redmi-ac2100-hardware-test.md` and `scripts/ac2100/hw-report.sh`. No AC2100 image has been flashed. Written 2 November 2026 against MiWRT 1.5.4.1 (pull request 1), OpenWrt 25.12 and the analysis in jacek4yang/redmi-ac2100-openwrt (MIT, no device flashed there yet).

## 1. Decision in one paragraph

Add the Redmi AC2100 as a second device in this repository without touching the BE7000 build. The AC2100 image is assembled with the official OpenWrt 25.12 ImageBuilder for `ramips/mt7621`, profile `xiaomi_redmi-router-ac2100`, plus a MiWRT overlay that is shared with the BE7000 (the app service, the theme, the update checker, the first-boot defaults). Nothing in the BE7000 workflow, overlay, feeds or release tags changes. The AC2100 gets its own workflow, its own overlay directory, its own release tag prefix and its own small package feed. The phone app learns the router's capabilities from the API instead of assuming a BE7000.

## 2. The two routers side by side

| | BE7000 (today) | Redmi AC2100 (RM2100) |
|---|---|---|
| SoC, arch | Qualcomm IPQ9554, aarch64_cortex-a73, 4 cores | MediaTek MT7621A, mipsel_24kc, 2 cores 4 threads, 880 MHz |
| RAM | 1 GB | 128 MB (about 124 MB usable) |
| Flash | 256 MB NAND, two firmware slots, stock bootloader | 128 MB NAND, 4 MB kernel partition, UBI for rootfs and overlay |
| Wi-Fi | Wi-Fi 7, ath12k and ath11k, MLO, split 5 GHz | 2.4 GHz MT7603 (n, 2x2), 5 GHz MT7615 (ac, 4x4), mt76 driver |
| Ethernet | 2.5 GbE, PPE offload | 1 GbE, 1 WAN + 3 LAN, MT7621 hardware flow offload |
| USB | USB 3 | none |
| OpenWrt base | main d958caf, kernel 6.18, kravasuper port plus Beam WRT patches | upstream supported since 21.02; 25.12 branch, kernel 6.12; main would be 6.18 |
| Install from stock | Beam WRT scripts, slot switch, factory firmware kept | exploit on an old stock version for SSH, then write `kernel1.bin` and `rootfs0.bin` and set the boot flags; stock is not kept |

What this means: almost everything Beam WRT does is BE7000 specific and does not apply. What MiWRT adds on top (the app service, the theme, the defaults, the signed update flow) is portable, with the changes listed in section 5.

## 3. Feature by feature: what carries over

| MiWRT feature | AC2100 | Notes |
|---|---|---|
| App service (hub, devices, alerts, pausing, people and rooms, guest Wi-Fi, schedules, summaries, speed test, WOL, laptop power, Tuya, discovery relay, mDNS reflector) | yes | ucode and shell, no architecture dependence; see section 5 for the few hardware assumptions |
| Pairing, relay, push, signed releases | yes | unchanged protocol; the relay needs no change |
| LuCI theme Nimbus with the MiWRT mark | yes | noarch LuCI package |
| Update check and install from System, Build update and from the app | yes, after generalising the updater | today it is `be7000-update`, picks the first `*-squashfs-sysupgrade.bin` in a release and only accepts tags `v*`; see section 6 |
| Country default GB on first boot | yes | generic uci-defaults |
| 5 GHz group-key renewal off | yes, keep | the failure was seen on ath12k; the setting is harmless on mt76 and keeps behaviour identical across devices |
| Xiaomi board data for the radios | no | ath11k and ath12k only; mt76 reads its EEPROM from the Factory partition, OpenWrt handles it |
| Split 5 GHz, MLO fixes, ath12k recovery patches | no | hardware does not exist |
| Two-slot upgrades, checked slot write, slot storage, factory firmware kept | no | one firmware, standard OpenWrt sysupgrade; the 4 MB kernel partition is the only layout constraint |
| Extroot, USB disk, Docker, modem page | no | no USB port |
| PPE offload page | no | different engine; MT7621 hardware flow offload is a firewall option, on by default in our image |
| sqm-scripts with cake | ship, off by default | cake on MT7621 handles roughly 200 to 300 Mbit/s and turning it on bypasses hardware offload; the app's speed shaping must say so |
| nlbwmon per-device traffic | yes | low memory use |
| banIP | optional package, not in the image | large block lists do not fit comfortably in 128 MB; the app's "blocked threats" card must degrade when banIP is absent (it already checks the service) |
| curl with HTTP/2, umdns, tcpdump-mini | yes | all in the official mipsel_24kc feed |
| Zapret Manager, Zapret, ByeDPI, NetShift, sing-box, AmneziaWG, roamd, hybrid failover, steer | later, if at all | need mipsel_24kc builds of our feeds; phase 3 |
| LED "State" trigger, LED control from the app | yes | the app reads `/sys/class/leds`; the AC2100 has status amber and white and WAN amber and white |

## 4. Repository and build layout: how the BE7000 stays untouched

Rules that make "no effect on current users" checkable rather than hoped for:

1. `overlay-files/`, `build.yml`, `config.buildinfo`, the patches and the feeds keep their names and content. The BE7000 image is built exactly as today.
2. Shared MiWRT code moves to `overlay-common/` only when the BE7000 build is taught to copy `overlay-common/` and then `overlay-files/` on top, and the result is proven identical: the first CI run after that change must produce the same package manifest and the same file list in the image as before. Until then the AC2100 build copies the files it needs from `overlay-files/` by an explicit list.
3. The AC2100 overlay lives in `overlay-ac2100/`. Device-specific first-boot defaults go there, never into the shared part.
4. A second workflow `build-ac2100.yml` uses the official ImageBuilder, no toolchain. It takes about ten minutes. No source build, no kernel patches, so every kernel module comes from the official 25.12 feed and stays installable later.
5. Release tags: BE7000 keeps `v1.5.4.1`; the AC2100 uses `ac2100-v1.0.0`. The BE7000 updater already in the field accepts only tags matching `^v[0-9]`, so AC2100 releases are invisible to it. That is the safety net for routers that never update.
6. Version identity: `DISTRIB_DESCRIPTION` "MiWRT 1.0.0 r... (Redmi AC2100)", `DISTRIB_RELEASE` left as the OpenWrt release so third-party scripts work, the same rule Beam WRT 1.5.1 introduced.
7. Feeds: the AC2100 image keeps the official OpenWrt 25.12 distfeeds for `mipsel_24kc` (they match, unlike the BE7000 where the official target is a53) plus one MiWRT feed `feed/mipsel_24kc/miwrt/` for our noarch packages (theme, updater, app service packaged as `miwrt-app`). The signing key is the one already in use.
8. Documentation: README gets a "Supported routers" section; AC2100 install, update and recovery go to `docs/instruction/ac2100/`.

## 5. Porting the app service: concrete changes

The service was checked file by file. It has exactly one BE7000 dependency and a few hardware assumptions that degrade badly rather than fail:

| Place | Today | Change |
|---|---|---|
| `extras.uc` firmware() and firmware_install() | calls `be7000-update` | call `miwrt-update`, a renamed and device-aware updater (section 6); keep `be7000-update` as a symlink on the BE7000 so nothing else breaks |
| `hub.uc` collect(): `s.rproc` from `/sys/class/remoteproc` | drives "Wi-Fi core crashed" alerts and the reboot watchdog | on the AC2100 the directory does not exist, so `rproc` is empty and the watchdog never fires. That is correct, but the alerts should instead watch `network.wireless` status for a radio that is down while enabled. Add that check for both devices |
| `hub.uc` temperature from `/sys/class/thermal` | MT7621 has no thermal zone, so `temperature: 0` | report `null` and have the app hide the tile |
| `hub.uc` status | `model` and `firmware` from `system board` | add a `capabilities` object: `slots`, `split5g`, `usb`, `temperature`, `sqm`, `banip`, `wan_speed_mbit`. The app shows only what the router has |
| `extras.uc` speed shaping | assumes the WAN can do whatever is asked | cap the offered range by `wan_speed_mbit` and warn that shaping disables hardware offload on the AC2100 |
| `extras.uc` threats() | returns `available: false` without banIP | already fine; the app must hide the card when `available` is false |
| LED control | enumerates `/sys/class/leds` | fine; names differ, nothing to do |
| Wi-Fi list | bands from `wifi-device.band` and from frequency | fine; the AC2100 has one radio per band, like the BE7000 in single-radio mode |
| `miwrt-wol`, `power.uc`, `miwrt-tuya`, relay, mDNS reflector | shell and ucode over sockets | fine |
| Memory | hubd keeps device history in RAM and `/etc/miwrt` | measure on the device; cap history length when `MemTotal` is under 256 MB |
| `oui.txt` (870 KB) | shipped in the image | fine for flash; it is read, not loaded |

Packages the service needs, all present in the official 25.12 mipsel_24kc feed: `uhttpd` with TLS (`luci-ssl`), `rpcd`, `ucode` with `ucode-mod-lua`, `ucode-mod-uci`, `ucode-mod-ubus`, `ucode-mod-fs`, `luci-lib-nixio`, `umdns`, `nlbwmon`, `curl`, `openssl-util`, `ca-bundle`, `libustream-mbedtls`, `uclient-fetch`, `etherwake` or the built-in WOL sender, `dropbear` for the laptop power keys.

## 6. The updater

`be7000-update` becomes `miwrt-update` with three changes, and the BE7000 keeps a compatibility symlink:

1. It knows its own image name from `/etc/be7000-release` (to be renamed `/etc/miwrt-release`, with the old path kept as a symlink), written by CI: `DEVICE=openwrt-ramips-mt7621-xiaomi_redmi-router-ac2100` or the BE7000 name. It picks the release asset whose name starts with that device name, never "the first sysupgrade.bin".
2. It knows its tag prefix (`v` or `ac2100-v`) and ignores releases with another prefix.
3. The Pages mirror path becomes `firmware/<tag>/`, which already differs per tag, so nothing changes there.
4. A release file line `PRERELEASE_OK=1` lets a router in the test programme take pre-releases; the AC2100 image carries it until the hardware phase is through, the BE7000 image does not.

Rollout order matters: ship the device-aware updater to BE7000 users in a regular `v` release first, before the first AC2100 release exists. Even if an AC2100 asset ever landed in a `v` release by mistake, routers with the new updater would skip it, and routers with the old one are protected by the tag prefix.

## 7. Image composition for the AC2100

ImageBuilder profile `xiaomi_redmi-router-ac2100`, 25.12.x pinned to the exact release and its `sha256sums`, as the reference repository does.

- Base: the profile defaults (`kmod-mt7603`, `kmod-mt7615-firmware`, `wpad-basic-mbedtls`, `uboot-envtools`), `luci`, `luci-ssl`, `luci-theme-nimbus`, `luci-i18n-base-ru` and `zh-cn` as on the BE7000.
- MiWRT: `miwrt-app` (the service, packaged), `miwrt-update` with its LuCI page, the credits page, the first-boot defaults (country GB, group rekey, hostname `MiWRT`, the firewall include for paused devices).
- Network and tools: `curl`, `umdns`, `nlbwmon` and its page, `sqm-scripts` and its page (installed, off), `tcpdump-mini`, `iperf3` only in debug builds.
- Not in the image: banIP (optional from the official feed), Docker, the Beam WRT add-ons, anything USB.
- First-boot defaults specific to the device (`overlay-ac2100`): software and hardware flow offload on, packet steering off (the reference repository's reasoning: an open MT7621 TX-queue watchdog issue), no regulatory change beyond the GB default.
- Budget: the official 25.12 image with LuCI is about 8 MB squashfs; MiWRT adds under 2 MB. The 4 MB kernel limit is the upstream kernel's problem and the 25.12 image fits. RAM after boot with hubd, uhttpd, nlbwmon and umdns is expected around 60 MB used; this is the first thing to measure.

## 8. What the phone app has to change

The app's source is not in this repository, so this is the API contract it has to follow:

- Read `model` and `capabilities` from `/v1/status` and hide: slots, split 5 GHz, temperature when `null`, blocked threats when banIP is absent, speed shaping above `wan_speed_mbit`.
- Firmware card: show the description string as is ("MiWRT 1.0.0 (Redmi AC2100)"); the update flow is unchanged.
- Pairing and discovery: unchanged, the service announces itself the same way over mDNS.
- Copy: "Wi-Fi core" alerts become "radio" alerts on both devices.
- Testing: one AC2100 and one BE7000 paired to the same phone at the same time, since people and rooms are per router.

## 9. Installation and recovery documentation

This needs verification against the OpenWrt wiki before anything is published; the wiki host is not reachable from this session, so the following is from memory and marked as such:

- Stock versions up to 2.0.23 can be opened for SSH through a known web exploit; newer stock needs a downgrade first. The install writes `kernel1.bin` to the `kernel1` partition and `rootfs0.bin` to `rootfs0`, then sets the boot flags (`flag_boot_rootfs`, `flag_last_success`, `flag_boot_success`, `flag_try_sys1_failed`, `flag_try_sys2_failed`) so that U-Boot starts the OpenWrt pair. Stock is not kept; going back means a stock image over TFTP or Breed.
- The reference repository has a full stock NAND dump analysis (`docs/stock-flash-layout.md`) and the bootloader flag names, but has never flashed a device. Treat its procedures as untested.
- Recovery: MT7621 U-Boot TFTP recovery and the Breed bootloader are the usual options; which one we recommend is decided after the first unit is flashed.
- Warning that must be on every page: the Xiaomi Mi Router AC2100 is a different device with a different layout. The CI must refuse to publish any `mi-router-ac2100` artifact, as the reference repository does.

## 10. Phases and gates

Phase 0, BE7000 safety (one `v` release, no AC2100 yet)
- Device-aware `miwrt-update` with the `be7000-update` symlink; `capabilities` in `/v1/status`; radio-down alert from `network.wireless`; `temperature: null` when absent.
- Gate: BE7000 image manifest unchanged apart from the updater package; update from 1.5.4.1 through the page and the app works.

Phase 1, AC2100 image builds (no release)
- `build-ac2100.yml` with the ImageBuilder, `overlay-ac2100/`, explicit copy list from `overlay-files/`, `verify-images` style checks (device identity, size ceilings, checksums).
- Gate: image builds in CI, the manifest is reviewed, the BE7000 workflow is byte-identical to before.

Phase 2, first hardware
- One Redmi AC2100 test unit. RAM boot through initramfs first if U-Boot allows, then flash. Measure RAM, throughput with and without offload, Wi-Fi on both bands, app pairing, every app card, LED control, sysupgrade keeping settings, factory reset.
- Gate: a week of soak without watchdog resets; `ac2100-v1.0.0` tagged as a pre-release.

Phase 3, parity and feeds
- `feed/mipsel_24kc/miwrt/`; decide which Beam WRT add-ons are worth building for mipsel (AmneziaWG and the blocking tools are the likely asks); documentation in three languages.

Phase 4, shared overlay
- Move the app service and theme to `overlay-common/` with the identity proof from section 4, rule 2.

## 11. Risks and how the plan handles them

| Risk | Handling |
|---|---|
| 128 MB RAM | no banIP in the image, history caps in hubd, measurement before release |
| MT7621 known issues (TX-queue watchdog, hardware NAT degrading over uptime, mt7615 slow clients) | packet steering off, soak test, the app's radio-down alert, document the limits |
| Wrong image on the wrong router | tag prefix plus device-name filter in the updater, CI identity check, the Mi Router AC2100 guard |
| Stock exploit availability | documented stock version requirement; nothing we can change |
| Kernel partition of 4 MB | ImageBuilder on a release branch that already fits; no kernel patches of our own |
| Scope creep into the BE7000 tree | separate overlay, separate workflow, identity proof before any shared move |

## 12. Effort

Phase 0 is a day of work plus a BE7000 release. Phase 1 is one or two days. Phase 2 depends on a device and is about two weeks of testing. Phase 3 is open ended and should be driven by what AC2100 users actually ask for.
