# Fleet inventory (Phase 0, step 1)

Fill this in before touching any config. The "reach it when down" column is
the point of the exercise — most of these cells will start blank, and each
blank cell is a Phase 1 (OOB) task.

Do not commit real credential material here. Names of credential holders
and *where* the credential lives (e.g. "1Password: Fleet vault") are fine;
the credential itself is not.

| Site name | Model | RouterOS version | Serial | Physical location | Credential holder(s) | Reach it when routing is down | Notes |
|---|---|---|---|---|---|---|---|
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |
| | | | | | | | |

## How to fill this in

For each router:

1. `Model` / `Serial`: `/system routerboard print`
2. `RouterOS version`: `/system resource print` (look for `version`)
3. `Reach it when routing is down`: be honest. "Drive there" is a valid
   answer today — it is the answer Phase 1 (OOB access) exists to replace.
   "Nothing, it's the only path in" is the most important answer on this
   sheet to find.

## Next step

Once this table has no blank cells in the first six columns, pull `/export`
and a binary `/system backup` from every box into `inventory/<site-name>/`
(one directory per site) and commit them — that is the "before" photo
referenced in docs/PLAN.md section 3, Phase 0 step 2. Then read all ten
exports side by side and write down the discrepancy list (step 3) before
normalizing RouterOS versions (step 4).
