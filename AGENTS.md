# Instructions for Codex

This repository implements agentictl, a safe SSH executor for agent-managed Linux nodes.

Rules:
- Preserve strict separation between read-only diagnostics and mutating actions.
- Never add arbitrary shell execution or passthrough SSH commands.
- All mutating operations must support `--dry-run` and require explicit `--execute`.
- All mutating operations must check allowlists from `config/policy.env`.
- Configuration writes must create backups before replacement.
- Prefer JSON or stable machine-readable output where practical.
- Add tests for validation, allowlist behavior, and failure paths when adding capabilities.
- If a requested change requires changing, relaxing, extending, or reinterpreting project requirements, ask the user for explicit approval before implementing it.
- When approved changes affect requirements, update the relevant files under `requirements/` and keep user-facing documentation such as `README.md`, `docs/`, and skills in sync.
