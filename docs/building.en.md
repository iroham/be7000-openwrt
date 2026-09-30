# Building

[Русская версия](building.md)

Nothing is built by hand anymore. Everything is done by a single workflow in `.github/workflows/build.yml` on GitHub Actions.

- A manual run (Actions, Build, Run workflow) builds all packages from `config.buildinfo`, signs the indexes with the key from the `APK_SIGNING_KEY` secret and pushes the feed to the gh-pages branch.
- Pushing a tag like `v1.2.6` does the same and additionally builds the firmware, puts the installer with the instructions into the archive, computes checksums and creates a Release. The release text is taken from `docs/release-notes/<tag>.md`.
- Nothing goes through Actions artifacts, only git and Release. The compiler is cached with ccache between runs.
- Kernel modules are published to a directory named after the kernel config hash, `feed/targets/qualcommbe/ipq95xx/<hash>/packages/`. During the build the image writes its hash into `customfeeds.list`, so old images keep finding matching modules when the kernel config changes.

If you want to build it yourself, the order is as follows, and it is the same as in `.github/workflows/build.yml`. The openwrt/openwrt tree at the commit from patches/port/BASE, then `git am patches/port/*.patch`, which is the kravasuper port. Feeds at the commits from feeds-pins.txt. Kernel patches from patches into target/linux/qualcommbe/patches-6.18, ath12k patches from patches/mac80211-ath12k into package/kernel/mac80211/patches/ath12k, mac80211 patches from patches/mac80211-subsys into package/kernel/mac80211/patches/subsys, tree changes from patches/tree with patch -p1, described in [patches.en.md](patches.en.md). A version file in the tree root containing r20260929-d958caf, without it apk will not build base-files. overlay-files into files, awg-feed and luci-theme-nimbus next to it. The config from config.buildinfo, then make defconfig and make world. It is better to build in Docker on debian and keep the sources in a Docker volume rather than on the macOS disk, where the case-insensitive filesystem loses kernel files. If you changed the kernel config, rebuild the out-of-tree modules too (mac80211, amneziawg), otherwise they stay built for the old kernel.

```
grep -E "^(kmod-ath11k-ahb|kmod-ath12k|kmod-qcom-ppe|wpad-mbedtls|luci-ssl) " *.manifest
```

Images can be unpacked with the scripts/ubi_extract.py script (volume 1 is squashfs).

Debug builds from a `debug-*` tag come out as a pre-release, do not publish the feed and build only the image, without the module packages for the feed, so they take about half an hour.
