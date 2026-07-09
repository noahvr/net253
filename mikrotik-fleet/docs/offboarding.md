# Offboarding checklist

When an engineer with fleet access leaves (or a laptop/key is compromised),
do all five steps the same day. The credential improvised offboarding
always misses is the WireGuard key — it is on this list on purpose.

1. Delete their RouterOS user entry from `sites.yaml` (every site's `admins:` list).
2. Remove their `age` public key from `.sops.yaml` (`keys:` list for `secrets.yaml`).
3. Re-encrypt `secrets.yaml` with `sops updatekeys secrets.yaml` so it's no longer decryptable with the removed key.
4. Rotate every WireGuard key they could read or hold (their own mgmt-host access, plus any per-site `wg_privkey` secrets they had access to) and rotate any break-glass passwords they knew.
5. Redeploy the fleet (`./deploy.py push <site> --push --i-have-oob-open` per site, one at a time, per docs/PLAN.md section 3) so the rotated values take effect on every router.

Until step 5 completes, the old keys are still live on the routers — steps
1–4 only revoke access to the *repo and vault*, not to the fleet itself.
