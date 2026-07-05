# MikroTik Fleet Modernization — Implementation Plan & Context Handoff

Purpose of this document: Complete context for a future Claude instance assisting with implementation. The design phase is DONE. All architectural decisions below were made deliberately with rationale recorded. Do not relitigate them unless the user presents new facts (fleet growth past ~30 devices, new team members, new compliance requirements). The correct posture for the next instance is: build, don't redesign.

## 1. Situation

* Operator: small shop (2–3 people at most), ~10 MikroTik RouterOS devices spread across a county (reference location: Kitsap County, WA area). Sites are remote enough that a bad push = a truck roll.
* Current state: manually configured routers, no version control, no drift detection, presumed shared/ad-hoc credentials, no out-of-band access, no lab. Nothing has been built yet as of July 2026.
* Goal: intent-based, git-versioned configuration management with full-state deployment, drift detection, and survivable failure modes.

## 2. Decisions already made (with rationale — do not reopen)

Rejected: Terraform provider (terraform-routeros). Actively maintained and good software, but requires modeling all config as HCL, per-object imports of existing state, and creates a second source of truth (state file). Half-adoption produces a split-brain router. Wrong fit for this operator's scale and for their stated desire to keep configs readable as whole documents.

Rejected: Ansible (community.routeros). Provides transport (command/api modules), not a declarative resource model. Idempotency is DIY. Fine for procedural jobs (upgrades, cert pushes) but not the config backbone.

Rejected: raw /export diffing in git. No native diff/patch-apply exists in RouterOS; /import of a full export against a live box errors on existing objects and removes nothing. Text diffs can't safely handle position-ordered firewall rules. routeros-diff (adamcharnock) is the closest tool but semi-abandoned and fragile. Export-in-git documents drift after the fact; it prevents nothing.

Chosen: intent → render → full-state deploy.

