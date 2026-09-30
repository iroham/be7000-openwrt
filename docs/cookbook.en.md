# Recipes

[Русский](cookbook.md)

Ready recipes for common tasks. Commands run over SSH on the router (`ssh root@192.168.1.1`), packages come from the build's feed, so the router needs internet. If something goes wrong, post the command output in the 4PDA topic or in issues.

## LTE or 5G USB modem

Most current modems need ModemManager and the QMI, MBIM and NCM drivers.

```
apk update
apk add modemmanager luci-proto-modemmanager kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim kmod-usb-net-cdc-ncm kmod-usb-serial-option
```

Plug the modem in, wait half a minute and check that it shows up:

```
mmcli -L
```

Then in LuCI, Network, Interfaces, Add: protocol ModemManager, the modem device, the carrier's APN. Put it in the wan firewall zone. Huawei modems that work over NCM also want `kmod-usb-net-huawei-cdc-ncm`.

## Internet from a phone over USB

Android. Newer phones share over NCM, older ones over RNDIS, install both drivers:

```
apk update
apk add kmod-usb-net-cdc-ncm kmod-usb-net-rndis
```

iPhone. It needs the ipheth driver and usbmuxd, which talks to the phone:

```
apk update
apk add kmod-usb-net-ipheth usbmuxd
/etc/init.d/usbmuxd enable
/etc/init.d/usbmuxd start
```

On the iPhone confirm "Trust This Computer" and turn on Personal Hotspot.

Plug the phone in and see which interface appeared:

```
dmesg | tail -20
```

Usually `usb0` or an `eth` with a new number. In LuCI, Network, Interfaces, Add: protocol DHCP client, that device, zone wan.

## Docker

Docker images do not fit into the internal flash, a USB disk is needed. Plug it in, format and mount it as described in [storage.en.md](storage.en.md), then:

```
be7000-docker setup
```

The script finds a mounted disk with room and moves the Docker data there. Ready container sets run from Services, Docker: stacks. The script also installs Dockerman, the page for containers, images and networks.

## 5 GHz modes

The 5 GHz mode block at the top of Network, Wireless. The router does not reboot on a mode change, 5 GHz Wi-Fi is down for about half a minute.

- One radio. One network for the whole band, every channel, up to 160 MHz. The highest speed for a single device.
- Two radios, like 5G-1 and 5G-2 on stock. The lower one on channels 36-64, the upper one from 149. The lower one can take 160 MHz in its settings, the upper one up to 80 MHz. Handy with many devices.
- MLO. One Wi-Fi 7 network over both radios. Devices with Wi-Fi 7 and MLO keep a link on two channels at once, the rest join one of them like an ordinary network.

In two-radio and MLO mode each radio gets half of the antennas, so one device is slower than in one-radio mode. Numbers in [benchmarks.en.md](benchmarks.en.md).

The country code trap. With some codes, RU among them, the radio firmware turns Wi-Fi 7 off and the access point runs as Wi-Fi 6. The 5 GHz mode block warns about it, and the button next to the warning switches the code to US. Channel and power rules change with the code.

From the console:

```
be7000-5g-split mode           # the mode now
be7000-5g-split mode split     # two radios
be7000-5g-split mode mlo       # MLO
be7000-5g-split mode single    # one radio
```

## Settings from stock

If the router came from stock with Wi-Fi and internet already set up, on its first boot Beam WRT takes the Wi-Fi names and passwords, the internet connection (PPPoE, DHCP or a static address) and the router address from there. Status, Overview shows what was taken, with an undo button.

To see what stock has, without changing anything:

```
be7000-stock-import preview
```

To take it by hand and to undo:

```
be7000-stock-import apply
be7000-stock-import undo
```

Stock keeps its settings in an encrypted container. The script opens it read-only, from a copy, so stock finds them untouched if the router goes back.

## Slots and going back to stock

The flash has two slots. System, Slots shows what each one holds, which one runs and which one boots by default, and switches to the other one. The firmware that boots makes its own slot the default, so a switch is for good. The page says how to come back from stock before it switches. More about the bootloader in [bootloader.en.md](bootloader.en.md).

## Updating

System, Build update: checks for a new version and installs it in one click, settings are kept. From the console:

```
be7000-update check     # is there a new version
be7000-update apply     # download, verify and install
```

Packages you installed are reinstalled for the new kernel after the update, once the router is online.
