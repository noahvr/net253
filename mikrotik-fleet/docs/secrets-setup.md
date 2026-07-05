# Secrets setup (sops + age)

Background and rationale: docs/PLAN.md section 5. This doc is the
mechanical how-to. Read it once, then it's `sops -e`/`sops -d` forever.

Secrets that live here: WireGuard private keys (one per router), break-glass
passwords (one per router), SNMP community strings, PPPoE/ISP credentials,
third-party VPN PSKs. NOT here: engineer SSH private keys (never leave the
engineer's machine — only the *public* key goes in `pubkeys/`), the deploy
credential (lives only on the management host, see below), human-held
secrets like password-manager entries for break-glass passwords' *paper
trail* (the password value itself is still in `secrets.yaml` so a deploy can
assert it — the password manager copy is for a human to read during a 2am
break-glass login).

## One-time setup

1. Install `age` and `sops` on the management host (the only place
   `secrets.yaml` ever gets decrypted).
2. Each engineer with deploy access generates their own age keypair:
   ```
   age-keygen -o ~/.config/sops/age/keys.txt
   ```
   The public key it prints (`age1...`) is not secret — it goes in
   `.sops.yaml`. The private key file never leaves that engineer's machine
   and never goes in git.
3. Create `.sops.yaml` at the repo root (copy `.sops.yaml.example`) listing
   every current engineer's age public key as a recipient for `secrets.yaml`.
4. Generate real values for every token referenced in `sites.yaml` (grep for
   `{{SECRET:` to enumerate them) and put them in a working copy of
   `secrets.yaml` (start from `secrets.yaml.example`), matching this shape:
   ```yaml
   secrets:
     wg_privkey:
       site-a: <real wireguard private key for site-a>
       site-b: <real wireguard private key for site-b>
     break_glass_password:
       site-a: <unique long random password>
       site-b: <unique long random password>
     snmp_community:
       site-a: <random string, not "public">
       site-b: <random string, not "public">
   ```
   Generate WireGuard keypairs with `wg genkey` / `wg pubkey` (the private
   key goes in `secrets.yaml`; the matching public key is NOT secret and
   goes directly in `sites.yaml` as `overlay.peer_public_key` for whichever
   side is the peer — the management host's own WG keypair is the deploy
   credential and lives only on the management host, never in this repo at
   all).
5. Encrypt it in place: `sops --encrypt --in-place secrets.yaml`. Commit the
   result — the values are now `ENC[...]`, the keys (`wg_privkey`, `site-a`,
   etc.) stay readable so PR reviewers can see *what changed* without seeing
   the value.
6. Copy each break-glass password into the shared password manager vault as
   well, labeled by site. `secrets.yaml` is what the router gets asserted
   to; the password manager is what a human reads at 2am.

## Day to day

* Edit secrets: `sops secrets.yaml` (opens decrypted in `$EDITOR`,
  re-encrypts on save). Never hand-edit the `ENC[...]` blob.
* `deploy.py` calls `sops --decrypt secrets.yaml` itself at deploy time —
  you don't need to decrypt it manually for a normal deploy.
* Rotating a value (e.g. after offboarding, see docs/offboarding.md):
  update it via `sops secrets.yaml`, then redeploy every site whose secret
  changed.

## Offboarding an engineer's decrypt access

```
# remove their key from .sops.yaml's recipient list, then:
sops updatekeys secrets.yaml
```
This re-wraps the data key without their age key as a recipient. Their old
clone of the repo can no longer decrypt *new* commits, but they could have
read the values before removal — so also rotate every secret they could
have decrypted (docs/offboarding.md step 4).

## The deploy credential is not a secret in this file

The management host's own SSH key (used to reach routers over the overlay)
and its own WireGuard keypair (used to join the overlay in the first place)
are never stored in `secrets.yaml` or anywhere in git. They live only on
the management host's disk. This is deliberate (docs/PLAN.md section 5) —
it's what keeps deploys human-triggered instead of CI-triggered.
