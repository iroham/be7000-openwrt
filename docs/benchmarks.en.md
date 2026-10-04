# Measurements

[Русский](benchmarks.md) · [中文](benchmarks.zh.md)

Numbers you can check. Each one says what it was measured with and how, so anyone can repeat it on their own router and compare.

## Method

Wi-Fi. `iperf3 -s` on the router, the Wi-Fi client runs

```
iperf3 -c 192.168.11.1 -P 4 -t 15
iperf3 -c 192.168.11.1 -P 4 -t 15 -R
```

The first line measures client to router, the second router to client. Four streams, 15 seconds, the received total. Router CPU load comes from the same iperf3 report (`remote_total`). Here the router itself receives and sends the traffic, so this is Wi-Fi speed together with its CPU, not routing.

Memory. `MemTotal` and `MemAvailable` from `/proc/meminfo` 10 minutes after boot, with every service of the build and Wi-Fi on both bands.

The conditions go next to the numbers. That is the channel, the width, the signal at the client and the 5 GHz mode. Without them numbers cannot be compared.

## Results

A 1.4.0 test build (OpenWrt main d958caf, kernel 6.18.52), September 30, 2026. The client is a MacBook with Wi-Fi 7 (802.11be), in the same room as the router.

| 5 GHz mode | Client channel | Signal | Client → router | Router → client | Router CPU |
|---|---|---|---|---|---|
| One radio | 149, 80 MHz, EHT | -51 dBm | 211 Mbit/s | 545 Mbit/s | 8 % / 5 % |
| MLO, 36 at 160 MHz and 149 at 80 MHz | 149, 80 MHz, EHT, one link | -54 dBm | 81 Mbit/s | 441 Mbit/s | 6 % / 4 % |

![5 GHz Wi-Fi speed in one-radio and MLO mode](img/bench-wifi-5g-en.svg)

In two-radio and MLO mode the radio firmware splits the four chains of the QCN9274 in half, two per radio. That is why one client is faster in one-radio mode. Two radios and MLO pay off with many clients on different channels. The MacBook joins the MLO network on one link, not as an MLD, so it cannot show two links adding up.

Memory is 881,336 kB in total, 509,712 kB of it available.

## Hardware offload on a wired connection

The measurement was made by zh8416 on build 1.4.4. The topology is a main router, the BE7000 behind it on its WAN port, and a computer on a LAN cable, with 2.5 Gbit/s ports throughout. iperf3 runs as a server on the WAN side, the client runs `iperf3 -c <address> -P 4 -t 15` and the same with `-R`. Offload was switched off and on under Network, Hardware offload. CPU load is 100 % minus idle over ten samples of `top -b -n 10 -d 1`, averaged, over all cores together.

| | Up, speed | Down, speed | CPU up | CPU down |
|---|---|---|---|---|
| Offload off | 2.26 Gbit/s | 2.24 Gbit/s | 42.7 % | 60.1 % |
| Offload on | 2.28 Gbit/s | 2.25 Gbit/s | 36.5 % | 41.5 % |

With offload on, `/proc/net/nf_conntrack` held 15 to 27 entries marked `HW_OFFLOAD`, with it off none. The speed did not change because a 2.5 Gbit/s port is already at the practical TCP limit of about 2.3 Gbit/s without offload. The gain shows only in CPU load, and more in the down direction.

Two caveats. Almost all the load that remains with offload is softirq, 35 to 39 %, and it would be much lower if the PPE forwarded the whole flow. What exactly stays on the CPU is not clear yet. There were also more retransmissions in the down direction with offload, 8465 and 10646 against 6642 and 6068 without it, about three in a thousand packets, and the speed was not affected. It is one measurement on one router.

## Not measured yet

- Routing and NAT on a wired connection. There is no way to run such a measurement yet.
- A client that joins MLO on two links at once.
- An explanation for the softirq load that remains with offload on, and a second measurement on another router. If you can, send a measurement with the method above, with offload and without.
