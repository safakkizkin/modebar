# Security Policy

## Supported versions

Security fixes are applied on the latest release of ModeBar on `main`.

## Reporting a vulnerability

Please **do not** open a public GitHub issue for security problems.

Email or privately message the maintainer via GitHub
([@safakkizkin](https://github.com/safakkizkin)) and include:

- ModeBar version / commit
- macOS version
- Steps to reproduce
- Impact (e.g. unexpected RFCOMM traffic, local privilege issue)

You should receive an acknowledgement within a few days.

## Scope notes

ModeBar uses Classic Bluetooth RFCOMM with the App Sandbox off. That is an
intentional tradeoff for IOBluetooth access, not a bug by itself. Reports about
Gatekeeper quarantine on unsigned builds are support issues, not vulnerabilities.
