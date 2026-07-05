#!/usr/bin/env python3
"""Pass 1 of the two-pass render (docs/PLAN.md section 5).

Renders templates/router.rsc.j2 against sites.yaml into rendered/*.rsc.
Secret fields in sites.yaml are already literal "{{SECRET:category:site}}"
placeholder strings -- this pass never sees or needs real secret values.
Output is safe to commit and safe to review in a PR.

Usage:
    ./render.py                 render every site in sites.yaml
    ./render.py site-a          render only site-a
    ./render.py --check         render in-memory and fail if rendered/
                                 does not already match (used by CI)
"""
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader

ROOT = Path(__file__).parent
SITES_FILE = ROOT / "sites.yaml"
TEMPLATE_DIR = ROOT / "templates"
OUTPUT_DIR = ROOT / "rendered"

REQUIRED_KEYS = (
    "name", "role", "identity", "routeros_version", "wan", "lan_ports",
    "loopback", "vlans", "ntp_servers", "snmp", "overlay", "admins",
    "break_glass", "watchdog",
)


def load_sites():
    data = yaml.safe_load(SITES_FILE.read_text())
    sites = data["sites"]
    names = [s["name"] for s in sites]
    if len(names) != len(set(names)):
        raise SystemExit(f"sites.yaml: duplicate site names in {names}")
    for site in sites:
        missing = [k for k in REQUIRED_KEYS if k not in site]
        if missing:
            raise SystemExit(f"sites.yaml: site {site.get('name', '?')} missing required keys: {missing}")
    return sites


def render_site(env, site):
    template = env.get_template("router.rsc.j2")
    return template.render(site=site)


def main():
    args = sys.argv[1:]
    check_mode = "--check" in args
    args = [a for a in args if a != "--check"]

    sites = load_sites()
    if args:
        sites = [s for s in sites if s["name"] in args]
        if not sites:
            raise SystemExit(f"no matching site(s) for {args}")

    env = Environment(
        loader=FileSystemLoader(TEMPLATE_DIR),
        trim_blocks=True,
        lstrip_blocks=True,
        keep_trailing_newline=True,
    )

    OUTPUT_DIR.mkdir(exist_ok=True)
    drift = []
    for site in sites:
        rendered = render_site(env, site)
        out_path = OUTPUT_DIR / f"{site['name']}.rsc"
        if check_mode:
            existing = out_path.read_text() if out_path.exists() else None
            if existing != rendered:
                drift.append(site["name"])
        else:
            out_path.write_text(rendered)
            print(f"rendered {out_path}")

    if check_mode:
        if drift:
            print("rendered/ is stale for: " + ", ".join(drift), file=sys.stderr)
            print("run ./render.py and commit the result", file=sys.stderr)
            raise SystemExit(1)
        print(f"rendered/ is up to date for {len(sites)} site(s)")


if __name__ == "__main__":
    main()
