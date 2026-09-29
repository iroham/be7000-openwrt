# Patches

[Русская версия](patches.md)

Everything added to the kravasuper port (branch xiaomi_be7000, commit 790d036a). The kernel patches are in [patches](../patches) and are copied into target/linux/qualcommbe/patches-6.18, the changes to the OpenWrt tree itself are in [patches/tree](../patches/tree).

## Why the first patches were needed

The image from the port would not start on my board. The LED blinks white rapidly, there is no network and no Wi-Fi, and after seven power cycles the bootloader goes back to stock. In the port's discussion thread I am not the only one describing this, and it usually gets blamed on board revisions. The UART on the board is 1.8 V and I had no adapter for it, so I looked for the cause in logs that the firmware itself writes to flash. How that was done is in [debugging.en.md](debugging.en.md).

It turned out that startup is broken by three bugs that feed into each other.

1. **The QCA8084 PHY driver**, right after configuration, waits 100 ms for the BaseR link and returns an error if it fails. But the link depends on a signal sent by the SoC, and the SoC only starts sending it once the port is opened. If the bootloader managed to configure the SerDes, the check passes. On mine it did not, the log had `BaseR link failed!` and `PPE port 1 failed to connect phylink`. Patch 0901 turns the error into a warning.
2. **qcom-ppe**, after that error, tears itself down and calls `napi_disable()` on a NAPI that is already disabled. Such a call never returns. `insmod` hangs, and since modules are loaded by `S10boot`, nothing after that starts at all: no network, no SSH, no Wi-Fi. Patch 0900.
3. **In the same place, in the port cleanup**, once the hang is removed, the index `i` goes negative and the code reads memory before the start of the array. The result is an oops. Patch 0902.

The last two patches fix real driver bugs and do not depend on the board, they are worth sending upstream. The first one is a workaround, the proper fix would be to configure the SoC's SerDes before attaching the PHY.

## Kernel patches

| Patch | What it does |
|------|-----------|
| 0900 | qcom-ppe: do not disable NAPI a second time when tearing down the rings, otherwise insmod hangs forever holding RTNL |
| 0901 | QCA8084: missing BaseR when attaching the PHY is no longer an error but a warning |
| 0902 | qcom-ppe: the index does not go negative when rolling back the port setup |
| 0903 | QCA8084: if BaseR did not lock when attaching, redo the XPCS setup on the first link up |
| 0904 | qcom-ppe: EDMA receive buffers are mapped and unmapped with the same DMA direction (from OpenWrt main, 0362) |

## OpenWrt tree changes

| Patch | What it does |
|------|-----------|
| 001 | BE7000 DTS: switching of the 5 GHz RF path (TLMM6 and TLMM7) as on stock, without it 5 GHz reception is weak; kernel parameters for mtdoops and the settings volume |
| 002 | device profile: kmod-ath11k-ahb, without it the built-in 2.4 GHz radio is left without a driver |
| 003 | sysupgrade writes to the slot it booted from |
| 004 | mtdoops in the kernel config |
| 005 | BE7000 DTS: the kernel does not vote the l2 regulator over RPM, same as stock. With that request some boards had no reception on the UNIPHY0 lane from the QCA8084, i.e. no Ethernet at all. USB gets a fixed 1.8 V supply |

## Ethernet reception on some boards

Before 1.3.0, on some boards Ethernet reception did not work after installation: there was a link, the MAC did not receive a single frame, Wi-Fi worked. The cause was power: the l2 regulator in the DTS came from the Qualcomm reference board, and the kernel's RPM request for it silenced the SoC receiver on the 10G-QXGMII lane to the QCA8084, while every lane register and clock matched stock. Found on zerc00l's board, which he gave us for remote testing. The fix is patch 005. The history of the search is in [issue #1](https://github.com/timofey-maykov/be7000-openwrt/issues/1) and in the 4PDA thread.
