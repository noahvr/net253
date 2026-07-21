# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This is a **network operations / config-as-data** repo for Net253, LLC (ISP, AS396952) — not a
software application. There is **no build system, no package manifest/lockfile, no runnable app,
and no database**. It holds MikroTik RouterOS exports (`hyla355.rsc`), BGP policy/filters (`bgp/`),
a geofeed (`geofeed.csv`), and a device inventory (`devices.yml`). Restoration of `.rsc` onto a
device is documented in `README.md` and cannot be exercised locally (needs real hardware).

### The only automation = CI validation
The two GitHub Actions in `.github/workflows/` are the closest thing to a runnable "app":
- `formatting.yml` — sorts BGP prefixes (`python3` + `pyyaml`).
- `rpki-check.yml` — prefix-length check + live RPKI validation against `stat.ripe.net`
  (`python3`, `jq`, `curl`, and mikefarah `yq`).

To validate the config locally, reproduce those steps (prefix-length limits: IPv4 ≤ /24, IPv6 ≤ /48;
RPKI via `https://stat.ripe.net/data/rpki-validation/data.json?resource=AS396952&prefix=<enc>`).

### Non-obvious gotchas (important)
- **`yq` mismatch:** the preinstalled `/usr/bin/yq` is the Python (kislyuk) `yq` (a jq wrapper),
  **not** the mikefarah `yq` the workflows download inline. The workflows' `yq -r '.netblocks4[].prefix'`
  syntax does not work with the preinstalled binary. Install mikefarah `yq` separately if you need it.
- **Workflow/data drift:** the workflows target `net253_bgp.yml` at repo root with `netblocks4`/
  `netblocks6` keys, but the actual file lives at `bgp/net253_bgp.yml` and uses
  `announce.<asn>.v4[].prefix` / `...v6[]`. The workflows are effectively mismatched against current data.
- **`bgp/net253_bgp.yml` is not loadable by YAML parsers as-is** (lines 1–2 mix a mapping key
  `self:` with a sequence item `- asn:`), so `pyyaml`/`yq` fail on the whole file. To extract prefixes
  reliably, scan the well-formed `- prefix: <cidr>` lines with a regex instead of a YAML loader.
- **RPKI checks need outbound access** to `stat.ripe.net` and can occasionally time out — retry.

### Tooling (preinstalled in the base image)
`python3` 3.12 with `pyyaml`, plus `jq`, `curl`, `wget`, `git`. No install step is required for
local validation beyond (optionally) fetching mikefarah `yq`.
