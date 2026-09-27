# Building

[Русская версия](building.md)

Nothing is built by hand anymore. Everything is done by a single workflow in `.github/workflows/build.yml` on GitHub Actions.

- A manual run (Actions, Build, Run workflow) builds all packages from `config.buildinfo`, signs the indexes with the key from the `APK_SIGNING_KEY` secret and pushes the feed to the gh-pages branch.
- Pushing a tag like `v1.2.6` does the same and additionally builds the firmware, puts the installer with the instructions into the archive, computes checksums and creates a Release. The release text is taken from `docs/release-notes/<tag>.md`.
- Nothing goes through Actions artifacts, only git and Release. The compiler is cached with ccache between runs.
- Kernel modules are published to a directory named after the kernel config hash, `feed/targets/qualcommbe/ipq95xx/<hash>/packages/`. During the build the image writes its hash into `customfeeds.list`, so old images keep finding matching modules when the kernel config changes.

If you want to build it yourself, the order is as follows. The kravasuper/openwrt tree at commit 790d036a and feeds at the date from feeds-pins.txt. The patches from patches go into target/linux/qualcommbe/patches-6.18 and the changes from patches/tree on top of the tree, described in [patches.en.md](patches.en.md). In the board DTS, two gpio-hogs for TLMM6 (output low) and TLMM7 (output high), they are needed for proper reception on 5 GHz. kmod-ath11k-ahb in the device profile. The awg-feed feed for AmneziaWG. A version file in the tree root containing r20260623-790d036a, without it apk will not build base-files. overlay-files into files. In the config: xiaomi_be7000, wpad-mbedtls instead of wpad-basic, luci-ssl. After make defconfig, check with grep that the required drivers are still enabled, then make world. It is better to build in Docker on debian and keep the sources in a Docker volume rather than on the macOS disk, where the case-insensitive filesystem loses kernel files.

```
grep -E "^(kmod-ath11k-ahb|kmod-ath12k|kmod-qcom-ppe|wpad-mbedtls|luci-ssl) " *.manifest
```

Images can be unpacked with the scripts/ubi_extract.py script (volume 1 is squashfs).

Debug builds from a `debug-*` tag come out as a pre-release, do not publish the feed and build only the image, without the module packages for the feed, so they take about half an hour.
