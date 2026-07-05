# live/

Nightly `/export` snapshots, one subdirectory per site, written by
`scripts/drift_check.py` (docs/PLAN.md section 3 step 17). This is the
drift alarm: whatever lands here gets diffed against `rendered/` on every
run, and a non-empty diff means a human has to decide whether the router
was right (adopt into the template) or the router drifted (let the next
deploy conform it away).

Per docs/PLAN.md section 6, this should run somewhere the fleet operator
does not solely administer, so the alert can't be quietly silenced by
whoever made the undocumented change.

Empty until `scripts/drift_check.py` runs against real routers.
