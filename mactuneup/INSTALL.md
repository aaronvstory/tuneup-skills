# Install `/mactuneup`

A Claude Code skill that health-checks a Mac — performance, memory, startup junk left by
uninstalled apps, network, disk, audio, DNS — and delivers a polished HTML report. It
scans and reports first, and changes nothing until you pick items off a menu.

## Install

Unzip, then drop the `mactuneup` folder into your Claude Code skills directory:

```bash
mkdir -p ~/.claude/skills
mv mactuneup ~/.claude/skills/
chmod +x ~/.claude/skills/mactuneup/*.sh
```

Restart Claude Code (or start a new session) and it'll pick the skill up.

## Other agents

Codex, ChatGPT agents, and others do not need a special folder. Put `mactuneup` anywhere and say:

> Read `mactuneup/SKILL.md` and follow it.

## Use

```
/mactuneup
```

Or just say "tune up this mac" / "why is my mac slow".

## What happens

1. **Baseline** — one measurement captures the "before" numbers.
2. **Read-only scan** — ~30 seconds, changes nothing, no password.
3. **Verification** — findings are confirmed before they're reported. Several of the
   scanner's raw checks produce false positives; the skill knows which and re-tests them.
4. **A report** — an HTML file saved to `~/Downloads/Claude-MacTuneUp/` and opened in
   your browser. **Nothing is uploaded anywhere**; it's a local file describing your
   machine, and it stays on your machine.
   It covers:
   - **About This Mac** — model, chip, macOS, plus how many apps, login items, launch
     agents and kernel extensions you're carrying
   - **This Mac's Networking** — IPs, DNS, VPN stacks, tunnels, public exit
   - **Before & after** charts and scoreboard
   - **Findings**, **Cleared**, and **Recommendations**

   One timestamped file per run, so you can compare tune-ups over time.
   `latest.html` always points at the newest.
5. **You choose** what to act on from a click-through menu, with the RAM/CPU/disk cost
   shown for every option. **Nothing changes until you pick.**
6. Anything not needing a password, Claude does directly. Anything that does gets bundled
   into one script — you see what's in it first and type your password once.
7. **Re-measure**, and the report file updates with what each change actually bought —
   just refresh the browser tab.

## What's in the folder

| File | Purpose |
|---|---|
| `SKILL.md` | The instructions Claude follows |
| `scan.sh` | Read-only diagnostic scan |
| `measure.sh` | State snapshot — identical every run, so before/after is comparable |
| `report-template.html` | The report design, ready to fill with data |
| `apply.sh` | Regenerated each run with only the fixes you approved |
| `partner-prompt.md` | Standalone version for machines without the skill installed |

Reports are written to `~/Downloads/Claude-MacTuneUp/`, not into the skill folder.

## Safety

- Nothing is deleted — things are **moved** to `~/mac-tuneup-bak-<date>/`, so any change
  reverses by moving the file back. (Deletion happens only if you explicitly ask.)
- Documents, downloads and media are never touched without asking about that specific
  file, with its size and path shown.
- Sync daemons, the VPN carrying your traffic, and live VMs are excluded from the menu
  by default rather than offered as options.
- It won't go near FileVault, SIP, Gatekeeper, the Spotlight index, kernel extensions,
  or `/System`.
- **Nothing leaves the machine.** Reports are local HTML files opened from disk — no
  upload, no link, no external fonts or scripts. They work with the network off.

## No Claude Code on that machine?

Paste `partner-prompt.md` into any Claude session — same workflow, no install needed.
