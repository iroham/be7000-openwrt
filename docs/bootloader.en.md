# Flash slots and the bootloader

[Русская версия](bootloader.md)

## Slots

The Xiaomi bootloader keeps two copies of the firmware.

| Slot | Partition | Size |
|------|--------|--------|
| 0 | rootfs, mtd23 | 40 MiB |
| 1 | rootfs_1, mtd24 | 40 MiB |

The slot selection flags live in mtd17 (APPSBLENV). On stock they are read and written through nvram, on OpenWrt through fw_printenv and fw_setenv. Do not touch the bootloader (0:APPSBL and 0:APPSBL_1) under any circumstances, it is the only place where the board can be killed for good.

The image is written to the inactive slot, the one stock is not currently running from. The installer figures out which slot that is by itself.

sysupgrade in versions 1.0 and 1.1 always wrote to rootfs_1, and for those whose stock lived exactly there, the update erased it. Since version 1.2 the slot is determined from the kernel command line, which the bootloader fills in: the slot the system booted from is the one that gets updated, and the other one is never touched. If the slot cannot be determined, flashing does not start at all. You can also update through LuCI, System, Backup / Flash Firmware, it is the same sysupgrade underneath.

## How the bootloader picks a slot

This is not documented anywhere, so I took apart the stock U-Boot (cmd_bootmiwifi.c in the APPSBL dump).

- The bootloader does not read `flag_boot_rootfs` at all, it only writes it back.
- With `flag_ota_reboot=0` the slot from `flag_last_success` is booted, and that slot's `flag_try_sys{N}_failed` counter is incremented on every boot, unconditionally. When the counter is greater than 5, the bootloader switches to the other slot. Only the booted system can reset the counter, stock does this in its init.
- With `flag_ota_reboot=1` and `flag_boot_success` not equal to zero, the other slot is booted, not last_success, and `flag_boot_success` is reset to 0. If that boot was not confirmed, the very next one goes back to last_success. This is the regular OTA path.

Up to 1.2.2 the installer moved `flag_last_success` to the new slot and reset the counters. It worked, but rollback only happened on the seventh power-on. Since 1.2.3 the installer follows the OTA path: last_success stays on stock, `flag_ota_reboot=1`, and if OpenWrt did not come up, the next power-on returns stock. The boot is confirmed by the be7000-bootconfirm service at the very end of startup: it moves last_success to its own slot, clears ota_reboot and resets the counters.

The consequence for everyone on versions 1.0, 1.1, 1.2, 1.2.1 and 1.2.2: the counter grows with every reboot, and on the seventh the router goes to stock. Reset the counters by hand and update through sysupgrade right away, seven boots of margin is more than enough for that.

```
fw_setenv flag_try_sys1_failed 0 && fw_setenv flag_try_sys2_failed 0
```

## Network in the bootloader

This is from the same dump (md5 c315ebc92b53795f07b10b0ba3b411e6, identical on all the boards I could compare). The bootloader does have Ethernet initialization with the full UNIPHY and QCA8084 setup, but it is called only in four cases: boot was interrupted with a key on the UART, the kernel failed to load and control returned to the bootloader, the reset button is held at power-on (TFTP recovery), or network dump collection after a kernel crash is enabled. On a normal boot the bootloader does not touch UNIPHY, so everything the network needs has to be done by the kernel itself.
