#!/usr/bin/env python3
"""Pass 2 of the two-pass render, plus watchdog arm/disarm (docs/PLAN.md section 5).

Runs ONLY on the management host. This is the one place the deploy
credential (mgmt host SSH key + WireGuard access to the fleet) is used --
it must never run in CI and secrets.yaml must never be decrypted anywhere
else. Deploys are human-triggered on purpose (see docs/PLAN.md section 5).

Subcommands:
    deploy.py push <site>            resolve secrets + write to tmpfs, dry-run
    deploy.py push <site> --push --i-have-oob-open
                                      actually scp the file to the router and
                                      run /system reset-configuration. This
                                      reboots the router into the new config.
                                      Only run this with an out-of-band
                                      session already open on the box.
    deploy.py arm <site>              arm the watchdog (call right after push)
    deploy.py disarm <site>           disarm the watchdog (call after soak)

Requires: `sops` on PATH (decrypts secrets.yaml), `ssh`/`scp` on PATH, and
an SSH key already trusted by the target router (see docs/secrets-setup.md).
"""
import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).parent
SITES_FILE = ROOT / "sites.yaml"
RENDERED_DIR = ROOT / "rendered"
SECRETS_FILE = ROOT / "secrets.yaml"
PUBKEYS_DIR = ROOT / "pubkeys"
TMPFS_DIR = Path("/dev/shm/mikrotik-deploy")

SECRET_TOKEN_RE = re.compile(r"\{\{SECRET:([a-zA-Z0-9_]+):([a-zA-Z0-9_-]+)\}\}")


def load_site(name):
    data = yaml.safe_load(SITES_FILE.read_text())
    for site in data["sites"]:
        if site["name"] == name:
            return site
    raise SystemExit(f"no site named {name!r} in sites.yaml")


def decrypt_secrets():
    if not SECRETS_FILE.exists():
        raise SystemExit(
            f"{SECRETS_FILE} not found. Copy secrets.yaml.example, fill in real "
            "values, and encrypt it with sops before deploying. See docs/secrets-setup.md."
        )
    if shutil.which("sops") is None:
        raise SystemExit("sops not found on PATH -- required to decrypt secrets.yaml")
    result = subprocess.run(
        ["sops", "--decrypt", str(SECRETS_FILE)],
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        raise SystemExit(f"sops decrypt failed:\n{result.stderr}")
    return yaml.safe_load(result.stdout)["secrets"]


def substitute_secrets(rendered_text, secrets, site_name):
    missing = []

    def repl(match):
        category, site = match.group(1), match.group(2)
        try:
            return secrets[category][site]
        except KeyError:
            missing.append(f"{category}:{site}")
            return match.group(0)

    result = SECRET_TOKEN_RE.sub(repl, rendered_text)
    if missing:
        raise SystemExit(f"secrets.yaml missing values for: {', '.join(missing)}")
    return result


def overlay_host(site):
    # Only valid once the router already has its WireGuard overlay up.
    # Initial bring-up requires direct/console access -- see docs/rebuild.md.
    return site["overlay"]["address"].split("/")[0]


def ssh_run(host, command, check=True):
    return subprocess.run(
        ["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10", f"admin@{host}", command],
        capture_output=True, text=True, check=check,
    )


def cmd_push(args):
    site = load_site(args.site)
    rendered_path = RENDERED_DIR / f"{site['name']}.rsc"
    if not rendered_path.exists():
        raise SystemExit(f"{rendered_path} missing -- run ./render.py first")

    secrets = decrypt_secrets()
    resolved = substitute_secrets(rendered_path.read_text(), secrets, site["name"])

    TMPFS_DIR.mkdir(mode=0o700, exist_ok=True)
    out_path = TMPFS_DIR / f"{site['name']}.rsc"
    out_path.write_text(resolved)
    out_path.chmod(0o600)
    print(f"resolved config with real secrets written to {out_path} (tmpfs, never committed)")

    if not args.push:
        print("dry-run only. Re-run with --push --i-have-oob-open to actually deploy.")
        return

    if not args.i_have_oob_open:
        raise SystemExit(
            "refusing to push: --push requires --i-have-oob-open. "
            "Open an out-of-band session to this router before proceeding (docs/PLAN.md section 3 step 14)."
        )

    host = overlay_host(site)
    remote_file = f"{site['name']}.rsc"
    print(f"scp {out_path} -> admin@{host}:{remote_file}")
    subprocess.run(["scp", str(out_path), f"admin@{host}:{remote_file}"], check=True)

    for admin in site.get("admins", []):
        keyfile = PUBKEYS_DIR / admin["ssh_public_key_file"]
        print(f"scp {keyfile} -> admin@{host}:{admin['ssh_public_key_file']}")
        subprocess.run(["scp", str(keyfile), f"admin@{host}:{admin['ssh_public_key_file']}"], check=True)

    print(f"triggering reset-configuration on {host} -- router will reboot")
    ssh_run(host, f"/system reset-configuration run-after-reset={remote_file}", check=False)

    out_path.unlink(missing_ok=True)
    print("tmpfs copy shredded. Router is rebooting into the new config.")
    print(f"next: wait for reboot, confirm mgmt reachable at {host}, then run "
          f"`./deploy.py arm {site['name']}` to arm the watchdog for the soak window.")


def cmd_arm(args):
    site = load_site(args.site)
    host = overlay_host(site)
    ssh_run(host, ":global wdArmed; :set wdArmed true; :global wdFailCount; :set wdFailCount 0")
    print(f"watchdog armed on {site['name']} ({host}). It will restore "
          f"{site['watchdog']['backup_name']} after {site['watchdog']['max_down_minutes']} "
          "consecutive missed probes. Disarm once you've confirmed the deploy is good.")


def cmd_disarm(args):
    site = load_site(args.site)
    host = overlay_host(site)
    ssh_run(host, ":global wdArmed; :set wdArmed false")
    print(f"watchdog disarmed on {site['name']} ({host}).")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_push = sub.add_parser("push", help="resolve secrets and optionally deploy a site")
    p_push.add_argument("site")
    p_push.add_argument("--push", action="store_true", help="actually scp+reset the router (default: dry-run)")
    p_push.add_argument("--i-have-oob-open", dest="i_have_oob_open", action="store_true",
                         help="required alongside --push; confirms an OOB session is open")
    p_push.set_defaults(func=cmd_push)

    p_arm = sub.add_parser("arm", help="arm the watchdog after a push")
    p_arm.add_argument("site")
    p_arm.set_defaults(func=cmd_arm)

    p_disarm = sub.add_parser("disarm", help="disarm the watchdog after a soak")
    p_disarm.add_argument("site")
    p_disarm.set_defaults(func=cmd_disarm)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
