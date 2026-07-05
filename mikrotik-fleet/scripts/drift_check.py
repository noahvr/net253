#!/usr/bin/env python3
"""Nightly drift check (docs/PLAN.md section 3 step 17).

For every site: SSH in, run /export, commit the result to the live/
directory on the `live` branch, then diff it against rendered/<site>.rsc.
A non-empty diff means either untracked drift (someone hand-edited the
router) or a same-day emergency fix that hasn't been back-ported to the
templates yet (docs/PLAN.md section 7) -- either way, a human must look at
it and decide: adopt into the template, or let the next deploy erase it.
The only forbidden state is leaving it undecided.

Known blind spot: RouterOS /export omits passwords and private keys, so
this can never see credential changes made on-box. It can see user
existence and SSH key fingerprints. See docs/PLAN.md section 5.

This script must run somewhere the fleet operator does not solely
administer (a CI runner, a second host) so the alert cannot be quietly
silenced by whoever made the undocumented change. Running it from a
laptop the same person controls defeats the point.

Usage:
    ./scripts/drift_check.py                 check every site, exit 1 if any drift
    ./scripts/drift_check.py --site site-a    check a single site
    ./scripts/drift_check.py --no-commit      skip git commit (for local testing)
"""
import argparse
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import yaml

ROOT = Path(__file__).parent.parent
SITES_FILE = ROOT / "sites.yaml"
RENDERED_DIR = ROOT / "rendered"
LIVE_DIR = ROOT / "live"

# RouterOS omits these parameters' values from /export (sometimes the whole
# parameter, sometimes just the value); rendered/ carries them as
# placeholder tokens instead. Strip just the key=value token from both
# sides before diffing -- not the whole line -- so the rest of the line
# (interface names, other params on the same command) still gets compared.
SECRET_PARAM_RE = re.compile(
    r'\s*(?:private-key|password|shared-secret|preshared-key)=(?:"[^"]*"|\S+)',
    re.IGNORECASE,
)

# /snmp community's payload parameter is confusingly called "name=" -- strip
# it only on that command, since "name=" is a legitimate non-secret
# identifier everywhere else (e.g. `/interface bridge add name=bridge-lan`).
SNMP_COMMUNITY_NAME_RE = re.compile(r'\s*name=(?:"[^"]*"|\S+)')


def load_sites():
    data = yaml.safe_load(SITES_FILE.read_text())
    return data["sites"]


def overlay_host(site):
    return site["overlay"]["address"].split("/")[0]


def fetch_export(host):
    result = subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", f"admin@{host}", "/export"],
        capture_output=True, text=True, check=True,
    )
    return result.stdout


def normalize(text):
    lines = []
    for line in text.splitlines():
        stripped = SECRET_PARAM_RE.sub("", line)
        if stripped.lstrip().startswith("/snmp community"):
            stripped = SNMP_COMMUNITY_NAME_RE.sub("", stripped)
        stripped = stripped.strip()
        if stripped:
            lines.append(stripped)
    return "\n".join(lines)


def git(*args, check=True):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True, check=check)


def commit_live_export(site_name, export_text, no_commit):
    site_dir = LIVE_DIR / site_name
    site_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M%SZ")
    (site_dir / f"{stamp}.rsc").write_text(export_text)
    (site_dir / "latest.rsc").write_text(export_text)

    if no_commit:
        return
    git("add", str(site_dir))
    result = git("diff", "--cached", "--quiet", check=False)
    if result.returncode != 0:
        git("commit", "-m", f"live export: {site_name} {stamp}")


def check_site(site, no_commit):
    name = site["name"]
    host = overlay_host(site)
    rendered_path = RENDERED_DIR / f"{name}.rsc"
    if not rendered_path.exists():
        print(f"[{name}] SKIP: no rendered/{name}.rsc -- run ./render.py", file=sys.stderr)
        return True

    try:
        export_text = fetch_export(host)
    except subprocess.CalledProcessError as e:
        print(f"[{name}] ERROR: could not reach {host} for /export: {e.stderr}", file=sys.stderr)
        return False

    commit_live_export(name, export_text, no_commit)

    live_norm = normalize(export_text)
    rendered_norm = normalize(rendered_path.read_text())

    if live_norm == rendered_norm:
        print(f"[{name}] OK: no drift")
        return True

    print(f"[{name}] DRIFT DETECTED: live config differs from rendered/{name}.rsc", file=sys.stderr)
    print(f"[{name}] compare live/{name}/latest.rsc against rendered/{name}.rsc and decide: "
          f"adopt into templates, or let the next deploy erase it.", file=sys.stderr)
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--site", help="check only this site")
    parser.add_argument("--no-commit", action="store_true", help="skip git commit, for local testing")
    args = parser.parse_args()

    sites = load_sites()
    if args.site:
        sites = [s for s in sites if s["name"] == args.site]
        if not sites:
            raise SystemExit(f"no site named {args.site!r} in sites.yaml")

    clean = True
    for site in sites:
        clean = check_site(site, args.no_commit) and clean

    if not clean:
        sys.exit(1)


if __name__ == "__main__":
    main()
