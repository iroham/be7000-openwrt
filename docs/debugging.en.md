# How to find the cause without UART

[Русская версия](debugging.md)

The method is useful beyond this case.

- The image is written to the inactive slot from stock, so the stock boot remains as a fallback.
- A service is added to the image that saves dmesg and the process list to flash every second, into a separate folder for each boot. This matters: my first conclusions were wrong precisely because on power cycles the new boot overwrote the data of the previous one, and I was mistaking the moments of power loss for hangs.
- From stock, the slot's rootfs_data volume is attached (ubiattach and cat from /dev/ubiN_M), and the file is unpacked on a computer with ubireader, because the stock kernel cannot mount UBIFS with zstd compression.
- Once the system starts reaching the network, streaming /dev/kmsg over SSH shows kernel panics in real time. Driver modules are tested without flashing: the ko is sent over SSH and loaded with insmod.

Public images since 1.2.4 have all of this built in. The boot log is written to the crash_syslog partition (mtd27): dmesg at the start of boot, then every 15 seconds for four minutes, and at the end together with interface addresses, the network config and the tail of the system log. Kernel panics go through mtdoops to the crash partition (mtd26). To read it from stock:

```
dd if=/dev/mtd27 bs=64k 2>/dev/null | strings
dd if=/dev/mtd26 bs=64k 2>/dev/null | strings
```

## Mistakes I made myself

Twice I wrote that Wi-Fi 7 did not work, and both times I was wrong. First I mistook a side effect of my own experiments for a driver limitation, then I decided it was about MLO at the kernel level. The reason was more mundane: the access point interface had its own disabled setting, separate from the setting of the radio itself, and in a couple of runs it was left on by oversight.
