# 闪存槽位和引导程序

[Русский](bootloader.md) · [English](bootloader.en.md)

## 槽位

小米的引导程序保存两份固件。

| 槽位 | 分区 | 大小 |
|------|--------|--------|
| 0 | rootfs, mtd23 | 40 MiB |
| 1 | rootfs_1, mtd24 | 40 MiB |

选择槽位用的标志存在 mtd17（APPSBLENV）里。原厂固件通过 nvram 读写这些标志，OpenWrt 里用 fw_printenv 和 fw_setenv。引导程序本身（0:APPSBL 和 0:APPSBL_1）无论如何都不要动，这是唯一能把板子彻底刷死的地方。

镜像写入非活动槽位，也就是原厂固件当前没有在用的那个。安装脚本会自己判断是哪一个。

1.0 和 1.1 版本的 sysupgrade 总是写 rootfs_1，如果原厂固件刚好装在那里，升级就会把它擦掉。从 1.2 开始，槽位根据内核命令行来判断，命令行由引导程序填写。系统从哪个槽位启动，就更新哪个槽位，另一个槽位不会被碰。如果判断不出槽位，刷写根本不会开始。也可以通过 LuCI 的 系统, 备份/升级 来更新，底层用的是同一个 sysupgrade。

## 引导程序怎么选槽位

这部分没有任何文档，所以我把原厂的 U-Boot 拆开看了（APPSBL 转储里的 cmd_bootmiwifi.c）。

- 引导程序根本不读 `flag_boot_rootfs`，只往里写。
- `flag_ota_reboot=0` 时，从 `flag_last_success` 指定的槽位启动，并且每次启动都无条件把这个槽位的 `flag_try_sys{N}_failed` 计数器加一。计数器大于 5 时，引导程序切到另一个槽位。只有启动起来的系统才能把计数器清零，原厂固件在它的 init 里做这件事。
- `flag_ota_reboot=1` 并且 `flag_boot_success` 不为零时，启动的是另一个槽位而不是 last_success，同时 `flag_boot_success` 被清零。如果这次启动没有被确认，下一次启动就回到 last_success。这是正常的 OTA 流程。

到 1.2.2 为止，安装脚本会把 `flag_last_success` 改到新槽位并清零计数器。这样能用，但回滚要到第七次上电才发生。从 1.2.3 开始，安装脚本走 OTA 流程。last_success 保持指向原厂固件，`flag_ota_reboot=1`，如果 OpenWrt 没起来，下一次上电就回到原厂固件。启动由 be7000-bootconfirm 服务在启动流程最后确认。它把 last_success 改到自己的槽位，清掉 ota_reboot，并把计数器清零。

对还在用 1.0、1.1、1.2、1.2.1 和 1.2.2 的人来说，后果是这样的。计数器每次重启都会增加，到第七次路由器就回到原厂固件。手动把计数器清零，然后马上用 sysupgrade 升级，七次启动的余量做这件事绰绰有余。

```
fw_setenv flag_try_sys1_failed 0 && fw_setenv flag_try_sys2_failed 0
```

## 引导程序里的网络

这部分来自同一份转储（md5 c315ebc92b53795f07b10b0ba3b411e6，我能对比的所有板子上都一样）。引导程序里确实有以太网初始化，包括完整的 UNIPHY 和 QCA8084 配置，但只在四种情况下调用。分别是在 UART 上按键打断了启动，内核加载失败控制权回到引导程序，上电时按住 reset 键（TFTP 恢复），或者开启了内核崩溃后通过网络收集转储。正常启动时引导程序不碰 UNIPHY，所以网络需要的一切都得由内核自己完成。