* Small structured source of truth: `sites.yaml` (per-site facts only: name, loopback, WAN, VLANs/prefixes, peers — target ≤20 lines/site).
* Jinja2 templates (`router.rsc.j2` + role overlays) hold the ~90% of config shared across sites. Templates should be deliberately dumb: minimal logic, no clever macros; computed values belong in YAML as explicit facts.
* `render.py` (~12 lines + secrets pass, see §5) stamps out complete per-site `.rsc` files into `rendered/`, committed to git. PR review reads the RENDERED diff (that's what the router eats), not just the intent diff.
* Deploy = full-state replacement: push rendered .rsc, `/system reset-configuration run-after-reset=<file>`. Reboot per change is accepted. No drift possible by construction; Winbox changes are obliterated on next deploy (feature, not bug).
* Emergency changes: allowed via direct SSH only inside Safe Mode, and must be back-ported to templates same day — enforced by the drift alarm (§6), not by discipline.

## 3. Phased rollout (order is load-bearing; each phase is the safety net for the next)

**Phase 0 — Discovery (days 1–2, touch nothing):**

1. Inventory all 10 boxes: model, RouterOS version, serial, location, credentials holders, and how each is reachable if it stops routing (this column will be mostly empty — that empty column is the real project).
2. Pull `/export` + binary `/system backup` from all boxes; commit exports to a fresh git repo, one directory per site ("before" photo — makes all subsequent change detectable).
3. Read all 10 exports side by side; write down the drift/discrepancy list (mismatched DNS, missing firewall rules, mystery accounts). Half are latent incidents.
4. Normalize the fleet to one RouterOS 7.x long-term release BEFORE templating (10 versions = 10 config dialects). Upgrade one at a time with someone physically nearby.

**Phase 1 — Survivability (week 1, still no config changes):**

5. OOB access per remote box: LTE stick, cheap second router on a separate path, or minimum a management VPN independent of the config being rewritten. Plus a `/system scheduler` watchdog: revert to last-known-good if management is unreachable N minutes after a change window.
6. PROVE recovery: for each site, actually reach the box via OOB and actually restore a binary backup. Untested recovery is a hypothesis.
7. Lab: CHR VMs (free), one per template role, same RouterOS version as fleet. Everything tests here first.

**Phase 2 — Intent layer (week 2):**

8. Take the most-standard router's export; factor into templates. First template version should be embarrassingly close to that export with ~15 variables punched in. Base template: users, logging, NTP, SNMP, firewall skeleton, management binding. Role overlays only if roles genuinely differ.
9. Write `sites.yaml` (ten entries, differences only). A site exceeding ~20 lines means either a genuinely special site or an under-factored template — decide explicitly which.
10. `render.py`; commit intent + rendered together. Use Jinja2 `trim_blocks=True, lstrip_blocks=True` from day one (RouterOS importer is picky about whitespace).
11. Lab validation: netinstall/reset a CHR with each rendered config; verify boot, routing, and — the step everyone skips — management access from a COLD boot (classic self-lockout is a rendered firewall blocking your own SSH, visible only on fresh boot).

**Phase 3 — Convergence (weeks 3–4, one router at a time):**

12. Order fleet by blast radius; least important box becomes the permanent canary.
13. Reconcile canary: diff live export vs rendered; every line either gets adopted into the template (router was right) or conformed away (drift). Slowest and most valuable step in the project.
14. Deploy full-state in a maintenance window with OOB session open; soak several days under real traffic before router #2.
15. Roll through remaining nine, worst-connected last, canary-soak between each. Weeks, not days. Never batch.

**Phase 4 — Steady state:**

16. Change flow: YAML/template edit → PR → review rendered diff → lab CHR boot → canary → fleet.
17. Nightly `/export` from every router auto-committed to a `live/` branch and diffed against `rendered/`; non-empty diff pages someone. This is simultaneously the drift alarm, the emergency-backport enforcer, and (partially) insider detection. It must run on infrastructure not administered solely by the person it's meant to watch.
18. Rebuild drill twice a year: netinstall a CHR/spare from repo alone. Routers must be provably disposable.

Realistic total: 4–6 weeks calendar time alongside a day job, of which the "modern tooling" (steps 8–10) is ~3 days. ~90% of the project is inventory, recovery paths, version normalization, drift reconciliation.

## 4. Auth design (principles kept, machinery dropped)

* Management plane NEVER on untrusted L2/L3 — including remote-site LANs. Native WireGuard overlay between all routers and the management host; SSH/API/Winbox bound to overlay addresses only; input chain drops management from every other interface. This is a template block, not a budget item. No public management, period (MikroTik is a botnet demographic).
* Per-human RouterOS users, SSH keys only, password SSH auth disabled. Accepted downgrade vs. big-shop practice: no SSH certificates in RouterOS, so no short-lived creds — compensated by cheap revocation (delete key from `users.yaml`, redeploy, minutes).
* Deliberately skipped: RADIUS/TACACS+ (machinery without payoff at 10 boxes / 3 admins; adds a lockout-capable dependency). Written down; revisit at ~30 boxes or ~5 admins.
* Break-glass: one local admin per box, unique long random password per box (never shared across boxes), stored in password manager, used never, existence watched by nightly export diff. Must not depend on the WireGuard overlay being healthy.
* Base template disables telnet, ftp, www, api-non-ssl outright; api/rest-api only if consumed, overlay-bound.

## 5. Secrets design

Secret inventory: WireGuard private keys (per router — these ARE the management plane), break-glass passwords, engineer SSH private keys, SNMP strings, PPPoE/ISP creds, third-party VPN PSKs, and the deploy credential. NOT secret (merely private): sites.yaml topology, public keys, firewall logic — keep these reviewable in plaintext.

* Git holds zero plaintext secrets ever, including history (one committed WG key = rotate every peer).
* Human secrets → password manager (1Password/Bitwarden shared vault).
* Machine secrets → sops + age, values-encrypted YAML (`secrets.yaml`): keys readable in diffs, values ENC[...]. Engineer offboarding = remove their age key, re-encrypt, rotate what they could read. Vault-the-product rejected (same reasoning as RADIUS).
* Deploy credential (mgmt host SSH key + WG access to fleet) lives ONLY on the management host. Never in GitHub, never in CI secrets. Deploys are human-triggered, not merge-triggered (keeps review and deploy as two separate controls).
* Two-pass render (resolves the rendered-configs-vs-no-secrets contradiction): pass 1 renders with placeholder tokens (`{{SECRET:wg_key:sitename}}`) → committed to `rendered/`, fully reviewable, zero secrets. Pass 2 runs only on the management host at deploy time, substitutes real values from sops-decrypted file, writes to tmpfs, never committed. ~20 extra lines in render.py.
* Known blind spot: RouterOS /export omits passwords/private keys, so the nightly drift diff CANNOT see credential changes on-box. Compensations: user existence and key fingerprints do appear in exports; full-state deploys re-assert known secrets every push. Do not let the user discover this during an incident.
* Offboarding checklist (write it while hypothetical): delete RouterOS user from YAML → remove age key → re-encrypt → rotate WG keys they held + break-glass entries they could open → redeploy fleet. The credential improvised offboarding always misses is the WireGuard key.

## 6. Repo governance

* Real threat is malicious/negligent MERGE, not repo deletion (deletion is recoverable: distributed clones, GitHub ~90-day soft delete, nightly `git clone --mirror` to the management host).
* Controls, priority order: (1) required PR review on main, no self-merge, no exceptions, reviewers read the RENDERED diff; (2) deploy credential isolation + human-triggered deploys (see §5); (3) drift alarm running where a single admin can't silence it. Branch protection: no force-push, no deletion; repo-delete restricted to org owner.
* Scale honesty: at 2–3 people the realistic adversaries are a phished GitHub account, a stolen laptop, a fat-fingered force-push, and an unrevoked ex-employee — not an anonymous rogue insider. Same mitigations either way; ~30 minutes of setup once the repo exists.

## 7. Emergency operations model

2am outage: SSH in via OOB, Safe Mode on, fix, site up. The pipeline is not the only door; it makes the emergency door safe (Safe Mode = rollback, OOB = reachability, nightly diff = the hand-edit cannot stay secret). The drift alarm stays red until intent matches reality — human then decides: template adopts the fix, or next deploy erases it. The only forbidden state is UNDECIDED drift. Deliberate choice: no auto-revert of emergency fixes.

## 8. Concrete artifacts to build (the actual deliverables)

Repo layout:

```
inventory/          # phase-0 raw exports, one dir per site (before photo)
templates/router.rsc.j2  (+ role overlays if needed)
sites.yaml
secrets.yaml        # sops/age encrypted values
render.py           # two-pass; trim_blocks/lstrip_blocks
rendered/           # pass-1 output, placeholder tokens, committed
live/               # branch: nightly export auto-commits
docs/offboarding.md # 5-line checklist
docs/rebuild.md     # per-site cold rebuild procedure
```

Reference render skeleton (pass 1):

```python
import yaml
from jinja2 import Environment, FileSystemLoader
data = yaml.safe_load(open("sites.yaml"))
env = Environment(loader=FileSystemLoader("templates"),
                  trim_blocks=True, lstrip_blocks=True)
t = env.get_template("router.rsc.j2")
for site in data["sites"]:
    open(f"rendered/{site['name']}.rsc", "w").write(t.render(site=site))
```

Jinja constructs the user now understands: `{{ var }}`, `{% for %}`, `{% if %}`. Most of the template is literal .rsc passthrough. If logic accumulates in templates, push computed values into YAML as explicit facts — dumb templates are debuggable templates.

## 9. Behavioral context for the next instance (read this)

The user is technically competent and asks sharp questions, but exhibited a consistent pattern across the design conversation: five consecutive tool-comparison questions, then three consecutive governance-perimeter questions (auth, GitHub perms, secrets) — all against a system with zero lines written. Each question was individually legitimate; the sequence was sophisticated procrastination. This was named explicitly to them, repeatedly, per their standing request for a brutally honest advisor. They also floated relaxing security "since this is a smaller shop" — the one part of the project that is nearly free — while accepting all the labor-intensive parts; this was called out as drafting a justification rather than making a tradeoff.

Their questions DID mature over the thread (from "which tool" to "how does this fail" to "explain the mechanics"), and the Jinja/YAML explanation landed — they now understand every component end to end. There is no remaining knowledge gap. The remaining risk, stated to them directly, is that the design conversation becomes the artifact instead of the network.

Therefore, next instance:

* Default to producing working artifacts (templates, render.py, watchdog scripts, checklists) over further comparison or design discussion.
* If they ask a fourth governance-flavored question about an unbuilt system, answer it briefly and redirect to Phase 0 step 1. If they open with "should I reconsider Terraform/Ansible," the answer is no absent new facts (§2).
* Honor their standing preference: direct, unflattering, challenge weak reasoning, name avoidance and its opportunity cost — but do it constructively; the goal is the network getting built, not rhetorical wins.
* First useful question to ask them: "Has export #1 landed in a git repo yet?" Everything sequences from that answer.

## 10. Immediate next actions (as of July 2026)

1. `git init`; pull /export + binary backup from all 10 boxes into `inventory/`. (One evening.)
2. Build the fleet inventory table, including the reach-it-when-down column. (Same evening.)
3. Stand up one CHR VM matching the target RouterOS version. (One hour.)
4. Order/stage OOB hardware for remote sites. (This week.)
5. Draft `router.rsc.j2` from the best export + `sites.yaml` with 2 sites → render → boot the CHR from it. (One weekend.)

Everything else in this document is downstream of these five items.

## 11. Implementation status (this repo)

This repo implements the software scaffold from §8: `templates/router.rsc.j2`, `sites.yaml` (two example sites per §10.5), `render.py` (two-pass), `deploy.py` (pass 2 + watchdog arm/disarm), `scripts/drift_check.py` (§3.17), and the docs in §8/§4/§5. It does **not** and cannot perform the physical/organizational work: no real device inventory has been taken, no OOB hardware exists, no CHR lab has been booted, no real WireGuard/age keys have been generated for production use, and nothing has been deployed to a real router. Phase 0 (§3, steps 1–4) is the literal next action and must happen before any of the code here touches a real device. See `README.md` in this directory for what is scaffolded vs. what remains manual/physical.
