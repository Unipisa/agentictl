# Adding Verbs To agentictl

A verb is one declared command that can be sent over SSH, such as `health` or `service-restart`.

## 1. Choose The Mode

Use `readonly` when the verb only observes state.

Use `act` when the verb can change state, install packages, restart services, write files, rotate credentials, or trigger any privileged operation.

## 2. Implement The Verb

Read-only verbs live in `bin/agentictl-readonly`.

Action verbs live in `bin/agentictl-act`.

OpenClaw-side inventory and snapshot helper verbs live in `bin/agentictl-nodes`.

Add a new `case "$cmd" in` branch. Parse arguments explicitly with a `while [[ $# -gt 0 ]]` loop and reject unknown arguments.

Do not pass untrusted text to `sh -c`, `eval`, unquoted command strings, or arbitrary command passthroughs.

## 3. Validate Arguments

Every argument needs a narrow validator. Prefer allowlists and exact formats over broad regexes.

Examples:

```bash
[[ "$unit" =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || fail 65 "invalid unit"
[[ "$pkg" =~ ^[a-zA-Z0-9_.+:-]+$ ]] || fail 65 "invalid package name"
```

## 4. Add Policy For Mutating Verbs

If the verb mutates state, add or reuse a policy variable in `config/policy.env.example`.

Examples:

```bash
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="htop jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml"
```

Load and check the policy before any privileged command runs.

## 5. Enforce Dry Run And Execute

Mutating verbs must parse both flags:

```bash
--dry-run
--execute
```

The implementation must return a preview for `--dry-run` and call `require_execute_flag` before changing state.

## 6. Expose The Verb In Capabilities

Update the `capabilities` output for the relevant mode so agents can discover the verb.

## 7. Add Dispatcher Permission

Update `bin/agentictl` so the selected mode can dispatch the new verb:

```bash
readonly:my-diagnostic)
act:my-action)
```

If the verb is not added here, SSH calls will be rejected even if the helper script implements it.

## 8. Update The Skill

Update `skills/agentictl-ssh/SKILL.md` with:

- When to use the verb.
- Required arguments.
- Whether it is read-only or mutating.
- The dry-run and execute sequence for mutating verbs.

## 9. Add Docker SSH Tests

Update `tests/docker/scripts/runner.sh`.

Each mutating verb should have tests for:

- Allowed dry-run.
- Policy denial.
- Unsafe argument rejection where relevant.
- Execute path using the Docker fake or fixture.

Filesystem read verbs should have tests for:

- Allowed list/stat/read under an allowed root.
- Allowed log read under `ALLOW_LOG_ROOTS`.
- Denial of a sensitive path under `DENY_READ_PATHS`.
- Limit handling where practical.

Inventory read verbs such as `package-list` and `kernel-modules` should have tests for:

- Stable JSON output.
- Limit handling.
- No mutation of node state.

Local helper verbs such as `role-set` and `role-show` should have tests for:

- Local persistence under the workspace.
- JSON output that exposes the saved path.
- Reuse by later software-stack reasoning.

## Example Checklist

For a new `service-reload` action:

- Add `service-reload` branch in `bin/agentictl-act`.
- Reuse `ALLOW_SERVICE_RESTART` or add `ALLOW_SERVICE_RELOAD`.
- Add `service-reload` to `act` capabilities.
- Add `act:service-reload` in `bin/agentictl`.
- Add skill examples.
- Add Docker tests for dry-run, denied unit, and execute.
