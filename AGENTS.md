# AGENTS.md

Working notes for agents in this repository. `overview` maps how the image is
assembled and says which skill covers what; the procedures live under
`.agents/skills/`. Neptuno's delta is in `.agents/skills/neptuno`.

## Gates

These hold for every change:

- **Conventional Commits** — `<type>[scope]: <description>`.
- **Validate before committing.** `just lint` shellchecks every shell
  script, `just check` verifies Justfile formatting, `just test-unit` runs the
  bats suite, and `just validate-flatpaks` checks Flathub IDs. With a built
  image, `just rechunk` and `just test-image` run what CI runs on it. The
  `required` status check on a pull request covers all of it plus a boot test.
- **Confirm before pushing** — show the diff and wait.
- **Declare, then enable.** Packages and units belong in
  `build/packages/*.toml`. `just test-unit` includes the manifest contract; a
  unit enabled outside a manifest fails the image build in `90-cleanup.sh`.
- **Never reintroduce** a build-time `flatpak remote-add`, `systemctl
  preset-all`, or a `/dev/null` unit mask. See `.agents/skills/neptuno`.

## Branches and releases

One branch. A pull request into `main` builds and tests the image without
publishing; a merge to `main` (and the daily rebuild) publishes `:latest` and
`:45.YYYYMMDD` once the digest is signed and verified. Renovate automerges
behind the same `required` check. `.agents/skills/ci` has the details.

## Pull request comments

One comment per PR event; fold new findings into the existing one. Report what
ran, whether it passed, and what blocked — nothing else. When the only finding
is "tests pass", post nothing. Mention someone only to ask for a specific
action, and do it inside the combined comment.

## Attribution

End every commit with:

    Assisted-by: <Model> via <Tool>

## Self-improvement

Ship the work and update the owning skill in the same PR, not a follow-up. A
skill is the home for durable learning; a changelog, a session note, or an
"append here" section is not. When a workaround or convention surprised you,
the next agent needs it.

## Ownership

Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Keep changes to this repository: `ublue-os/*` is read-only. The shared
lifecycle and labels are in
[projectbluefin/common's label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
