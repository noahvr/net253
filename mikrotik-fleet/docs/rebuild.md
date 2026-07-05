# Per-site cold rebuild procedure

Purpose: prove a router is disposable. Run this as a drill twice a year
(docs/PLAN.md section 3 step 18) against a spare or a lab CHR, and for real
if a box dies. If you can't do this from the repo alone, the repo is not
actually the source of truth yet — go fix that instead of the router.

## Prerequisites

* The site's entry exists in `sites.yaml` and `rendered/<site>.rsc` is current (`./render.py <site>`).
* `secrets.yaml` has real values for that site (`wg_privkey`, `break_glass_password`, `snmp_community`).
* The admin's public key file exists in `pubkeys/<username>.pub`.
* Physical or console access to the box (netinstall needs this; there is no remote path for a box with no OS on it).
* An out-of-band session you can fall back to if the new config locks you out.

## Procedure

1. **Netinstall** the pinned RouterOS version from `sites.yaml` (`routeros_version`) onto the router/CHR. Do not skip pinning — a version mismatch is exactly the "10 versions = 10 dialects" problem docs/PLAN.md section 3 step 4 exists to prevent.
2. **Resolve secrets**: `./deploy.py push <site>` (dry-run — do NOT pass `--push` yet). This writes the real, resolved `.rsc` to `/dev/shm/mikrotik-deploy/<site>.rsc` on the management host.
3. **Get the file onto the box.** For a box with no network config yet, this means a direct/console-attached transfer (serial, or a temporary IP + scp/Winbox file upload), not the overlay — the overlay doesn't exist until this config lands. Also copy `pubkeys/<username>.pub` for each admin.
4. **Apply**: `/system reset-configuration run-after-reset=<site>.rsc` (or netinstall directly with the file staged, if your netinstall flow supports it).
5. **Verify from a cold boot, not from the session that configured it**: reboot again, then reconnect from the management host over the WireGuard overlay (`ssh admin@<overlay-address>`). This step exists because the classic self-lockout is a firewall rule that only shows up after the SSH session that built it disconnects — see docs/lab-testing.md.
6. **Confirm**: SNMP responds, NTP is syncing, the break-glass account exists and is NOT reachable except locally, and `/export` from the box roughly matches `rendered/<site>.rsc` modulo the secret-bearing lines (see `scripts/drift_check.py`).
7. **Arm the watchdog** (`./deploy.py arm <site>`) if this was a real deploy, not a drill; disarm after the soak window.
8. **Take a binary backup** (`/system backup save name=last-known-good`) once you're satisfied — this is what the watchdog restores to on the *next* failed change, so don't skip it.

## If step 5 fails (you're locked out)

Use the out-of-band session, not the overlay. Console in if you have to.
Compare the firewall input chain in `rendered/<site>.rsc` against what
actually loaded — most lockouts are an interface name mismatch (e.g. the
WireGuard interface name in the firewall rule not matching the one the
`/interface wireguard add` line actually created). Fix it in the lab
(docs/lab-testing.md) before touching the real box again.
