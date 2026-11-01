# Security

## Reporting a vulnerability

Please report privately through GitHub: Security tab, "Report a vulnerability" on
https://github.com/Puneetspyne/Meridian. Do not open a public issue for security problems. Expect an
acknowledgement within a few days.

## What the app can access

- Read-only hardware and OS telemetry: CPU, memory, GPU, disks, network, battery, temperatures, fans, power, processes.
- Calendar events (read-only), only if you grant access.
- Location (when in use), only to name the Wi-Fi network, only if you grant access.
- Network: Open-Meteo, only when weather is turned on. See [docs/PRIVACY.md](docs/PRIVACY.md).
- Meridian is not sandboxed and is distributed outside the App Store. It is ad-hoc signed and not notarized.
- Some sensors use private Apple interfaces resolved at runtime; they fail soft.

## No root helper

Meridian ships no privileged helper and never asks for an administrator password. If one is ever added
(for example for fan control), it will be opt-in, separately documented, and called out here.

## Verifying a download

Releases include `SHA256SUMS`. `scripts/install.sh` verifies it before installing.
