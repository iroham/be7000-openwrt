#!/bin/sh
# Hardware report for the Redmi AC2100 test programme. Runs on the router,
# prints plain text to paste into the test log. Reads only; changes nothing.
# Serial numbers and MAC addresses are shortened so the output can be shared.
#
#   sh hw-report.sh > /tmp/report.txt
#
# Needs nothing beyond what the MiWRT image carries.

line() { printf '\n== %s\n' "$*"; }
mask() { sed -E 's/([0-9A-Fa-f]{2}:){3}[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:/xx:xx:xx:xx:xx:/g'; }

line "identity"
ubus call system board 2>/dev/null | mask
cat /etc/miwrt-release 2>/dev/null
grep -E '^DISTRIB_(ID|RELEASE|DESCRIPTION)' /etc/openwrt_release 2>/dev/null
sn="$(fw_printenv -n SN 2>/dev/null | tr -cd 'A-Za-z0-9')"
[ -n "$sn" ] && echo "serial from the bootloader environment: readable (${#sn} characters, starts with $(printf '%s' "$sn" | cut -c1-3))" || echo "serial from the bootloader environment: not readable"

line "uptime, load, memory"
uptime
free
grep -E 'MemTotal|MemAvailable' /proc/meminfo

line "flash"
cat /proc/mtd
ubinfo -a 2>/dev/null | grep -E 'ubi[0-9]|Volume ID|Name|Size|bad' | head -30
df -h / /overlay /tmp 2>/dev/null

line "network"
ip -br link 2>/dev/null | mask
for d in /sys/class/net/wan /sys/class/net/lan1 /sys/class/net/lan2 /sys/class/net/lan3 /sys/class/net/eth0; do
	[ -d "$d" ] && printf '%s: speed %s duplex %s carrier %s\n' "$(basename "$d")" "$(cat "$d/speed" 2>/dev/null)" "$(cat "$d/duplex" 2>/dev/null)" "$(cat "$d/carrier" 2>/dev/null)"
done
ubus call network.interface.wan status 2>/dev/null | grep -E '"(up|proto|device|l3_device|uptime)"' | mask
echo "flow offloading: sw=$(uci -q get firewall.@defaults[0].flow_offloading) hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw) packet_steering=$(uci -q get network.globals.packet_steering)"
nft list flowtables 2>/dev/null | head -5

line "wireless"
for r in radio0 radio1; do
	printf '%s: band=%s channel=%s htmode=%s country=%s disabled=%s\n' "$r" "$(uci -q get wireless.$r.band)" "$(uci -q get wireless.$r.channel)" "$(uci -q get wireless.$r.htmode)" "$(uci -q get wireless.$r.country)" "$(uci -q get wireless.$r.disabled)"
done
iwinfo 2>/dev/null | mask
ubus call network.wireless status 2>/dev/null | grep -E '"(up|pending|disabled|retry_setup_failed|ifname)"'
echo "wpa_group_rekey on 5 GHz: $(uci -q show wireless | grep -c 'wpa_group_rekey=.0.') interface(s) set to 0"

line "app service"
for s in miwrt be7000-update-check umdns nlbwmon uhttpd rpcd; do
	printf '%s: ' "$s"; /etc/init.d/$s running 2>/dev/null && echo running || echo "not running"
done
curl -sk -m 5 https://127.0.0.1/cgi-bin/miwrt/health 2>/dev/null || echo "health endpoint: no answer"
echo
ls -la /etc/miwrt 2>/dev/null | head -20
miwrt-update status 2>/dev/null

line "leds, buttons"
ls /sys/class/leds 2>/dev/null
for l in /sys/class/leds/*; do printf '%s: %s\n' "$(basename "$l")" "$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$l/trigger")"; done 2>/dev/null

line "temperature and thermal"
ls /sys/class/thermal 2>/dev/null || echo "no thermal zones (expected on the MT7621)"

line "kernel messages worth a look"
dmesg 2>/dev/null | grep -iE 'watchdog|mt76.*(error|fail|timeout)|ubi.*(error|bad)|oom|Out of memory|tx queue|NETDEV|flow offload|eip93' | tail -40
logread 2>/dev/null | grep -iE 'miwrt|be7000-update|hostapd.*(fail|error)|netifd.*(fail|error)' | tail -30

line "end of report"
