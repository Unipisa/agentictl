# Adding Module-Backed Verbs To agentictl

A verb is one declared command that can be sent over SSH, such as `health` or `service-restart`.

## 1. Choose The Mode

Use `readonly` when the verb only observes state.

Use `act` when the verb can change state, install packages, restart services, write files, rotate credentials, or trigger any privileged operation.

## 2. Choose Or Create A Module

Built-in verbs live in modules under `modules/`.

Current module families:

- `linux-core`: basic diagnostics.
- `linux-systemd`: systemd services and journal.
- `linux-packages`: package-manager inventory and actions.
- `linux-kernel`: kernel diagnostics.
- `linux-files`: policy-constrained file and log reads.
- `linux-config`: allowlisted config staging and apply.

Application-specific verbs should live in their own module, for example `app-yourls-classic` or `app-yourls-container`.

Each module must have a `module.env` manifest:

```bash
AGENTICTL_MODULE_ID="app.yourls.classic"
AGENTICTL_MODULE_LABEL="YOURLS classic install"
AGENTICTL_MODULE_READONLY_VERBS="yourls-status yourls-config-summary"
AGENTICTL_MODULE_ACT_VERBS="yourls-cache-clear"
```

The module ID should be stable and namespaced. The SSH verbs should remain short, explicit, and mode-specific.

## 3. Implement The Verb

Read-only module handlers live in `modules/<module>/readonly.sh`.

Action module handlers live in `modules/<module>/act.sh`.

OpenClaw-side inventory and snapshot helper verbs live in `bin/agentictl-nodes`.

Add or update `agentictl_module_dispatch()`. Parse arguments explicitly with a `while [[ $# -gt 0 ]]` loop and reject unknown arguments.

Do not pass untrusted text to `sh -c`, `eval`, unquoted command strings, or arbitrary command passthroughs.

## 4. Validate Arguments

Every argument needs a narrow validator. Prefer allowlists and exact formats over broad regexes.

Examples:

```bash
[[ "$unit" =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || fail 65 "invalid unit"
[[ "$pkg" =~ ^[a-zA-Z0-9_.+:-]+$ ]] || fail 65 "invalid package name"
```

## 5. Add Policy For Mutating Verbs

If the verb mutates state, add or reuse a policy variable in `config/policy.env.example`.

Examples:

```bash
ALLOW_SERVICE_RESTART="ollama.service agentictl-agent.service"
ALLOW_PACKAGE_INSTALL="htop jq"
ALLOW_CONFIG_TARGETS="/etc/agentictl/runtime.yaml"
```

Load and check the policy before any privileged command runs.

## 6. Enforce Dry Run And Execute

Mutating verbs must parse both flags:

```bash
--dry-run
--execute
```

The implementation must return a preview for `--dry-run` and call `require_execute_flag` before changing state.

When the verb is used through the OpenClaw skill, `--execute` must also go through the local batch approval workflow:

- Create an approval plan for the normalized command and target aliases.
- Dry-run the plan.
- Require one interactive human approval for the whole plan.
- Execute with the approved plan id and consume each target once.

## 7. Expose The Verb In Capabilities

Update the module's `module.env` so the generated `capabilities` output exposes the verb in both the flat command list and the module metadata.

## 8. Dispatcher Permission

Do not add hardcoded command cases to `bin/agentictl`, `bin/agentictl-readonly`, or `bin/agentictl-act`. The dispatcher permission comes from the module manifest. If the verb is not listed in `AGENTICTL_MODULE_READONLY_VERBS` or `AGENTICTL_MODULE_ACT_VERBS`, SSH calls will be rejected even if the handler implements it.

## 9. Update The Skill

Update `skills/agentictl-ssh/SKILL.md` with:

- When to use the verb.
- Required arguments.
- Whether it is read-only or mutating.
- The dry-run, batch approval, and execute sequence for mutating verbs.

## 10. Add Docker SSH Tests

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

Inventory read verbs such as `package-list`, `package-upgrades`, and `kernel-modules` should have tests for:

- Stable JSON output.
- Limit handling.
- No mutation of node state.

Local helper verbs such as `role-set` and `role-show` should have tests for:

- Local persistence under the workspace.
- JSON output that exposes the saved path.
- Reuse by later software-stack reasoning.

When changing package-manager support:

- Update `package-list`, `package-upgrades`, `package-install`, and `package-upgrade` when the platform has distinct inventory and install commands.
- Keep package names constrained by the existing package-name validator and the relevant policy variable: `ALLOW_PACKAGE_INSTALL` or `ALLOW_PACKAGE_UPGRADE`.
- Require an explicit policy flag for full package upgrades.
- Report the selected package manager in dry-run and execute JSON.
- Add local tests for explicit manager selection and Docker SSH tests for the default manager in the test image.

## Example Checklist

For a new `service-reload` action:

- Add `service-reload` to `modules/linux-systemd/module.env`.
- Add the `act:service-reload` branch in `modules/linux-systemd/act.sh`.
- Reuse `ALLOW_SERVICE_RESTART` or add `ALLOW_SERVICE_RELOAD`.
- Add skill examples.
- Add Docker tests for dry-run, denied unit, and execute.

For a new YOURLS classic module:

- Add `modules/app-yourls-classic/module.env`.
- Add `readonly.sh` with verbs such as `yourls-status` and `yourls-config-summary`.
- Add `act.sh` only for actions that can be safely allowlisted, such as `yourls-cache-clear`.
- Add policy keys such as `YOURLS_ROOT` and `ALLOW_YOURLS_CACHE_CLEAR`.
- Add Docker or fixture tests for both classic filesystem installs and denied unsafe paths.
