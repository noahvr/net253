# pubkeys/

One file per admin, named to match `admins[].ssh_public_key_file` in
`sites.yaml`. These are SSH **public** keys — not secret, safe to commit in
plaintext (docs/PLAN.md section 5). `deploy.py` scp's the relevant file(s)
to a router alongside its rendered config so `/user ssh-keys import` has
something to read.

`drift-ro.pub` is the drift collector's key (see `drift_ro:` in
`sites.yaml`): the nightly `scripts/drift_check.py` pull authenticates as a
dedicated read-only RouterOS user, not the deploy credential, so a stolen
collector key yields `/export` access and nothing more. Generate the
keypair on the collector host; only the public half goes here.

`noah.pub` and `drift-ro.pub` in this directory are placeholders. Replace
them with real public keys before deploying anything for real, and add one
file per admin as the team grows.
