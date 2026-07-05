# live/

Nightly `/export` snapshots, one subdirectory per site, written by
`scripts/drift_check.py` (docs/PLAN.md section 3 step 17). This is the
drift alarm: whatever lands here gets diffed against `rendered/` on every
run, and a non-empty diff means a human has to decide whether the router
was right (adopt into the template) or the router drifted (let the next
deploy conform it away).

Per docs/PLAN.md section 6, this should run somewhere the fleet operator
does not solely administer, so the alert can't be quietly silenced by
whoever made the undocumented change. Two properties back that up:

* The pull authenticates as the dedicated read-only `drift-ro` user
  (`sites.yaml` -> `drift_ro:`, key in `pubkeys/drift-ro.pub`), not the
  deploy credential — a compromised collector can read configs, not
  rewrite routers.
* A scheduled GitHub Actions workflow
  (`.github/workflows/mikrotik-drift-alarm-liveness.yml`) fails if no new
  export has been committed here in >26h — the dead-man switch for the
  alarm itself. It stays quiet until the first real export lands, so it
  won't false-alarm before the collector is in service.

Empty until `scripts/drift_check.py` runs against real routers.
