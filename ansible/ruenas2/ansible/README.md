# TrueNAS SCALE deployment playbook

Declaratively provisions a TrueNAS SCALE server end-to-end over its HTTPS REST
API: **groups → users → (encrypted) datasets → POSIX permissions → SMB + NFS
shares → services**. Idempotent — safe to re-run; it only creates what's
missing.

The playbook runs on the **control node** (your laptop / CI) and talks to the
NAS over the API. It does **not** SSH into TrueNAS.

## Layout

| File | Purpose |
|------|---------|
| `deploy-truenas.yml` | Main playbook (orchestrates the task files) |
| `inventory.yml` | Runs locally (`connection: local`) |
| `group_vars/all/vars.yml` | **What to build** — groups, users, datasets, shares |
| `group_vars/all/vault.yml` | **Secrets** — API key, passphrases, passwords (encrypted, git-ignored) |
| `tasks/*.yml` | One file per entity type |

## One-time setup

1. **Create an API key** in TrueNAS: avatar (top-right) → *API Keys* → *Add*.
2. **Create and encrypt the vault:**
   ```bash
   cd truenas/ansible
   cp group_vars/all/vault.yml.example group_vars/all/vault.yml
   # edit real values:
   ${EDITOR:-vi} group_vars/all/vault.yml
   ansible-vault encrypt group_vars/all/vault.yml
   ```
3. **Describe your NAS** by editing `group_vars/all/vars.yml`
   (`truenas_api_url`, `truenas_pool`, and the groups/users/datasets/shares
   lists). Every encrypted dataset needs a matching entry in
   `truenas_dataset_passphrases`, and every user a matching entry in
   `truenas_user_passwords`.

## Run

```bash
cd truenas/ansible

# Everything
ansible-playbook deploy-truenas.yml --ask-vault-pass

# Just one stage (tags: preflight, groups, users, datasets,
#                 permissions, shares, smb, nfs, services)
ansible-playbook deploy-truenas.yml --ask-vault-pass --tags datasets

# Preview (note: --check can't fully simulate API POSTs, but preflight +
# existence checks run and show what's already there)
ansible-playbook deploy-truenas.yml --ask-vault-pass --check
```

Requires only `ansible-core` on the control node (uses `ansible.builtin.uri`;
no external collection). To avoid typing the vault password each run, put it in
`.vault_pass` (git-ignored) and set `vault_password_file` in `ansible.cfg`.

## How encryption works

Datasets with `encrypted: true` are created with
`encryption_options.passphrase` (AES-256-GCM by default). The passphrase is
read from the vault by `passphrase_key` (falling back to the dataset name).
Creation tasks for encrypted datasets run with `no_log` so the passphrase never
appears in output.

To **unlock** encrypted datasets after a reboot you still enter the passphrase
in the UI (or via `pool.dataset.unlock`); this playbook provisions them, it
does not auto-unlock on boot (that would require storing the key on the NAS).

## Idempotency & safety

- Groups/users/SMB shares are matched by name, datasets by id, NFS shares by
  path — existing objects are skipped, not modified. To change an existing
  object, edit it in the UI or extend the relevant task with a `PUT`.
- Permissions **are** re-applied every run (cheap and self-correcting). Set
  `recursive: true` on a dataset only when you want ownership pushed down into
  existing children.
- The playbook aborts in `pre_tasks` if the vault/API key is still the
  placeholder, and preflight fails fast if the pool doesn't exist.

## Version notes (SCALE moves fast)

- Built against the **REST v2.0 API**, which is present through Electric Eel
  (24.10). TrueNAS is migrating to a JSON-RPC 2.0 **WebSocket** API and has
  flagged REST for eventual removal — if a future release drops it, the same
  logic ports to `midclt call` over SSH or the WS client.
- `sharing.smb` `purpose` values were reworked in newer releases. If a share
  POST is rejected on the `purpose` field, set a valid value per your version
  in `truenas_smb_shares[].purpose` (default here is `DEFAULT_SHARE`).
- NFS matching assumes the modern single-`path` share object; the task also
  tolerates the older `paths` list when detecting duplicates.
