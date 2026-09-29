#!/bin/sh
# Every string our LuCI pages pass to _() must have an English entry in
# i18n/be7000.en.po, and the committed .lmo must be built from that .po.
#   scripts/i18n-check.sh [path/to/po2lmo]
cd "$(dirname "$0")/.." || exit 1
PO=i18n/be7000.en.po
LMO=overlay-files/usr/lib/lua/luci/i18n/be7000.en.lmo
fail=0

python3 - "$PO" <<'PY' || fail=1
import re, sys, glob
po = open(sys.argv[1], encoding='utf-8').read()
have = set(bytes(m, 'utf-8').decode('unicode_escape').encode('latin-1').decode('utf-8')
           for m in re.findall(r'^msgid "(.*)"$', po, re.M))
files = [f for pat in ('overlay-files/www/**/*.js', 'awg-feed/*/htdocs/**/*.js', 'overlay-files/usr/share/luci/menu.d/*.json', 'awg-feed/*/root/usr/share/luci/menu.d/*.json')
         for f in glob.glob(pat, recursive=True)]
# LuCI's own files we only fork are not ours to translate
files = [f for f in files if not f.endswith('view/network/wireless.js')]
missing = []
for f in files:
    s = open(f, encoding='utf-8').read()
    if f.endswith('.json'):
        found = re.findall(r'"title":\s*"([^"]*)"', s)
    else:
        found = [m.group(2) for m in re.finditer(r"_\((['\"])((?:\\.|(?!\1).)*)\1", s)]
    for v in found:
        v = v.replace("\\'", "'").replace('\\"', '"')
        if re.search('[А-Яа-яЁё]', v) and v not in have:
            missing.append((f, v))
for f, v in missing:
    print('missing: %s: %s' % (f, v))
sys.exit(1 if missing else 0)
PY

if [ -n "${1:-}" ] && [ -x "$1" ]; then
	tmp=$(mktemp)
	"$1" "$PO" "$tmp" && cmp -s "$tmp" "$LMO" || { echo "$LMO is not built from $PO"; fail=1; }
	rm -f "$tmp"
fi

[ $fail = 0 ] && echo "i18n ok"
exit $fail
