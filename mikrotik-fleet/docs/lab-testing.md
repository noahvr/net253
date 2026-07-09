# Lab validation (Phase 1 step 7 / Phase 2 step 11)

Every rendered config gets booted in a lab CHR before it goes near real
hardware. This is not optional and not a formality — the failure mode it
catches (a rendered firewall blocking your own SSH, visible only on a cold
boot) is the single most common way people brick a router with "modern
tooling" instead of without it.

## Setup (one time)

1. Download a Cloud Hosted Router (CHR) image matching the fleet's pinned
   RouterOS version (`sites.yaml` -> `routeros_version`) from MikroTik.
2. Boot it in your hypervisor of choice (any will do — this is a config
   test, not a performance test).
3. Give the CHR's WAN-equivalent interface reachability to wherever your
   management host and WireGuard peer endpoint live, so the overlay can
   actually come up during the test.

## Per-render validation

For each `rendered/<site>.rsc` you're about to trust:

1. Reset the CHR to a blank state (`/system reset-configuration
   no-defaults=yes`) or redeploy the VM from a clean snapshot.
2. Follow docs/rebuild.md steps 2–4 against the CHR instead of a real box.
3. **Reboot the CHR again** (not just apply-and-check-in-the-same-session).
   Then, from a *different* terminal/session than the one that applied the
   config, connect over the WireGuard overlay. If you can't get in, you
   just found a self-lockout in the lab instead of at a site an hour's
   drive away — that is the entire point of this step.
4. Confirm:
   - Identity, VLANs, and IP addressing match `sites.yaml` for that site.
   - `/ip service print` shows only ssh/winbox/api-ssl, all bound to the
     overlay subnet; telnet/ftp/www/api are disabled.
   - `/user print` shows only the expected admins (SSH-key auth) plus the
     break-glass account.
   - `/system script print` and `/system scheduler print` show the
     watchdog script and job.
   - `/export` from the CHR, run through `scripts/drift_check.py`'s
     normalization, matches `rendered/<site>.rsc`.
5. Only after all of the above passes does this render get promoted to the
   canary router (docs/PLAN.md section 3, Phase 3).

## What the lab does NOT catch

Physical-layer and ISP-specific issues (PPPoE quirks, VLAN tagging some
switch, dying hardware). The lab proves the *config* is sound; the canary
step (Phase 3) proves it against real traffic and real hardware. Don't skip
either one for the other.
