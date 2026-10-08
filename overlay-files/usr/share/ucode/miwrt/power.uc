// MiWRT hub, remote power: put a laptop to sleep or restart it over SSH, with a key that can do nothing else.
//
// The router holds one key. Each laptop accepts that key only from the router's address and only for a fixed
// script (status, sleep, restart). A laptop is added by running one setup command on it; the command carries a
// one-time code, and the script it downloads is checked against a checksum the app shows.
'use strict';

import { readfile, writefile, stat, unlink, mkdir, chmod, access } from 'fs';
import * as digest from 'digest';
import * as hub from 'miwrt.hub';

const DIR = '/etc/miwrt/power';
const KEY = DIR + '/id_ed25519';
const HOSTS = DIR + '/hosts.json';
const CODES = '/tmp/miwrt/power-codes.json';
const CODE_LIFE = 1800;
const ACTIONS = { status: true, sleep: true, restart: true };

function public_key() {
	if (!access(KEY, 'r')) {
		mkdir(DIR, 0700);
		system(`dropbearkey -t ed25519 -f ${KEY} >/dev/null 2>&1`);
		chmod(KEY, 0600);
	}
	let m = match(hub.run(`dropbearkey -y -f ${KEY} 2>/dev/null`), /(ssh-ed25519 [A-Za-z0-9+\/=]+)/);
	return m ? m[1] : null;
}

function device(mac) {
	for (let d in (hub.cached('devices')?.devices ?? [])) if (d.mac == mac) return d;
	return null;
}

