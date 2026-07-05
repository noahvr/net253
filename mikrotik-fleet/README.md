# MikroTik Fleet Modernization

Intent-based, git-versioned configuration management for a small MikroTik
RouterOS fleet (~10 boxes): `sites.yaml` (facts) + `templates/router.rsc.j2`
(shared logic) -> `render.py` -> `rendered/*.rsc` (what a PR reviews) ->
`deploy.py` (full-state push, human-triggered) -> `scripts/drift_check.py`
(nightly proof that intent still matches reality).

Full design rationale, rejected alternatives, and phased rollout plan:
**[docs/PLAN.md](docs/PLAN.md)**. Read that first — this README is the
quickstart, PLAN.md is the "why."

## Status

This repo has the software scaffold. It has **not** touched a real router.
Phase 0 (inventory, exports, version normalization) is manual/physical work
against real hardware and hasn't happened yet. Do not run `deploy.py
--push` against anything until you've done Phase 0 and Phase 1 in
docs/PLAN.md section 3.

- [x] Phase 2 scaffold: templates, `sites.yaml` (2 example sites), `render.py`, `deploy.py`, `scripts/drift_check.py`, docs
- [ ] Phase 0: fleet inventory + exports + version normalization (docs/inventory-template.md)
- [ ] Phase 1: OOB access, proven recovery, CHR lab (docs/lab-testing.md)
- [ ] Phase 2: real `sites.yaml` entries for all real sites, lab-validated
- [ ] Phase 3: canary rollout, one router at a time
- [ ] Phase 4: steady state (nightly drift check running on real infra)

## Layout

```
sites.yaml            # per-site facts only, no logic, ~20 lines/site
templates/
  router.rsc.j2        # shared config, ~90% of every router
  watchdog.rsc.j2       # included by router.rsc.j2
render.py              # pass 1: sites.yaml + templates -> rendered/*.rsc
deploy.py              # pass 2: resolve secrets, push, arm/disarm watchdog
scripts/drift_check.py # nightly live-vs-rendered diff
rendered/              # generated, committed, placeholder secret tokens only
inventory/             # Phase 0 raw exports, one dir per site (empty until then)
live/                  # nightly export snapshots (empty until drift_check runs)
pubkeys/               # admin SSH public keys, plaintext, safe to commit
secrets.yaml.example   # copy -> secrets.yaml, fill in, sops-encrypt
.sops.yaml.example     # copy -> .sops.yaml, list engineer age public keys
docs/
  PLAN.md               # full design doc + context handoff
  inventory-template.md # Phase 0 fleet table
  lab-testing.md        # CHR validation procedure
  rebuild.md            # per-site cold rebuild / disaster recovery
  offboarding.md         # 5-step access revocation checklist
  secrets-setup.md       # sops + age, mechanically
```

## Quickstart (safe — no network calls, no real routers)

```bash
pip install -r requirements.txt
./render.py            # renders rendered/site-a.rsc, rendered/site-b.rsc
./render.py --check     # CI mode: fails if rendered/ is stale vs sites.yaml
```

## Change flow (once past Phase 3)

1. Edit `sites.yaml` or `templates/router.rsc.j2`.
2. `./render.py`, commit intent + rendered together.
3. Open a PR. CI runs `render.py --check`. Reviewer reads the **rendered**
   diff (that's what the router eats).
4. Boot the render in the CHR lab (docs/lab-testing.md).
5. `./deploy.py push <site> --push --i-have-oob-open`, then `./deploy.py arm
   <site>`, soak, `./deploy.py disarm <site>`.
6. `scripts/drift_check.py` runs nightly on the collector host, pulling
   `/export` as the read-only `drift-ro` user, and pages someone if live
   drifts from rendered. A scheduled GitHub Actions workflow
   (`mikrotik-drift-alarm-liveness.yml`) watches the watcher: it fails if
   the collector stops committing exports, so the alarm can't die silently.

## What this deliberately does not do

No Terraform, no Ansible as the config backbone, no raw `/export` diffing,
no RADIUS/TACACS+, no secrets vault product, no CI-triggered deploys. Each
of these was considered and rejected with reasons recorded in
docs/PLAN.md section 2 and section 4 — don't re-litigate without new facts
(fleet past ~30 boxes, team past ~5 admins, new compliance requirement).
