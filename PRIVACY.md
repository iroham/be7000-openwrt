# MiWRT privacy

This covers the MiWRT firmware's app service, the MiWRT iPhone app, and the notification relay.

## In short

- The app talks to your own router, on your own network. There is no account and no cloud service behind it.
- The app's publisher receives no information about your network, your devices or what they do.
- The one thing that leaves your home through a server we run is a notification, and its text is encrypted so that we cannot read it.
- There is no advertising, no analytics and no tracking in the app or in the firmware's app service.

## What stays in your home

Everything the app shows comes from your router and is stored on your router: the list of devices, their names and traffic totals, alerts, schedules, Wi-Fi settings. The app keeps on the phone only what it needs to reach the router: the router's address, the phone's own access key, the router's certificate fingerprint, and a key for decrypting notifications. These are stored in the iPhone's Keychain and are not included in backups.

The router's administrator password is sent to the router once, at pairing, over an encrypted connection. It is not stored on the phone.

## Notifications

Apple delivers a notification only when it is signed by the app's publisher, so a router cannot send one entirely by itself. If you switch notifications on:

- your router encrypts the alert's title and text with a key that only your phone has;
- it sends the encrypted alert, your phone's notification address (a random value Apple issues for the app on that phone) and the kind of alert (for example "internet" or "new device") to the relay at `miwrt-relay.iroham.cloud`;
- the relay passes it to Apple, and Apple delivers it to your phone, where the app decrypts it.

The relay does not store or log anything. It, and Apple, see the notification address and the kind of alert, and cannot read the text. As with any internet service, the relay's host (Cloudflare) sees the address the request came from.

Notifications are off until you switch them on, and can be switched off again at any time. A router can also be pointed at another relay, or given its own push key, in which case ours is not used.

## Other connections the router makes for the app

- Speed test: downloads from and uploads to Cloudflare's public speed test servers, only when you start a test.
- Firmware check: asks GitHub for the latest release of this project.
- Ad blocker link: if you link an AdGuard Home, the router talks to it on your network with the login you entered. That login is stored on the router.

## Children

The app is a network tool and is not directed at children.

## Changes and contact

Changes to this text are made in this repository, where the history is public. Questions: open an issue at https://github.com/iroham/be7000-openwrt/issues.
