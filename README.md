# TailGateway

TailGateway is a small macOS menu bar controller for Tailscale Exit Node split routing.

It keeps the simple model:

- Tail Mode On: IP CIDR and domain whitelist traffic goes through the local gateway (`en0`) and bypasses Tailscale.
- Tail Mode Off: local bridge routes are removed, so traffic follows the Tailscale Exit Node.
- Everything not matched by the whitelist stays on the Tailscale Exit Node.

TailGateway owns its runtime engine and whitelist data under `~/Library/Application Support/TailGateway`.

## Features

- Fox-tail menu bar status icon.
- One menu trigger: when Tail Mode is off it shows "Turn Tail Mode On"; when on it shows "Turn Tail Mode Off".
- Main management window for status, launch options, whitelists, and ping checks.
- Import and export IP CIDR whitelist lists.
- Import and export domain whitelist lists.
- Import, export, add, update, and delete pinned single-IP whitelist entries.
- Add a single website manually.
- Delete a selected website.
- Toggle app launch at login and restoring the last Tail Mode at login.

## Build

```zsh
swift build -c release
```

Install the command-line binary and menu bar app bundle:

```zsh
./scripts/install.sh
```

The installer creates:

```text
~/.local/bin/TailGateway
~/Applications/TailGateway.app
~/Library/Application Support/TailGateway
```

Run from source:

```zsh
swift run TailGateway
```

Run the release binary:

```zsh
.build/release/TailGateway
```

Run the installed app:

```zsh
open ~/Applications/TailGateway.app
```

## Runtime Files

TailGateway installs its internal engine and data here:

```text
~/Library/Application Support/TailGateway/bin/tailgatewayctl
~/Library/Application Support/TailGateway/bin/tailgateway-auto
~/Library/Application Support/TailGateway/Engine/
~/Library/Application Support/TailGateway/State/
~/Library/Application Support/TailGateway/Archive/
```

The engine directory contains:

- `cn-ip-list.txt`
- `cn-fast-route-domains.txt`
- `cn-domains-for-local-dns.txt`
- `pinned-hosts.txt`
- Apple/iCloud and WeChat route helper scripts

The UI is the intended way to import/export lists, add/delete domains, add/update/delete pinned IPs, toggle launch options, check status, and run ping checks.

## Notes

- Route changes require the existing passwordless `sudo /sbin/route` setup used by the bridge engine.
- This is not a VPN client. Tailscale remains responsible for the Exit Node.
