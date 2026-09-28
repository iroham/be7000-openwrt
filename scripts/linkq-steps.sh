#!/bin/sh
# Step-by-step check of the lane from the QCA8084 to the SoC on a debug
# image (uniphy21 and newer). Each step changes one thing the way the stock
# firmware does it and measures the lane with linkq.sh right after:
#   1 as booted, 2 UNIPHY2 down, 3 UNIPHY2 up again, 4 CPU governor at
#   performance (restored afterwards), 5 SoC XPCS EEE as on stock,
#   6 SoC UNIPHY bring-up again in the vendor (SSDK) order, 7 the same in our
#   order, 8 chip SerDes mode set again without analog reset/calibration,
#   9 the same with it, 10 chip switch core clock off as on stock,
#   11 chip SerDes0 clock off as on stock, 12 chip memory control and
#   sec_ctrl clocks as on stock.
# Nothing is written to flash; a reboot undoes everything. Runs in the
# background, so a dropped SSH session does not stop it.
#
# usage:  sh linkq-steps.sh
# result: /tmp/linkq-steps.txt (summary), /tmp/linkq-steps.tar.gz (everything)

PCS=${PCS:-/sys/kernel/debug/ipq_pcs0_ctl}
PHY=${PHY:-/sys/kernel/debug/qca8084_ctl}
IDLE=${IDLE:-/sys/kernel/debug/ipq_pcs_idle_ctl}
CPUFREQ=${CPUFREQ:-/sys/devices/system/cpu/cpufreq}
LQ=${LQ:-/tmp/linkq.sh}
SUM=${SUM:-/tmp/linkq-steps.txt}
DIR=${DIR:-/tmp/linkq-steps}
URL=https://raw.githubusercontent.com/timofey-maykov/be7000-openwrt/main/scripts/linkq.sh

[ -w "$PCS" ] && [ -w "$PHY" ] || { echo "no $PCS / $PHY: this needs a debug-* image"; exit 1; }
[ -w "$IDLE" ] || { echo "$IDLE not found: this needs uniphy21 or newer"; exit 1; }
[ -s "$LQ" ] || wget -q -O "$LQ" "$URL" || { echo "cannot download linkq.sh"; exit 1; }

if [ -z "$LQST_BG" ]; then
	cp "$0" /tmp/.linkq-steps.run.sh
	if LQST_BG=1 start-stop-daemon -S -b -x /bin/sh -- /tmp/.linkq-steps.run.sh 2>/dev/null; then
		:
	else
		LQST_BG=1 setsid sh /tmp/.linkq-steps.run.sh >/dev/null 2>&1 < /dev/null &
	fi
	echo "started in the background, takes about four minutes and keeps running if this session drops"
	echo "done when $SUM ends with the line 'done'; then send /tmp/linkq-steps.tar.gz"
	exit 0
fi

rm -rf "$DIR"
mkdir -p "$DIR"
: > "$SUM"
n=0

say() { echo "$*" >> "$SUM"; }

# measure <what>: one linkq.sh run after a step, totals into the summary
measure() {
	n=$((n + 1))
	f="$DIR/$(printf %02d $n).txt"
	OUT="$f" BATCHES=5 N=60 sh "$LQ" > /dev/null 2>&1
	say "$n $1: $(grep '^total:' "$f" | sed 's/^total: //')"
}

# chip 32-bit register read (value from the kernel log)
swr() {
	echo "sw r $1" > "$PHY" 2>/dev/null
	dmesg | grep "debug: sw r $(printf 0x%08x $(($1))) = " | tail -n 1 | sed 's/.* = \(0x[0-9a-f]*\).*/\1/'
}

# chip 32-bit read-modify-write: swm <reg> <and-mask> <or-bits>
swm() {
	v=$(swr "$1")
	[ -n "$v" ] || { say "   read of $1 failed"; return 1; }
	w=$(printf 0x%x $(( (v & $2) | $3 )))
	echo "sw w $1 $w" > "$PHY" 2>/dev/null
	say "   $1: $v -> $w, reads $(swr "$1")"
}

# SoC XPCS read-modify-write through ipq_pcs0_ctl
socm() {
	echo "r $1" > "$PCS"
	v=$(dmesg | grep "debug: r $(printf 0x%06x $(($1))) = " | tail -n 1 | sed 's/.* = \(0x[0-9a-f]*\).*/\1/')
	[ -n "$v" ] || { say "   read of $1 failed"; return 1; }
	w=$(printf 0x%x $(( (v & $2) | $3 )))
	echo "w $1 $w" > "$PCS"
	say "   $1: $v -> $w"
}

say "linkq-steps $(date), kernel $(uname -r), uptime $(cut -d' ' -f1 /proc/uptime) s"
for r in 0xc800008 0xc8001a8 0xc8001ac 0xc8001c0 0xc8001c4 0xc8001c8 0xc8001d0 0xc90f044 0xc90f048; do
	say "   chip $r = $(swr $r)"
done

echo status > "$IDLE"
measure "as booted"

echo down > "$IDLE"; sleep 5
measure "UNIPHY2 down"

echo up > "$IDLE"; sleep 5
measure "UNIPHY2 up again"

: > "$DIR/governors"
for p in "$CPUFREQ"/policy*; do
	[ -w "$p/scaling_governor" ] || continue
	echo "$(basename "$p") $(cat "$p/scaling_governor")" >> "$DIR/governors"
	echo performance > "$p/scaling_governor"
done
sleep 3
measure "CPU governor performance"
while read -r pol gov; do
	echo "$gov" > "$CPUFREQ/$pol/scaling_governor"
done < "$DIR/governors"

socm 0x38008 0xffffe000 0x16ca
socm 0x38009 0xffffe000 0x1cc8
socm 0x3800b 0xfffffefe 0x101
socm 0x38006 0xfffff0bf 0x143
sleep 3
measure "SoC XPCS EEE as on stock"

echo vmode > "$PCS"; sleep 5
measure "SoC UNIPHY again, vendor order"

echo mode > "$PCS"; sleep 5
measure "SoC UNIPHY again, our order"

echo fullnocal > "$PHY"; sleep 5
measure "chip SerDes again, no analog reset/calibration"

echo full > "$PHY"; sleep 5
measure "chip SerDes again, with calibration"

swm 0xc800008 0xfffffffe 0
sleep 3
measure "chip switch core clock off"

swm 0xc8001a8 0xfffffffe 0
sleep 3
measure "chip SerDes0 clock off"

swm 0xc90f044 0xffffffcf 0x20
swm 0xc90f048 0 0
swm 0xc8001c4 0xfffff8e0 0x3
swm 0xc8001c0 0xffffffff 0x1
swm 0xc8001c8 0xffffffff 0x1
swm 0xc8001d0 0xffffffff 0x1
sleep 3
measure "chip memory control and sec_ctrl clocks as on stock"

dmesg | grep "debug:\|idle \|settle\|SSDK order\|skipped\|7a20000" | tail -n 300 > "$DIR/debug-lines.txt"
tar -czf /tmp/linkq-steps.tar.gz "$DIR" "$SUM" 2>/dev/null
say "done"
