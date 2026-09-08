# CONTRIBUTING

Thanks for helping out!

Neptuno is a personal GNOME and Niri/DMS bootc image (Silverblue base). Small fixes
and chores may push directly to `main`; massive changes and feature adds
go via PR — see AGENTS.md Branch Strategy, which is normative for humans
and agents alike.

Upstream-shared pieces (desktop config, setup framework) live in
[@projectbluefin/common](https://github.com/projectbluefin/common) — change
something there only if every downstream should get it; keep
neptuno-specific ownership local.

Use the shared [label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md):
humans triage and approve, and agents work only on assigned or
`3-clanker-queue` issues. Clankers only transports Hive assignments; keep
template-specific ownership local.
