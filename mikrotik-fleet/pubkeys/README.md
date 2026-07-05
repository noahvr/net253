# pubkeys/

One file per admin, named to match `admins[].ssh_public_key_file` in
`sites.yaml`. These are SSH **public** keys — not secret, safe to commit in
plaintext (docs/PLAN.md section 5). `deploy.py` scp's the relevant file(s)
to a router alongside its rendered config so `/user ssh-keys import` has
something to read.

`noah.pub` in this directory is a placeholder. Replace it with a real
public key before deploying anything for real, and add one file per admin
as the team grows.
