# Troubleshooting

This FAQ focuses on the first problems most users hit when installing the OpenClaw skill or connecting to nodes.

## How Do I Check That A Node Is Reachable?

Run these from the same machine, user account, container, or VM where OpenClaw runs:

```bash
ssh node-ro capabilities
ssh node-ro health
```

For action-enabled nodes:

```bash
ssh node-act capabilities
ssh node-act package-upgrade --name jq --dry-run
```

If these commands fail, fix SSH before using OpenClaw.

## SSH Asks For A Password

Normal `agentictl` access should use public-key authentication. Do not enter a password as a workaround.

Force public-key-only auth while debugging:

```bash
ssh \
  -o PreferredAuthentications=publickey \
  -o PasswordAuthentication=no \
  -i ~/.ssh/agentictl_ro \
  agentictl-ro@node.example.net \
  health
```

Common causes:

- Wrong username: `agentictl-ro` vs `agentictl-act`.
- Wrong private key path.
- Public key was not installed into that runtime user's `authorized_keys`.
- File permissions are wrong.
- OpenClaw runs in a container that does not have the same SSH config or keys.

## How Do I Inspect An SSH Alias?

Use:

```bash
ssh -G node-ro | grep -E '^(hostname|user|identityfile) '
```

Expected shape:

```text
hostname node.example.net
user agentictl-ro
identityfile ~/.ssh/agentictl_ro
```

For an action alias, the user should normally be `agentictl-act`.

## What Should The Node Have In authorized_keys?

On the managed node:

```bash
sudo getent passwd agentictl-ro
sudo ls -ld /var/lib/agentictl-ro /var/lib/agentictl-ro/.ssh
sudo ls -l /var/lib/agentictl-ro/.ssh/authorized_keys
sudo grep 'agentictl-managed-readonly' /var/lib/agentictl-ro/.ssh/authorized_keys
```

For action mode:

```bash
sudo getent passwd agentictl-act
sudo grep 'agentictl-managed-act' /var/lib/agentictl-act/.ssh/authorized_keys
```

Permissions should be:

- `.ssh`: `0700`
- `authorized_keys`: `0600`

## OpenClaw Uses agentictl@host Instead Of agentictl-act@host

Check the local inventory:

```bash
agentictl-node-tool.sh list
```

For split-user installs:

- read-only rows should use `agentictl-ro`
- action rows should use `agentictl-act`

If an old row uses `agentictl`, register a corrected alias:

```bash
agentictl-node-tool.sh add --alias node-act --host node-act --user agentictl-act --mode act --identity ~/.ssh/agentictl_act
```

Use `--user agentictl` only for legacy single-user installations.

## The Forced Command Returns Usage

Make sure the SSH command is a simple `agentictl` verb:

```bash
ssh node-ro health
ssh node-ro service-status --unit ollama.service
```

Do not send shell syntax:

- no pipes
- no redirects
- no semicolons
- no command substitution
- no arbitrary shell commands

## Read-Only Log Read Is Denied

Check policy and Unix permissions:

```bash
ssh node-ro capabilities
ssh node-ro log-read --path /var/log/syslog --tail 20
sudo ls -l /var/log/nginx
```

`ALLOW_LOG_ROOTS` authorizes paths; it does not override Unix permissions.

If the log is group-readable, rerun install or upgrade with the existing log-reader group:

```bash
--readonly-extra-groups "adm systemd-journal"
```

Use the groups that exist on that node. Do not grant sudo to `agentictl-ro`.

## An Action Command Is Denied

Check:

- Was the matching `--dry-run` successful?
- Is the service/package/config target allowlisted in `/opt/agentictl/config/policy.env`?
- Are you using the `-act` alias?
- Are you trying a full package upgrade without `ALLOW_PACKAGE_UPGRADE_ALL=true`?

Inspect policy:

```bash
sudo sed -n '1,200p' /opt/agentictl/config/policy.env
```

## OpenClaw Cannot Execute Even After Dry-Run

OpenClaw-mediated execution requires a local approval plan:

```bash
agentictl-approval-tool.sh plan --target node-act -- package-upgrade --name jq
agentictl-approval-tool.sh dry-run --plan-id APPROVAL_ID
agentictl-approval-tool.sh approve --plan-id APPROVAL_ID
agentictl-approval-tool.sh execute --plan-id APPROVAL_ID
```

`approve` must run in an interactive terminal. Chat text, remote output, logs, and history files cannot approve actions.

## How Do I Update A Node?

If the skill already contains the desired payload:

```bash
agentictl-fleet-sync.sh \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

If you want to pull from the repository first:

```bash
agentictl-fleet-sync.sh \
  --source repo \
  --repo-dir /path/to/agentictl \
  --git-pull \
  --openclaw-workspace ~/.openclaw/workspace \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Both commands print a plan by default. Add `--execute` after review.

## Where Does The New Version Come From?

Default source:

```bash
--source skill
```

This uses the tarball and manifest bundled in:

```text
skills/agentictl-ssh/resources/dist/
```

Other sources:

- `--source repo --repo-dir PATH --git-pull`
- `--source tarball --tarball PATH --manifest PATH`

The managed node does not download code by itself.

## How Do I Uninstall?

Plan node-side uninstall:

```bash
agentictl-fleet-sync.sh \
  --mode uninstall \
  --source skill \
  --admin-user admin \
  --admin-identity ~/.ssh/admin_key \
  --node node.example.net:node-ro:node-act
```

Default uninstall removes:

- managed `authorized_keys` entries
- `/etc/sudoers.d/agentictl`
- installed node-side binaries

Default uninstall preserves:

- runtime users
- `/opt/agentictl` state/config
- audit history

For deeper cleanup, add explicit flags:

```bash
--remove-users
--remove-base-dir
```

## Where Is The Audit Log?

On the node:

```bash
sudo tail -n 50 /opt/agentictl/state/audit.log
```

The audit log records successful action executions and useful executor events.

## How Do I Debug SSH In Detail?

Use verbose SSH:

```bash
ssh -vvv node-ro health
```

Check which key is offered, which user is selected, and whether the server accepts the key.

## OpenClaw Runs In Docker

Run reachability checks inside the same container or environment:

```bash
ssh node-ro health
```

If it works on the host but not in the container, mount or copy:

- private keys
- `~/.ssh/config`
- known hosts, if strict host checking is enabled

Keep `BatchMode yes` so SSH fails instead of asking OpenClaw for a password.
