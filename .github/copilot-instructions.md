# Copilot Instructions for pluto (already bootstrapped — phases below are done)

Start with `AGENTS.md`, then load skills by task (index: `.agents/skills/README.md`,
router: `finpilot-router`):
- Containerfile / Justfile / `build/*.sh` → `finpilot-build`
- GitHub Actions / Renovate → `finpilot-ci`
- Packages (dnf5 layers, Brewfiles, Flatpaks, ujust) → `finpilot-packages`, `finpilot-custom`
- New work → `finpilot-overview`, then the domain skill, then `finpilot-pr-checklist`
- Branch strategy, commit format, pre-commit checklist → `AGENTS.md` (normative)

For issue and PR workflow, use the shared [label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Clankers only transports Hive assignments, and `ublue-os/*` is read-only.
