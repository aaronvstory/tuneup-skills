# TuneUp

Health-check skills for coding agents, one for Windows and one for macOS.
They work with Claude Code, Codex, and other agents.

Each skill scans first, writes a local HTML report, and then offers fixes.
It never deletes anything without an explicit pick from the user.

| Folder | For | What it checks |
|---|---|---|
| `wintuneup/` | Windows | Heat, speed, memory, startup, tasks, security, network, every GB of disk |
| `mactuneup/` | macOS | Heat, speed, memory, login items, security, network, disk |

## Install

Clone the repo once. A link keeps the skill current, so `git pull` is the only update step.

**macOS, Claude Code**

```bash
git clone https://github.com/aaronvstory/tuneup-skills.git ~/tuneup-skills
ln -s ~/tuneup-skills/mactuneup ~/.claude/skills/mactuneup
```

**Windows, Claude Code**

```powershell
git clone https://github.com/aaronvstory/tuneup-skills.git "$env:USERPROFILE\tuneup-skills"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.claude\skills\wintuneup" -Target "$env:USERPROFILE\tuneup-skills\wintuneup"
```

**Codex and other agents**

Clone the repo, then tell the agent:

> Read `tuneup-skills/wintuneup/SKILL.md` and follow it.

On a Mac, use `mactuneup` in that path.

## Update

```bash
git -C ~/tuneup-skills pull
```

## Use

In Claude Code, run `/wintuneup` or `/mactuneup`. You can also say "why is my PC slow".

See `INSTALL.md` in each folder for the full flow and safety rules.

## What stays out of this repo

Reports and generated `apply` scripts describe one machine. Git ignores them.
