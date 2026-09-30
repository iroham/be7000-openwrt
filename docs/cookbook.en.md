# Recipes

[Русский](cookbook.md)

Ready recipes for common tasks. Commands run over SSH on the router (`ssh root@192.168.1.1`). Packages come from the build's feed, so the router needs internet. If something does not work, post the command output in the 4PDA topic or in issues.

## LTE or 5G USB modem

Most current modems need ModemManager and the QMI, MBIM and NCM drivers.

```
apk update
apk add modemmanager luci-proto-modemmanager kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-net-cdc-ncm kmod-usb-serial-option
```

Plug the modem in, wait half a minute and check that the system sees it.

```
mmcli -L
```

Then in LuCI open Network, Interfaces and press "Add". Pick the ModemManager protocol and the modem device, and enter the carrier's APN. Put it in the wan firewall zone. Huawei modems that work over NCM also need `kmod-usb-net-huawei-cdc-ncm`.

## Internet from a phone over USB

Android. Newer phones share over NCM, older ones over RNDIS, so install both drivers.

```
apk update
apk add kmod-usb-net-cdc-ncm kmod-usb-net-rndis
```

iPhone. It needs the ipheth driver and the usbmuxd service, which talks to the phone.

```
apk update
apk add kmod-usb-net-ipheth usbmuxd
/etc/init.d/usbmuxd enable
/etc/init.d/usbmuxd start
```

On the iPhone confirm "Trust This Computer" and turn on Personal Hotspot.

Plug the phone in and see which interface appeared.

```
dmesg | tail -20
```

It is usually `usb0` or an `eth` with a new number. In LuCI open Network, Interfaces and press "Add". Pick the DHCP client protocol, that device and the wan zone.

## Docker

Docker images do not fit into the internal flash, a USB disk is needed. Plug it in, format and mount it as described in [storage.en.md](storage.en.md). Then run the command below.

```
be7000-docker setup
```

The script finds a mounted disk with free space and moves the Docker data there. It also installs Dockerman, the page for containers, images and networks. Ready container sets run from Services, "Docker: stacks".

## 5 GHz modes

The mode is chosen in the "5 GHz mode" block at the top of Network, Wireless. The router does not reboot on a mode change, 5 GHz Wi-Fi is down for about half a minute.

- One radio. One network for the whole band, every channel, up to 160 MHz. The highest speed for a single device.
- Two radios, like 5G-1 and 5G-2 on stock. The lower one runs on channels 36-64, the upper one from 149. The lower one can take 160 MHz in its settings, the upper one up to 80 MHz. Handy with many devices.
- MLO. One Wi-Fi 7 network over both radios. Devices with Wi-Fi 7 and MLO keep a link on two channels at once, the rest join one of them like an ordinary network.

In the two-radio and MLO modes each radio gets half of the antennas. So one device is slower than in one-radio mode. The numbers are in [benchmarks.en.md](benchmarks.en.md).

With some country codes, RU among them, the radio firmware turns Wi-Fi 7 off and the access point runs as Wi-Fi 6. The "5 GHz mode" block warns about it, and the button next to it switches the code to US. Channel and power rules change with the code.

From the console the mode changes like this.

```
be7000-5g-split mode           # the mode now
be7000-5g-split mode split     # two radios
be7000-5g-split mode mlo       # MLO
be7000-5g-split mode single    # one radio
```

## Settings from stock

If the router came from stock with Wi-Fi and internet already set up, on its first boot Beam WRT takes the Wi-Fi names and passwords, the internet connection (PPPoE, DHCP or a static address) and the router address from there. Status, Overview shows what was taken, with an undo button.

To see what stock has without changing anything, run this.

```
be7000-stock-import preview
```

To take the settings by hand and to undo it, run these.

```
be7000-stock-import apply
be7000-stock-import undo
```

Stock keeps its settings in an encrypted container. The script opens it read-only and from a copy, so stock finds them untouched if the router goes back.

## Slots and going back to stock

The flash has two slots. System, Slots shows what each one holds, which one runs and which one boots by default, and switches to the other one. The firmware that boots makes its own slot the default, so a switch is for good. Before the switch the page tells how to come back from stock. More about the bootloader in [bootloader.en.md](bootloader.en.md).

## Hardware offload

Offload is turned on at Network, Hardware offload. The PPE network engine can take over NAT and routing, and the LAN port bridge too. The feature is experimental and off by default. The page explains what is offloaded and what it does not mix with, for example SQM.

From the console it is turned on like this.

```
/usr/libexec/be7000-ppe status
/usr/libexec/be7000-ppe nat on        # at once
/usr/libexec/be7000-ppe bridge on     # after a reboot
```

This command shows how many connections go through the PPE now.

```
grep -c HW_OFFLOAD /proc/net/nf_conntrack
```

## Updating

System, Build update checks for a new version and installs it in one click. Settings are kept. From the console the same is done like this.

```
be7000-update check     # is there a new version
be7000-update apply     # download, verify and install
```

Packages you installed are installed again for the new kernel after the update, once the router is online. If you update to 1.4.0 from 1.x, first read the section on it at the top of docs/instruction/2-update-en.txt. The file is in the release archive too.
