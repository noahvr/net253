# inventory/

Phase 0 "before" photo (docs/PLAN.md section 3, steps 1–3). One directory
per real site, each holding that box's raw `/export` output and a binary
`/system backup`, pulled before anything else changes. This makes every
subsequent change detectable and gives you the material to write the
drift/discrepancy list.

This directory is empty until Phase 0 actually happens against real
hardware — nothing here is templated or generated. Structure once filled:

```
inventory/
  <site-name>/
    export.rsc          # raw `/export` output, verbatim
    backup.backup        # binary `/system backup`, verbatim
    notes.md              # anything odd found while reading it
```

See docs/inventory-template.md for the fleet table to fill in alongside this.
