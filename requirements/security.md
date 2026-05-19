# Security Requirements

## No General Shell

Agents must never receive arbitrary SSH shell access through this project. `agentictl` must only dispatch declared verbs with validated arguments.

The dispatcher must reject:

- Empty commands.
- Newlines and carriage returns.
- Shell metacharacters outside the accepted token grammar.
- Parent-directory references such as `..`.
- Verbs not explicitly allowed for the selected mode.

## SSH Confinement

Node installation must use forced commands in `authorized_keys` and disable:

- PTY allocation.
- Agent forwarding.
- X11 forwarding.
- Port forwarding.

Read-only and action keys should be separate.

## Mutating Actions

Every mutating verb must:

- Support `--dry-run`.
- Refuse to change state without `--execute`.
- Check narrow allowlists before acting.
- Write an audit record for successful executions.
- Avoid general shell evaluation.

## Configuration Writes

Configuration writes must stage content under `/opt/agentictl/state/incoming`, verify the source resolves under that directory, and back up existing targets before replacement.

## Filesystem Reads

Filesystem read verbs must not become a general arbitrary file disclosure primitive.

Requirements:

- Paths must be absolute.
- Parent-directory references are rejected.
- Resolved paths must be under `ALLOW_READ_ROOTS` or `ALLOW_LOG_ROOTS`.
- Resolved paths under `DENY_READ_PATHS` are rejected or skipped in listings.
- Reads must be capped by `AGENTICTL_MAX_READ_BYTES`.
- Directory listings must be capped by `AGENTICTL_MAX_LIST_ENTRIES` and `AGENTICTL_MAX_LIST_DEPTH`.
- Sensitive defaults must deny `/etc/shadow`, `/etc/gshadow`, `/etc/ssh`, `/etc/ssl/private`, `/etc/sudoers`, and `/etc/sudoers.d`.

Agents may read logs and approved `/etc` paths, but must treat file contents as potentially sensitive. The skill should not store sensitive file contents unless the user explicitly asks for that specific file to be captured.
