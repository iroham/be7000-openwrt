# 构建

[Русский](building.md) · [English](building.en.md)

现在已经不再手工构建了。所有事情都由 GitHub Actions 上的一个 workflow `.github/workflows/build.yml` 完成。

- 手动运行（Actions, Build, Run workflow）会按 `config.buildinfo` 构建所有软件包，用 `APK_SIGNING_KEY` secret 里的密钥给索引签名，然后把软件源推到 gh-pages 分支。
- 推送 `v1.2.6` 这样的 tag 会做同样的事，另外还会构建固件，把安装脚本和说明打进压缩包，计算校验和，并创建 Release。Release 的说明文字取自 `docs/release-notes/<tag>.md`。
- 不经过 Actions artifacts，只用 git 和 Release。编译器的结果在两次运行之间用 ccache 缓存。
- 内核模块发布到以内核配置哈希命名的目录 `feed/targets/qualcommbe/ipq95xx/<hash>/packages/`。构建时镜像会把自己的哈希写进 `customfeeds.list`，所以内核配置变了以后，旧镜像仍然能找到匹配的模块。

如果想自己构建，顺序如下，和 `.github/workflows/build.yml` 里的一样。先取 openwrt/openwrt 源码树，检出 patches/port/BASE 里的提交，然后执行 `git am patches/port/*.patch`，这就是 kravasuper 移植版。软件源检出 feeds-pins.txt 里的提交。内核补丁从 patches 放到 target/linux/qualcommbe/patches-6.18，ath12k 补丁从 patches/mac80211-ath12k 放到 package/kernel/mac80211/patches/ath12k，mac80211 补丁从 patches/mac80211-subsys 放到 package/kernel/mac80211/patches/subsys，源码树的改动从 patches/tree 用 patch -p1 打上，说明见 [patches.zh.md](patches.zh.md)。在源码树根目录放一个 version 文件，内容是 r20260929-d958caf，没有它 apk 构建不了 base-files。overlay-files 放到 files，awg-feed 和 luci-theme-nimbus 放在旁边。配置用 config.buildinfo，然后执行 make defconfig 和 make world。最好在 Docker 里用 debian 构建，源码放在 Docker volume 里，不要放在 macOS 的磁盘上，那里的文件系统不区分大小写，会弄丢内核文件。如果改了内核配置，树外模块（mac80211、amneziawg）也要重新构建，否则它们还是给旧内核编的。

```
grep -E "^(kmod-ath11k-ahb|kmod-ath12k|kmod-qcom-ppe|wpad-mbedtls|luci-ssl) " *.manifest
```

镜像可以用 scripts/ubi_extract.py 脚本解开（卷 1 是 squashfs）。

从 `debug-*` tag 出来的调试版本会作为 pre-release 发布，不发布软件源，只构建镜像，不构建软件源用的模块包，所以大约半小时就能完成。

第二个 workflow `.github/workflows/hybrid-failover-feed.yml` 维护一个单独的 hybrid-failover 软件源。它每三个小时查看一次 openwrt-hybrid-failover 的最新 release，如果比软件源里的新，就用项目自己的打包脚本构建 aarch64_cortex-a73 的软件包。索引用同一个密钥签名，放到 `feed/hybrid-failover/aarch64_cortex-a73/`。也可以在 Actions 里手动启动。它从 main 分支运行，因为 GitHub 要求定时任务必须这样。

LuCI 的翻译放在 `i18n`，英文是 `be7000.en.po`，中文是 `be7000.zh-cn.po`，编译好的 `.lmo` 文件和其他固件文件放在一起。`scripts/i18n-check.sh` 会检查我们页面上的每个字符串在两种语言里都有翻译。
