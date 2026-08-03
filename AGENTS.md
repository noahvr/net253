# AGENTS.md

## Cursor Cloud specific instructions

### What this repo is
This is a network-infrastructure **config/data** repository for Net253 LLC (AS396952), not a
buildable application. It contains MikroTik router exports (`devices/*.rsc`), BGP announce config
and per-peer out-filters (`bgp/`), a device inventory (`devices.yml`), and an RFC 8805 geofeed
(`geofeed.csv`). There is no server/app to build or run.

### Toolchain / services
The only "runnable" logic lives in `.github/workflows/`:
- `formatting.yml` — sorts BGP prefixes using Python3 + PyYAML + `ipaddress`.
- `rpki-check.yml` — checks prefix lengths and validates RPKI via `yq`/`jq`/`curl` against the
  live RIPE stat API (`https://stat.ripe.net`), for `ASN=396952`.

Required tools: `python3` + PyYAML (base image), `jq`, `curl` (base image), and **mikefarah** `yq`.

### Non-obvious gotchas
- **`yq` flavor matters.** The base image ships `kislyuk/yq` (a Python jq-wrapper with different
  syntax) at `/usr/bin/yq`. The workflows require **mikefarah** `yq`. The update script installs
  mikefarah `yq` to `/usr/local/bin/yq`, which precedes `/usr/bin` in `PATH` and shadows the
  kislyuk one. Confirm with `yq --version` (should say `mikefarah`).
- **Workflows don't match the committed data.** Both workflows read `net253_bgp.yml` at the repo
  root with a `netblocks4`/`netblocks6` schema, but the actual file is `bgp/net253_bgp.yml` using a
  different schema (`self`/`peers`/`announce`). The `.yml` files here are loosely-formatted human
  records and are **not** guaranteed to parse with a strict YAML loader (`yaml.safe_load` / mikefarah
  `yq` both error on `bgp/net253_bgp.yml` and `devices.yml` as committed). Do not assume they load.
- **RPKI validation needs network egress** to `stat.ripe.net`. The authoritative clean list of the
  network's prefixes is `geofeed.csv` (parse with `grep -v '^#' geofeed.csv | cut -d',' -f1`).

### Lint / test / build / run
There is no build or app to run. The closest equivalents are the two workflow scripts above; run
their logic locally against `geofeed.csv` (clean prefixes) or a well-formed
`netblocks4`/`netblocks6` sample.