/* The router's own address on the same network as the device: what the laptop will see the login come from. */
function router_address(ip) {
	let want = match(ip ?? '', /^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+$/);
	if (!want) return null;
	for (let line in split(hub.run('ip -4 -o addr show 2>/dev/null'), '\n')) {
		let m = match(line, /inet ([0-9]+\.[0-9]+\.[0-9]+)\.([0-9]+)\//);
		if (m && m[1] == want[1]) return `${m[1]}.${m[2]}`;
	}
	return null;
}

function key_line(from, command, pub) {
	return `from="${from}",command="${command}",no-pty,no-port-forwarding,no-agent-forwarding,no-X11-forwarding ${pub} miwrt-router`;
}

function mac_script(from, pub, code) {
	return `#!/bin/sh
# MiWRT remote power for this Mac.
# Lets your MiWRT router (${from}) put this Mac to sleep or restart it, and nothing else:
#  - Remote Login (SSH) is switched on.
#  - The router's key is accepted only from ${from} and can only run /usr/local/bin/miwrt-power.
#  - One sudo rule lets your account run "shutdown -r now" without a password.
# To undo: delete the miwrt-router line from ~/.ssh/authorized_keys, and remove
# /usr/local/bin/miwrt-power and /etc/sudoers.d/miwrt-power.
set -e
[ "$(id -u)" = 0 ] || { echo "Run this with sudo."; exit 1; }
U="\${SUDO_USER:-$(stat -f %Su /dev/console)}"
[ -n "$U" ] && [ "$U" != root ] || { echo "Could not tell which account to set up. Run it with sudo from your own account."; exit 1; }
H=$(dscl . -read "/Users/$U" NFSHomeDirectory | awk '{print $2}')

mkdir -p /usr/local/bin
cat > /usr/local/bin/miwrt-power <<'EOS'
#!/bin/sh
# Run by the MiWRT router's key. Only these three requests are accepted.
case "$SSH_ORIGINAL_COMMAND" in
	status) echo "ok macOS $(sw_vers -productVersion)" ;;
	sleep) echo ok; nohup sh -c 'sleep 1; pmset sleepnow' >/dev/null 2>&1 & ;;
	restart) echo ok; nohup sh -c 'sleep 1; sudo -n /sbin/shutdown -r now' >/dev/null 2>&1 & ;;
	*) echo "not allowed"; exit 1 ;;
esac
EOS
chown root:wheel /usr/local/bin/miwrt-power
chmod 755 /usr/local/bin/miwrt-power

echo "$U ALL=(root) NOPASSWD: /sbin/shutdown -r now" > /etc/sudoers.d/miwrt-power
chmod 440 /etc/sudoers.d/miwrt-power
visudo -cf /etc/sudoers.d/miwrt-power >/dev/null || { rm -f /etc/sudoers.d/miwrt-power; echo "Could not add the restart rule."; exit 1; }

mkdir -p "$H/.ssh"
touch "$H/.ssh/authorized_keys"
grep -v ' miwrt-router$' "$H/.ssh/authorized_keys" > "$H/.ssh/authorized_keys.miwrt" || true
cat >> "$H/.ssh/authorized_keys.miwrt" <<'EOS'
${key_line(from, '/usr/local/bin/miwrt-power', pub)}
EOS
mv "$H/.ssh/authorized_keys.miwrt" "$H/.ssh/authorized_keys"
chown -R "$U" "$H/.ssh"
chmod 700 "$H/.ssh"
chmod 600 "$H/.ssh/authorized_keys"

# Remote Login on (the second form works where the first needs Full Disk Access)
systemsetup -setremotelogin on >/dev/null 2>&1 || true
launchctl enable system/com.openssh.sshd >/dev/null 2>&1 || true
launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist >/dev/null 2>&1 || true
# wake for network access while on the charger
pmset -c womp 1 >/dev/null 2>&1 || true

sleep 2
if ! nc -z 127.0.0.1 22 >/dev/null 2>&1; then
	echo "Remote Login did not start. Switch it on in System Settings, General, Sharing, Remote Login, then run this again."
	exit 1
fi
if curl -fsSk -m 15 -H 'Content-Type: application/json' -d "{\\"code\\":\\"${code}\\",\\"user\\":\\"$U\\"}" https://${from}/cgi-bin/miwrt/power/register >/dev/null; then
	echo "Done. This Mac can now be put to sleep, restarted and woken from the MiWRT app."
else
	echo "This Mac is set up, but the router did not confirm. Make a new setup command in the app and run it again."
	exit 1
fi
`;
}

function windows_script(from, pub, code) {
	return `# MiWRT remote power for this PC.
# Lets your MiWRT router (${from}) put this PC to sleep or restart it, and nothing else:
#  - The OpenSSH server that comes with Windows is installed and started, reachable only from ${from}.
#  - The router's key is accepted only from ${from} and can only run C:\\ProgramData\\miwrt\\power.ps1.
# To undo: delete the miwrt-router line from C:\\ProgramData\\ssh\\administrators_authorized_keys
# and delete C:\\ProgramData\\miwrt.
$ErrorActionPreference = 'Stop'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { Write-Host 'Open PowerShell with "Run as administrator" and run the command again.'; exit 1 }

$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
if ($cap.State -ne 'Installed') { Write-Host 'Installing the OpenSSH server (a minute or two)...'; Add-WindowsCapability -Online -Name $cap.Name | Out-Null }
Set-Service -Name sshd -StartupType Automatic
Start-Service sshd

New-Item -ItemType Directory -Force 'C:\\ProgramData\\miwrt' | Out-Null
@'
# Run by the MiWRT router's key. Only these three requests are accepted.
switch ($env:SSH_ORIGINAL_COMMAND) {
	'status' { "ok Windows $([Environment]::OSVersion.Version)" }
	'sleep' {
		'ok'
		Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', 'Start-Sleep 1; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $false)'
	}
	'restart' { 'ok'; shutdown.exe /r /t 3 | Out-Null }
	default { 'not allowed'; exit 1 }
}
'@ | Set-Content -Encoding ASCII 'C:\\ProgramData\\miwrt\\power.ps1'

$line = '${key_line(from, 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\\\ProgramData\\\\miwrt\\\\power.ps1', pub)}'
$files = @('C:\\ProgramData\\ssh\\administrators_authorized_keys', (Join-Path $env:USERPROFILE '.ssh\\authorized_keys'))
foreach ($f in $files) {
	New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
	$keep = @()
	if (Test-Path $f) { $keep = @(Get-Content $f | Where-Object { $_ -notmatch ' miwrt-router$' }) }
	($keep + $line) | Set-Content -Encoding ASCII $f
}
icacls 'C:\\ProgramData\\ssh\\administrators_authorized_keys' /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null

# only the router may reach the SSH server
$rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($rule) { $rule | Set-NetFirewallRule -Enabled True -RemoteAddress '${from}' }
else { New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (MiWRT router only)' -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -RemoteAddress '${from}' | Out-Null }

# let the network adapters wake the PC
Get-NetAdapter -Physical | ForEach-Object { try { Set-NetAdapterPowerManagement -Name $_.Name -WakeOnMagicPacket Enabled -ErrorAction Stop } catch {} }

$body = Join-Path $env:TEMP 'miwrt-register.json'
('{"code":"${code}","user":"' + $env:USERNAME + '"}') | Set-Content -Encoding ASCII -NoNewline $body
curl.exe -fsSk -m 15 -H 'Content-Type: application/json' -d "@$body" https://${from}/cgi-bin/miwrt/power/register | Out-Null
$ok = $LASTEXITCODE -eq 0
Remove-Item $body -ErrorAction SilentlyContinue
if ($ok) { Write-Host 'Done. This PC can now be put to sleep, restarted and woken from the MiWRT app.' }
else { Write-Host 'This PC is set up, but the router did not confirm. Make a new setup command in the app and run it again.'; exit 1 }
`;
}

function codes() {
	let now = time(), all = hub.load(CODES, {});
	for (let c in keys(all)) if (all[c].exp < now) delete all[c];
	return all;
}

export function status(mac) {
	let h = hub.load(HOSTS, {})[mac];
	return h ? { configured: true, os: h.os, user: h.user, added: h.added } : { configured: false };
};

/* Makes the one-time setup command for a laptop. */
export function setup(mac, os) {
	if (!hub.is_mac(mac)) return { error: 'unknown device' };
	if (os != 'mac' && os != 'windows') return { error: 'Choose macOS or Windows.' };
	let d = device(mac);
	if (!d?.ip || !d.online) return { error: 'The laptop has to be awake and on your network while you set it up.' };
	let from = router_address(d.ip), pub = public_key();
	if (!from || !pub) return { error: 'The router could not prepare its key.' };
	let code = hexenc(hub.random_bytes(16));
	let script = os == 'mac' ? mac_script(from, pub, code) : windows_script(from, pub, code);
	let sum = digest.sha256(script), url = `https://${from}/cgi-bin/miwrt/power/s?c=${code}`;
	let all = codes();
	all[code] = { mac, os, ip: d.ip, exp: time() + CODE_LIFE, script };
	hub.save_private(CODES, all);
	let command = os == 'mac'
		? `curl -fsSk '${url}' -o /tmp/miwrt-power.sh && echo '${sum}  /tmp/miwrt-power.sh' | shasum -a 256 -c - && sudo sh /tmp/miwrt-power.sh`
		: `curl.exe -fsSk "${url}" -o "$env:TEMP\\miwrt-power.ps1"; if ((Get-FileHash "$env:TEMP\\miwrt-power.ps1").Hash -eq '${uc(sum)}') { powershell -ExecutionPolicy Bypass -File "$env:TEMP\\miwrt-power.ps1" } else { 'The download did not match. Nothing was run.' }`;
	return { command, os, expires_in: CODE_LIFE };
};

/* The setup script itself, fetched by the laptop with its one-time code. */
export function script(code) {
	if (type(code) != 'string' || !match(code, /^[0-9a-f]{32}$/)) return null;
	return codes()[code]?.script ?? null;
};

/* Called by the setup script when it has finished on the laptop. */
export function register(b, ip) {
	if (type(b?.code) != 'string' || !match(b.code, /^[0-9a-f]{32}$/)) return 'bad code';
	if (type(b.user) != 'string' || !match(b.user, /^[A-Za-z0-9._-]{1,32}$/)) return 'This account name has characters the router cannot use.';
	return hub.locked(() => {
		let all = codes(), c = all[b.code];
		if (!c) return 'This setup command has expired. Make a new one in the app.';
		if (c.ip != ip) return 'The setup command was made for a different device.';
		let hosts = hub.load(HOSTS, {});
		hosts[c.mac] = { os: c.os, user: b.user, added: time() };
		mkdir(DIR, 0700);
		hub.save_private(HOSTS, hosts);
		delete all[b.code];
		hub.save_private(CODES, all);
		// the laptop's SSH identity is remembered at the first login; forget any older one for this address
		let kh = DIR + '/.ssh/known_hosts', old = readfile(kh);
		if (old) writefile(kh, join('\n', filter(split(old, '\n'), l => length(l) && index(l, ip + ' ') != 0)) + '\n');
		hub.add_alert('router', 'Remote power set up', `${device(c.mac)?.name ?? c.mac} can now be put to sleep and restarted from the app.`, 'info');
		return null;
	});
};

export function remove(mac) {
	return hub.locked(() => {
		let hosts = hub.load(HOSTS, {});
		if (!(mac in hosts)) return null;
		delete hosts[mac];
		hub.save_private(HOSTS, hosts);
		return null;
	});
};

/* sleep, restart or status on a laptop that has been set up. Returns { ok, detail } or { error }. */
export function action(mac, what) {
	if (!hub.is_mac(mac) || !ACTIONS[what]) return { error: 'unknown request' };
	let h = hub.load(HOSTS, {})[mac];
	if (!h) return { error: 'Remote power is not set up for this device.' };
	let d = device(mac);
	if (!d?.ip || !match(d.ip, /^[0-9]{1,3}(\.[0-9]{1,3}){3}$/)) return { error: 'The router does not know this device\'s address.' };
	if (!match(h.user, /^[A-Za-z0-9._-]{1,32}$/)) return { error: 'The saved account name is not usable. Set remote power up again.' };
	mkdir(DIR + '/.ssh', 0700);
	let out = trim(hub.run(`HOME=${DIR} timeout 12 dbclient -y -T -i ${KEY} -o BatchMode=yes '${h.user}@${d.ip}' ${what} 2>&1 </dev/null`));
	for (let line in split(out, '\n')) {
		let m = match(trim(line), /^ok ?(.*)$/);
		if (!m) continue;
		if (what != 'status') hub.add_alert('device', what == 'sleep' ? 'Put to sleep' : 'Restarted', d.name, 'info');
		return { ok: true, detail: m[1] };
	}
	if (match(out, /not allowed/)) return { error: 'The laptop refused that request.' };
	if (match(out, /[Hh]ost key mismatch|HOST KEY/)) return { error: 'The laptop\'s identity changed since setup. Remove remote power for it and set it up again.' };
	if (match(out, /[Pp]ermission denied|auth|publickey/)) return { error: 'The laptop did not accept the router\'s key. Run the setup command on it again.' };
	return { error: d.online ? 'The laptop did not answer. Check that remote login is still on.' : 'The laptop is asleep or off the network. Wake it first.' };
};
