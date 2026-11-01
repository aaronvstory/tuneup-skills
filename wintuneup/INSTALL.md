# Install `/wintuneup`

A Claude Code skill that health-checks a Windows PC — performance, memory, startup junk
left by uninstalled apps, scheduled-task orphans, shell extensions, security stack,
network, disk, DNS — and delivers a polished HTML report. It scans and reports first,
and changes nothing until you pick items off a menu.

The Windows counterpart to `/mactuneup`. Same workflow, same report design, same
scan-then-ask discipline.

## Install

Drop the `wintuneup` folder into your Claude Code skills directory:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills" | Out-Null
Move-Item .\wintuneup "$env:USERPROFILE\.claude\skills\"
```

No execution-policy change is needed — every command runs with `-ExecutionPolicy Bypass`.
Start a new Claude Code session and it'll pick the skill up.

## Other agents

Codex, ChatGPT agents, and others do not need a special folder. Put `wintuneup` anywhere and say:

> Read `wintuneup/SKILL.md` and follow it.

## Use

```
/wintuneup
```

Or just say "tune up this pc" / "why is windows slow".

## What happens

1. **Baseline** — one measurement captures the "before" numbers.
2. **Read-only scan** — ~60 seconds, changes nothing, no admin needed. Run it elevated
   if you can: two checks (shadow-copy store, filter drivers) are admin-only and report
   `NEEDS-ADMIN` rather than pretending they're clean.
3. **Verification** — findings are confirmed before they're reported. Several raw checks
   can produce false positives; the skill knows which and re-tests them.
4. **A report** — an HTML file saved to `%USERPROFILE%\Downloads\Claude-WinTuneUp\` and
   opened in your browser. **Nothing is uploaded anywhere**; it's a local file describing
   your machine, and it stays on your machine.
   It covers:
   - **About This PC** — model, CPU, Windows build, plus how many apps, startup entries,
     scheduled tasks, services and drivers you're carrying
   - **This PC's Networking** — IPs, DNS, MTU, VPN stacks, virtual adapters, public exit
   - **Before & after** charts and scoreboard
   - **Findings**, **Cleared**, and **Recommendations**

   One timestamped file per run, so you can compare tune-ups over time.
   `latest.html` always points at the newest.
5. **You choose** what to act on from a click-through menu, with the RAM/CPU/disk cost
   shown for every option. **Nothing changes until you pick.**
6. Anything not needing admin, Claude does directly. Anything that does gets bundled into
   one script — you see what's in it first and approve one UAC prompt.
7. **Re-measure**, and the report file updates with what each change actually bought —
   just refresh the browser tab.

## What's in the folder

| File | Purpose |
|---|---|
| `SKILL.md` | The instructions Claude follows |
| `thermal.ps1` | Heat and throttle check, with no screenshot needed |
| `disksweep.ps1` | Accounts for every GB, including hidden NTFS data |
| `scan.ps1` | Read-only diagnostic scan (24 sections) |
| `measure.ps1` | State snapshot — identical every run, so before/after is comparable |
| `report-template.html` | The report design, ready to fill with data |
| `apply.ps1` | Written during a run, with only the fixes you approved. Not shipped in this folder. |
| `test-parse.ps1` | Self-check for the command-line parser |
| `partner-prompt.md` | Standalone version for machines without the skill installed |

Reports are written to `%USERPROFILE%\Downloads\Claude-WinTuneUp\`, not into the skill folder.

## Safety

- **A System Restore point is taken before anything is changed.** If a run goes wrong,
  one rollback reverses every registry and service change at once. `apply.ps1` refuses
  to run at all if it can't create one.
- Nothing is deleted. Scheduled tasks are **exported then disabled**, registry values are
  **exported then removed**, services are **recorded then set to Disabled**, files are
  **moved** to `%USERPROFILE%\win-tuneup-bak-<date>\`. Every change reverses.
- `sc delete` is never used. Neither is `DISM /ResetBase`.
- Documents, downloads and media are never touched without asking about that specific
  file, with its size and path shown.
- Sync clients, the VPN carrying your traffic, backup agents and live VMs are excluded
  from the menu by default rather than offered as options.
- It won't go near BitLocker, Secure Boot, Tamper Protection, Defender real-time
  protection, the Windows Search index, or `C:\Windows\Installer` by hand.
- **Nothing leaves the machine.** Reports are local HTML files opened from disk — no
  upload, no link, no external fonts or scripts. They work with the network off.

## Optional sensor tool

CPU temperature needs HWiNFO. Claude asks before it installs HWiNFO. Without it, the scan still reports CPU speed, load, and NVIDIA GPU temperature.

## Why it doesn't use `Get-Counter`

Because on a machine whose performance-counter registry is corrupted — a common and
completely silent Windows fault — `Get-Counter` and every `Win32_PerfFormattedData_*`
class return **nothing**, and a counter-based script cheerfully reports a perfectly idle
machine no matter how loaded it is. CPU here is derived from per-process CPU-time deltas,
which always work and don't depend on system locale. The scan reports the counter
registry's health as a finding in its own right.

## No Claude Code on that machine?

Paste `partner-prompt.md` into any Claude session — same workflow, no install needed.
