# agentictl Requirements

This folder captures the project requirements in Markdown so the GitHub repository has a clear public contract.

Documents:

- `functional.md`: supported modes, verbs, outputs, and policy behavior.
- `security.md`: confinement and threat-model requirements.
- `verbs.md`: how to add new verbs to `agentictl`.
- `packaging.md`: installer and release package requirements.
- `testing.md`: local and Docker test requirements.
- `github.md`: repository-readiness requirements for publishing.

These requirements are intentionally practical. A pull request that adds operational surface area should update the relevant requirement file and the Docker SSH test suite.
