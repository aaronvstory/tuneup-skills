---
name: wintuneup
description: Full read-only health scan of this Windows PC — performance, memory, startup cruft, scheduled-task orphans, shell extensions, security stack, network, disk, DNS — delivered as a polished HTML report saved locally to %USERPROFILE%\Downloads\Claude-WinTuneUp\ and opened in the browser (About This PC, networking, before/after scoreboard, findings, recommendations), then applies only the fixes the user picks from an the question tool menu. Use when the user says "tune up this pc", "why is windows slow", "/wintuneup", "check my pc", "windows health check", or reports sluggishness, fan noise, flaky network, slow right-click, or DNS/connection errors with no obvious cause. Scans first, changes nothing without an explicit pick.
---

# Windows Tune-Up

Diagnose, report, **then** ask. The scan changes nothing. No permanent change happens
without the user picking it off a list first.

## Works with any agent

These are plain instructions and scripts. the agent, Codex, ChatGPT agents, and other coding agents can all follow them.

- **`<skill-folder>`** means the folder that holds this file. Use its real path.
- **Ask with the agent's question tool.** That is `AskUserQuestion` in the agent and `request_user_input` in Codex. If there is none, print a numbered list and wait for the reply.
- **Web lookups** use the agent's web tool. If there is none, say so and mark the market section as not checked.
- **Keep the same rules on every model.** A weaker model checks more, not less.

## Never delete on your own

**This is the top rule.** The scan and the report change nothing.

- Every fix is an offer. Show the path, the size, what it costs, and how to undo it. Then ask.
- A plain "clean up" request is not approval for a delete. Ask with the exact items.
- Prefer a move or a disable to a delete. Offer a delete only for data that can be rebuilt, or when the user names the item.
- Delete only what the user picked, and verify the target right before you delete it.
- Never touch user documents, media, chats, or projects without an explicit yes for that item.

## Quick reference

| Need | Command |
|---|---|
| Baseline / final numbers | `powershell -ExecutionPolicy Bypass -File <skill-folder>\measure.ps1 -Inventory` (`-Now` skips the 30 s settle) |
| Heat, throttle, and temperature | `powershell -ExecutionPolicy Bypass -File <skill-folder>\thermal.ps1` (`-Setup` once for sensors) |
| Every GB on a drive | `powershell -ExecutionPolicy Bypass -File <skill-folder>\disksweep.ps1` (all drives, run elevated, takes minutes) |
| Network analysis | `<skill-folder>\network.ps1` (`-NoSpeed` to skip transfers) |
| Full diagnostic scan | `powershell -ExecutionPolicy Bypass -File <skill-folder>\scan.ps1` (~60 s) |
| Parser self-check | `powershell -ExecutionPolicy Bypass -File <skill-folder>\test-parse.ps1` |
| Report starting point | `<skill-folder>\report-template.html` |
| Where reports go | `%USERPROFILE%\Downloads\Claude-WinTuneUp\pc-health-<date>.html` → `Start-Process` it (never published) |
| Hand elevated work to the user | write `apply.ps1`, then they run `! powershell -ExecutionPolicy Bypass -File "<skill-folder>\apply.ps1"` |
| Backups / undo | `%USERPROFILE%\win-tuneup-bak-<date>\` + a System Restore point |

**The six rules that matter most** — everything below elaborates on these:

1. **Settle before measuring.** Only `measure.ps1` takes numbers. Never `apply.ps1`'s inline ones.
2. **Verify every scan finding before repeating it.** `scan.ps1` reports symptoms, not conclusions.
3. **Kill patterns come from `Get-Process`, never from the app's name** — then verify the kill took.
4. **Take a System Restore point before `apply.ps1` touches anything.** Windows gives you this; use it.
5. **Ask with the question tool**, with the cost in every option, never a freeform list.
6. **The report states findings, never your process.** No corrections, no "I got this wrong".

## Workflow

0. **Heat** — `thermal.ps1`, while the machine is slow. See *Heat*.
1. **Baseline** — `measure.ps1 -Now -Inventory`. Keep this output. It is the "before"
   column of every number you will later claim.
2. **Scan** — `scan.ps1`. Read-only, ~60 s. Runs without admin, but **run it elevated when
   you can**: `vssadmin` and `fltmc` are admin-only and say `NEEDS-ADMIN` otherwise.
3. **Verify before believing.** The scan reports symptoms. Confirm each cause yourself
   before naming it (see *Verification rules*). A confident wrong diagnosis is worse
   than "I don't know yet".
4. **Report** — write an HTML file to `%USERPROFILE%\Downloads\Claude-WinTuneUp\` and open
   it. Never a terminal wall, never published online. See *Reporting*.
5. **Ask with the the question tool tool** — always, never a freeform "which ones?".
   See *Asking*. Only then write a script.
6. **Apply** — see *Applying fixes*. Verify each retirement actually took.
7. **Re-measure** — `measure.ps1 -Inventory` (settles 30 s automatically). Diff against
   step 1, rewrite the report file, and tell the user to refresh the tab.

### Efficiency — don't hand-roll what the scripts already do

The failure mode is thirty ad-hoc calls that each re-derive the same state.

- **Batch verification into one call.** After the scan, resolve every questionable
  finding in a single command — one pass over all flagged tasks, one over all suspect
  processes. Not one call per item.
- **`measure.ps1` is the only way you take a measurement.** Never hand-roll
  `Get-Process` for before/after; the point is that both sides ran identical code.
- **Never poll in the foreground.** Use `run_in_background` and read the file when it lands.
- **Don't re-scan what hasn't changed.** Disk layout and inventory move slowly.
- **Total budget for a clean run: baseline + scan + ~2 verification calls + apply +
  re-measure.** Past a dozen calls before writing the report means you are re-deriving
  state instead of reading it.

## Applying fixes

Goal: the user types **one** thing, not a wall of pasted commands.

- **Do everything that doesn't need elevation yourself**, directly, once they've
  confirmed. `HKCU` Run values, per-user scheduled tasks, Startup-folder shortcuts,
  killing user processes, files in the home directory — just do those.
- **Everything needing admin goes into one script**, always at the same path:
  `<skill-folder>\apply.ps1` (overwrite it each run). It
  **self-elevates**, so the user gets one UAC prompt and types exactly one line:

  ```
  ! powershell -ExecutionPolicy Bypass -File "<skill-folder>\apply.ps1"
  ```

  A `!` command gets a real terminal so the UAC consent dialog can appear. **Your own
  shell cannot elevate** — `Start-Process -Verb RunAs` from the Bash/PowerShell tool
  either fails or silently opens a window you cannot see. Never try.
- **Before handing it over, show what the script will do** as a short bullet list.
- **Build the script from the fixes they actually picked** — not everything you found.

### Retiring a startup item — the full recipe

An app has **up to five independent anchors**. Miss one and it survives or returns.
Handle all five, or the "removal" is cosmetic:

| # | Anchor | Where | Admin? |
|---|---|---|---|
| 1 | Run key (machine) | `HKLM\...\CurrentVersion\Run` **and** `\Wow6432Node\...\Run` | yes |
| 2 | Run key (user) | `HKCU\...\CurrentVersion\Run` | **no** |
| 3 | Startup folder | `shell:startup` (user) / `shell:common startup` (machine) | machine one: yes |
| 4 | Scheduled Task | `Get-ScheduledTask`, often under a vendor `TaskPath` | depends on the task's principal |
| 5 | Service | `Get-CimInstance Win32_Service`, `StartMode=Auto` | yes |

- **Check all five before declaring it done.** Anchors 2–4 are invisible in Task
  Manager's Startup tab and are the usual reason a "removed" app reappears at boot.
  A single vendor routinely uses three at once — Stardock Fences ships a `HKCU` Run
  value, two scheduled tasks, *and* a shell extension.
- **`Wow6432Node` is a separate key, not a view.** On one tested PC, five startup entries
  live only there. Checking `HKLM\...\Run` alone misses them entirely.
- **Disabling in Task Manager ≠ removing.** The `StartupApproved` binary value flips
  byte 0 to odd. `scan.ps1` reads it and prints `[DISABLED]`. **Never offer to disable
  something already marked DISABLED** — it makes the menu look padded and wastes a pick.

### Kill patterns must come from `Get-Process`, never from the app's name

**This is the most common way an apply script silently under-delivers.** Vendor process
names rarely match the product name:

| You'd guess | Actually runs as |
|---|---|
| Glary Utilities | `GUBootService`, `MemfilesService`, `Initialize` |
| UltraVNC | `winvnc` |
| Chrome Remote Desktop | `remoting_host` |
| Parsec | `pservice` + `parsecd` |
| Adobe Creative Cloud | `CCXProcess`, `AdobeUpdateService`, `armsvc` |

Before writing any `Stop-Process`, dump the real names and build the pattern from that:

```powershell
Get-Process | Where-Object { $_.Path -like '*<vendor>*' } | Select-Object Name, Id, Path
```

**Always verify after killing** — re-run the same query and report what survived. Never
report a service as retired without that second check.

### Measuring — settle before you believe

- **Never measure inside the apply script.** A `Start-Sleep 3` before/after on a busy PC
  measures scheduler noise. Take the script's numbers as informational only; **do not
  publish them**.
- **Settle ≥ 30 s** before any post-change measurement. `measure.ps1` does this for you.
- **Compare like for like**: same script, same settle time, both sides.
- **`COMMIT_PCT` is the honest memory metric.** `MEM_AVAILABLE_MB` swings wildly because
  Windows opportunistically fills free RAM with cache; a single reading proves nothing.
- **`Memory Compression` holding several GB is normal**, not a leak. It is compressed
  pages, and it means the compressor is doing its job.
- Re-measure everything once at the end, in one command, and let *that* be the scoreboard.

## Verification rules

These exist because each one has already caught a wrong diagnosis.

- **Perf counters are the first thing to check, because their failure is silent.** When
  `HKLM\...\Perflib\009\Counter` is empty, `Get-Counter` and **every**
  `Win32_PerfFormattedData_*` class return nothing — so a counter-based script reports a
  perfectly idle machine no matter how loaded it is. Task Manager's App History and
  Resource Monitor go blank too. `scan.ps1` checks this in `PERFLIB_HEALTH` and derives
  CPU from per-process CPU-time deltas instead, which always works. Rebuild with
  `lodctr /R` then `winmgmt /resyncperf`.
- **`H` is a built-in alias for `Get-History`.** A helper function named `H` is silently
  shadowed, and with `$ErrorActionPreference='SilentlyContinue'` every call vanishes
  without a trace. Same trap for `r`, `sc`, `gc`, `cat`, `curl`, `wget`, `ls`, `where`.
  **Check `Get-Alias <name>` before naming a helper**, and never leave a script's
  structural output at the mercy of a suppressed error stream.
- **Never split a command line on whitespace to find its executable.** Program Files
  paths contain spaces, so `C:\Program Files\Elgato\ControlCenter\ControlCenter.exe
  -runinbk` becomes three "missing files" and one healthy entry becomes an ORPHAN. Parse
  the quoted token first, then fall back to a non-greedy match up to the first
  executable extension. `test-parse.ps1` locks this in — run it if you touch the helper.
- **Some Run values are quoted *and* backslash-escaped**: `"\"C:\path\app.exe\" --startup"`.
  Naively grabbing the first quoted token returns a lone `\`. Unwrap before parsing.
- **svchost-hosted services all share `svchost.exe`.** A naive missing-exe check flags
  dozens of healthy services. Exclude them explicitly.
- **A bare executable name is not a missing file.** `powershell.exe`, `OneDrive.exe` and
  `explorer.exe` resolve via `PATH`. Test with `Get-Command` before calling it orphaned.
- **Verify the vendor directory yourself before calling a task orphaned.** A missing
  `ScheduleEventAction.exe` inside a version folder that *does* exist, next to a service
  that *is* running, is still a real orphan — but you only know that by listing the
  folder. Check; don't infer from the service being up.
- **A stale user profile is the usual source of orphan clusters.** When several unrelated
  vendors all point at `C:\Users\<old-name>\...`, the finding is one dead profile, not
  five broken apps. Check `Get-ChildItem C:\Users` early — it collapses a long findings
  list into one line.
- **Two installs of a thing are not automatically fighting.** Confirm both are actually
  running, then check whether they can both hold the resource. Two VNC servers only
  conflict if both want port 5900 — verify with `Get-NetTCPConnection -State Listen`.
- **`ProxyServer` set with `ProxyEnable=0` is inert.** Don't report a disabled proxy as
  a cause of anything. It's a leftover, worth one line in *Cleared*, not a finding.
- **A cached DNS lookup cannot fail.** Testing a common name proves nothing. Use random
  never-seen labels, aimed at a specific server. **NXDOMAIN is a successful lookup** —
  the server answered. Only timeouts count as failures.
- **Separate a bad resolver from a starved client.** If failures shrink as the timeout
  grows, the resolver is fine and *this PC* is too loaded to answer in time. Fix the load.
- **Distinguish a burst from a steady state.** A 3-second CPU sample catches steady load,
  not bursts. Sample twice, minutes apart, before calling anything permanent.
- **Uptime first — under ~10 minutes of uptime every number is a boot burst.** Windows
  runs update scans, Defender catch-up, prefetch and indexing right after login.
- **A pending reboot is not automatically a servicing problem.** Read
  `PendingFileRenameOperations` before escalating: three browser temp files awaiting
  cleanup is a footnote, a stuck CBS servicing stack is a finding. Say which.
- **Error code 22 in Device Manager means *the user disabled it*.** Don't offer to
  "fix" a deliberately disabled camera or NIC. Code 28 (no driver) on `ROOT\USBDEVICE\*`
  is a genuine ghost-device pile; code 31 is a driver that failed to load.
- **Check what's actually listening before blaming a remote-access tool.** A resident
  VNC/RDP host that isn't bound to a port costs a few MB and nothing else.
- **`Get-MpComputerStatus` can report `RealTimeProtectionEnabled = True` while
  `AntivirusEnabled = False` with an empty signature version.** That is not a
  contradiction to hand-wave — it means the engine is loaded with **no definitions**.
  Read `AntivirusSignatureLastUpdated`, `AntivirusSignatureVersion` and
  `DefenderSignaturesOutOfDate` together before drawing any conclusion about protection.
  An age of `65535` is the "never successfully updated" sentinel, not 179 years.
- **Never purge `%TEMP%` by file age.** Apps keep live data there, and an old file is not an unused file.
  - On one PC, a 7-day purge removed idle binaries from a running app's unpacked folder, so the app could not stream.
  - The same purge deleted the app's saved settings, which were last written weeks earlier.
  - List the top-level folders with size and newest file date. Offer each folder as a pick. Never recurse with a date filter.
  - Never offer `claude`, `.claude`, or a folder that holds the `Path` of a running process (`Get-Process`).
  - Never offer a folder named after an installed app until you know it holds only cache. Search the app's source or logs for that path.
  - Write the full delete list to the backup folder first, so the user can see what went.
  - Say that a restore point can bring back a file. Check that one exists before the delete.
- **`Update-MpSignature` returns success without doing anything when a policy blocks
  the AV component.** Never report a definition update as applied off the cmdlet's exit
  alone. Verify with `MpCmdRun.exe -SignatureUpdate`, which prints the real engine and
  signature versions, and check the `.vdm` file dates under
  `C:\ProgramData\Microsoft\Windows Defender\Definition Updates`. Empty status fields
  with current `.vdm` files on disk means the *reporting* is disabled, not the
  definitions missing — check
  `HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\DisableAntiVirus` before
  concluding anything about protection.
- **Tamper Protection cannot be enabled from the registry or PowerShell.** The key is
  kernel-protected and the write fails with "Requested registry access is not allowed"
  even elevated. It is a Windows Security UI toggle (or Intune). Say so; don't retry.
- **Another machine on the same LAN is the best instrument available.** If a Mac on the
  same network doesn't have the problem, everything shared is innocent — router, tunnel,
  exit IP, ISP, remote service. Ask early.

## Heat — check before any process hunt

A hot machine feels like a hidden process: every app is slow and no process shows high CPU.
Heat and thermal limits hide from Task Manager. Read them yourself. Never ask the user for a screenshot.

- **Run `thermal.ps1` first, while the machine is slow.** It prints temperatures, power, limits, and a verdict.
- **Sensors need HWiNFO.** With the user's yes: `winget install REALiX.HWiNFO`, then `thermal.ps1 -Setup` elevated.
  - `-Setup` backs up the INI, turns on sensor sharing, and starts HWiNFO minimized.
  - The free edition stops sharing after 12 hours. Run `-Setup` again when `SENSORS=NOT-SHARED`.
- **Temperature at a given power is the finding.** 100°C at 60 W is a cooling fault. 100°C at 150 W can be normal on a laptop.
- **Read the limits.** `CPU_THERMAL_LIMIT_PCT` at 100 with `CPU_PPT_SLOW_LIMIT_PCT` far below 100 means heat is the limit, not power.
- **`THROTTLE_FLAGS=none` does not clear heat.** The chip can hold its temperature limit without setting a flag.
- **Compare with a fresh boot.** `CPU_SPEED_PCT` high after boot and low after 30 minutes points to heat build-up.
- **`FANS_FOUND=0` means the sensor is not exposed.** Some laptops hide fan speed. It does not mean a dead fan. Listen for the fan.
- **Check the GPU state.** Top P-state at about 0% use adds steady heat on a shared cooler. Find the holder before you blame it.
- **Never switch the power plan to cut heat without measuring clocks under load.** A lower temperature can come from a clock lock, not from better cooling.
  - On one laptop, Balanced locked an AMD CPU at 2.0 GHz under full load (32 W, 75°C). Ultimate Performance ran it at 4.4 GHz (82 W). The 10°C drop that Balanced gave was the lock, and benchmark scores fell by half.
  - Measure with an all-core load and read the core ratio or effective clock (HWiNFO), on both plans, before you offer a switch.
  - Ultimate Performance also turns off CPU idle (`IDLEDISABLE=1`), which adds idle heat. Turning idle back on (`powercfg /setacvalueindex <plan> SUB_PROCESSOR IDLEDISABLE 0`) kept full boost on that laptop.
- **Fix order.** Clear the vents, clean the fans and fins, then consider a repaste. Warn that some laptops use liquid metal, so a repaste can be a repair-shop job.

## Disk space — account for every GB

Folder tools miss hidden NTFS data. Do not stop at a list of large folders.

- **Run `disksweep.ps1` elevated, with no drive named.** It sweeps every connected drive, one at a time. It prints the NTFS allocation report and then folders and files over 5 GB.
- **Show every connected drive.** Include internal, USB, and network drives, not only the fullest two. Say if a known drive is not connected.
- **Rank each drive's contents.** In `space.drives[].parts`, list the top 10 or so items as `{ "l", "n", "gb", "s" }`, where `n` is a short detail such as "6 titles over 20 GB". Never show only a bar.
- **Reconcile.** Allocated space must equal system files + System Volume Information + user files. Name any gap.
- **`$Txf` over 1 GB is a finding.** These are NTFS transaction files, and folder tools cannot see them.
  - Fix: `fsutil resource setautoreset true C:\`. Space frees at the next reboot, so say the real gain is unknown until then.
  - Require zero running transactions first (`fsutil resource info C:\`).
- **Count a junction once.** `disksweep.ps1` does not follow links. List the links so the user sees where the data really is.
- **Prefer moves over deletes.** Check which volumes share a physical disk. A move to the same fast disk costs no speed. A USB disk is a poor target for apps.
- **Moving an app folder:** copy, compare file count and bytes, rename the original, create a junction, compare again, then remove the original.
- **Installer patches are not junk.** `.msp` files moved out of `C:\Windows\Installer` break repair and update of that app. Say this before anyone removes them.

## Do not become the load

- **Check the machine before you add work.** If it is hot or slow, do the light checks first.
- **Run copies and sweeps at below-normal priority, one at a time.** Below-normal priority does not protect the disk.
- **A restore point also loads the machine.** Do not start a large copy in the same minute.
- **Other agents count.** Look for parallel tests, builds, and scans before you blame an app. Do not pause another agent's work unless the user asks.
- **If the user says it is slow, stop your own jobs first, then measure.**

## Known pathologies

| Symptom | Usual cause | Notes |
|---|---|---|
| Everything reports 0% / Task Manager App History blank | Perflib counter registry destroyed | `lodctr /R` + `winmgmt /resyncperf`. Also throws `WMI Performance Adapter` errors in the System log. |
| Slow right-click, Explorer hangs | Third-party shell extensions | Explorer loads every handler **in-process**, so the cost shows up as `explorer.exe` and is invisible per-extension. A handler whose DLL is *missing* still costs a failed load on every menu. |
| C: shrinking with nothing installed | VSS restore-point store at its cap | Capping keeps recent points and reclaims the rest. Not the same as disabling protection. |
| Deleting large files frees nothing | Shadow copies still pin them | The direct analog of an APFS snapshot. Check the store before believing a delete failed. |
| `MsMpEng.exe` pegging a core | Defender scanning a build/dev tree | The fix is a **path exclusion**, never disabling real-time protection. |
| Defender on but signature version empty | Definitions never installed / update channel broken | `Update-MpSignature`. Reporting "protected" off `RealTimeProtectionEnabled` alone is wrong. |
| Fast after boot, slow after 30 minutes, no process to blame | Cooling fault: dust, fan, paste, vents | `thermal.ps1` shows high temperature at low power. |
| "System and reserved" huge, folder tools find nothing | `$Txf` NTFS transaction files, or restore points | `disksweep.ps1` reports both. Often follows System Restore. |
| Startup cruft | Uninstalled apps leaving Run keys + scheduled tasks | Vendor uninstallers routinely remove the binary and leave the task. Highest-value find. |
| Orphan cluster across unrelated vendors | One renamed/abandoned user profile | Fix the profile question once instead of the symptoms N times. |
| "Memory optimizer" / standby-list cleaner resident | Purges the standby list | These *cause* re-reads from disk by dropping the file cache, then bill it as freed RAM. A memory service holding hundreds of MB to save memory is self-refuting. |
| Several "cleaner"/"driver updater" suites installed | Each adds services, a shell extension, and a SkipUAC task | The worst offenders orphan themselves on uninstall. |
| Many virtual adapters | VPN stacks + Hyper-V vSwitch + WSL | Each adds routing and MTU complexity. A tunnel at MTU 1280 alongside a 1500 physical link is normal, not a fault. |
| Uploads die, downloads fine | MTU too big for a tunnel on the **router** | Less common than on macOS — Windows does PMTU black-hole detection and backs off. If Windows is fine and a Mac on the same LAN isn't, the Mac is the outlier. |
| Ghost `ROOT\USBDEVICE\*` entries, code 28 | Device-spoofing / ADB tooling leaving phantom nodes | Harmless at idle; they slow enumeration and clutter Device Manager. |
| Audio effects stack (Nahimic, Sonar, virtual cables) | Each APO loads into `audiodg.exe` | Only a finding **if `audiodg` is actually burning CPU**. Idle at 0.2% is a *Cleared* line, not a recommendation. |
| High disk, low CPU at idle | SysMain + Defender scan + Delivery Optimization overlapping | Usually legitimate transient work. |

## Reporting

**Write an HTML file to disk and open it locally. Never publish it.** These reports
describe the user's machine, network topology, IP addresses and security posture —
that stays on the machine. **Do not call the Artifact tool for a tune-up report.**

```powershell
$dir = "$env:USERPROFILE\Downloads\Claude-WinTuneUp"
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$report = Join-Path $dir "pc-health-$(Get-Date -Format 'yyyy-MM-dd-HHmm').html"
Copy-Item "<skill-folder>\report-template.html" $report
# ...fill in the data...
Copy-Item $report (Join-Path $dir 'latest.html') -Force    # stable pointer
Start-Process $report
```

- **One file per run**, timestamped, so past tune-ups stay comparable. `latest.html`
  always points at the newest.
- **As findings firm up, rewrite the same file** and tell the user to refresh the tab.
  Never start a second file mid-run.
- `Start-Process` uses their default browser. Say the filename in chat.

**Fill `report-template.html`, and do not redesign it.** It is one self-contained, minimal page: actions and findings first, collapsible detail below, and a jump bar at the top. Do not add decoration. Copy it to the report path. Then replace only the JSON inside `<script id="report-data">`.

- **Remove `"example": true`.** That key prints "sample data" on the page.
- **Delete a key to hide its section.** Never leave sample values on the page.
- **`mood`:** `happy`, `ok`, `hot`, or `sad`. Use `hot` when heat is the top finding.
- **`score`:** start at 100. Take off 25 for a heat limit, 15 for a disk over 90% full, 10 for each other serious finding, and 3 for each minor one. Never use a score to flatter a machine.
- **`s` values:** `good`, `warn`, `hot`, or `info`.
- **Check the page.** It needs no network. In strings, only `<b>` works as markup. JSON-escape backslashes in paths.

### Voice — this is a product, not a lab notebook

- **Bullets, not paragraphs.** A reader should get the whole picture by scanning.
- **Never narrate your own process.** No "I got this wrong", no "correction", no "my
  earlier check misfired". The reader wants the state of their PC, not a diary.
  **Wrong findings are deleted, not confessed.**
- Self-correction belongs in *chat*, once, briefly — never on the page.
- No hedging filler. State the finding.
- Numbers carry the argument: `13 tasks / 1 missing exe`, not "several broken tasks".
- **Security findings are stated factually, never moralised.** Report what is
  configured, what it exposes, and what changes it. How it got there is not the report's
  business unless the user asks.

### No commands in the report — exactly one exception

**The report is a snapshot, not a runbook.** The user reads it to see what they're
working with; *you* run the commands in the agent. A page full of PowerShell they'd
have to copy is the thing they didn't want.

- **Never** put `Stop-Process`, `Disable-ScheduledTask`, `Remove-ItemProperty`,
  `vssadmin`, `DISM`, `sfc` or a "how to undo" block on the page. Recommendations say
  **what** and **why**, with cost and effort tags — never **how**.
- Settings, paths and process names as *facts* are fine and good: `MTU 1280`,
  `HKCU\...\Run`, `audiodg.exe`, `Perflib\009`. A fact is not an instruction — the test
  is whether the reader is meant to type it.
- **The one exception:** when elevated work is outstanding, show the single one-liner
  in the `#pending-admin` block (in the template, `hidden` by default — unhide it and
  fill in the figures). Swap it for the "Applied" card once it has run.
- Undo instructions live in `apply.ps1`'s own output and in chat, never on the page. The
  page just names the backup directory and the restore point.

### Report data

The page puts `vitals`, `offers`, `findings`, and `space` first. Network, market, machine, and cleared items start collapsed.

1. **`machine`, `headline`, `summary`, `mood`, `score`.** The headline states the top problem in plain words. `mood` only sets the small status icon.
2. **`vitals`:** CPU heat, CPU speed, memory, main disk, internet, background load. Measured values only.
3. **`spec`:** model, CPU, GPU, memory, OS, storage, uptime.
4. **`market`:** how good this machine is today. See *Market check*.
5. **`space`:** every connected drive with a ranked list of its largest items. `items` holds only the ones with an offer.
6. **`network`:** the hops in order, then speed, Wi-Fi, DNS, loss, tunnels, and open remote access.
7. **`findings`:** ordered by severity, 3 bullets at most: what, evidence, cost.
8. **`results`:** only after a change. Keep rows that did not improve.
9. **`offers`:** the choices you will ask about. Say what and why, with cost and effort tags.
10. **`cleared`:** what looked wrong and checked out fine.
11. **`protected`:** say that nothing is deleted without a pick, and name what stays untouched.

### Market check

Look up the exact model on the web during the run. The user wants a real answer on how good this machine is today.

- **Search for:** release year, current new-machine equivalents, and current used prices for the exact model.
- **Say the tier honestly.** Rate CPU, GPU, memory, and storage against machines sold today, and name what limits it.
- **Name the best upgrade**, or say none is worth buying.
- **Cite every price with its source and month.** Listing prices are asking prices, so say that.
- **Never send the serial number, user name, or IP address in a search.** Search by model only.
- **Nothing found:** say "not checked". Do not guess.

### Network analysis

Run `network.ps1` or `network.sh`. It sends a few pings and a small speed test.

- **Ask first on a metered link,** or pass the no-speed flag.
- **Fast hop 1 with slow hop 2 means a tunnel past the first hop.** If another device on the same network shows the same hop, the tunnel is on the router.
- **Report open remote-access tools factually.** Do not moralise.
- **Do not compare speed results from different tools as if they were the same test.**

### Honest-scoreboard rules

- Baseline = the **settled** figure, not a boot-burst peak.
- If a change didn't help, keep the row and mark it flat. Say so in chat too.
- Never publish numbers from `apply.ps1`'s inline before/after.
- Attribute honestly: a pending reboot, or Defender finishing a scan on its own, is not
  something the tune-up did.

## Asking

**Always use the the question tool tool.** Never end a report with a freeform "tell me
which ones" — it makes the user compose a list by hand from a long page.

- **State your recommendation first**, in prose, then ask. They should be choosing
  against a recommendation, not from a blank menu. Mark it `(Recommended)` and put it first.
- **Batch by category, not one question per item.** 4 questions × 4 options is the
  ceiling. Group startup items, orphaned tasks, disk reclaim, and network changes into
  their own questions with `multiSelect: true`.
- **Put the cost in the description** — RAM, CPU, process count, GB, boot delay.
  "Glary Utilities — 326 MB across 2 services + a shell extension" beats "cleaner app".
- **Never list a must-keep item as an option.** The VPN carrying their traffic, sync
  daemons, backup agents, licensing helpers — exclude them and say in prose why.
- **When an answer contradicts their own documented setup, flag it once and re-ask.**
  Answers get inverted in a multi-select. Once they reaffirm, do it without argument.
- Re-ask at each new decision point, not just once at the end.

## Change rules

- **Take a System Restore point first.** One command, and it covers registry and
  service changes wholesale. This is the biggest safety advantage Windows has — use it
  before every `apply.ps1` run, and name it in the report.
- **Disable, don't delete.**
  - Scheduled task → `Export-ScheduledTask` to XML in the backup dir, *then* `Disable-ScheduledTask`.
  - Run key value → `reg export` the key, *then* `Remove-ItemProperty`.
  - Service → record `StartMode`, *then* `Set-Service -StartupType Disabled`. Never `sc delete`.
  - Files → **move** to `%USERPROFILE%\win-tuneup-bak-<date>\`, never delete.
- **One script, shown before it runs.** No silent edits scattered across turns.
- **User files are the user's call.** Never delete documents, downloads or media without
  an explicit yes on that specific file, with its size and path shown.
- **Never touch:** BitLocker, Secure Boot, Defender real-time protection (exclusions are
  fine, disabling is not), Tamper Protection, the Windows Search index (deleting forces a
  worse full rebuild), `DISM /ResetBase` (irreversible, blocks update uninstall),
  `C:\Windows\Installer` by hand (breaks app repair/uninstall — the reversible
  three-source orphan check is the only safe route), driver removal without a restore point.
- **Ask before disabling anything the user might rely on** — VPNs, sync clients, backup
  agents, remote-access hosts, licensing helpers. Removing a licensing helper to reclaim
  0% CPU is a bad trade; say so.
- **Check what's running before restarting a shared service.** Restarting `audiodg` or
  Explorer during a recording or call loses work — check for OBS, Zoom, Teams first.
- **Quit apps gracefully first, then verify.** `CloseMainWindow()` lets an app save
  state; try it before `Stop-Process -Force`. But **confirm it worked** — many tray apps
  ignore it. Never assume a quit succeeded.
- **Warn before quitting anything holding live state** — a browser with unsaved tabs, a
  sync client mid-transfer, the VPN carrying the current connection.
- **Re-measure and report honestly.** If a fix didn't help, say it didn't — in chat *and*
  in the Results table.

## Post-run

- **Offer, don't assume:** a final rewrite of the report file with the results scoreboard.
- **State what's left** — pending reboot, stragglers that clear at boot, anything deferred.
- **Point at the backup dir** `%USERPROFILE%\win-tuneup-bak-<date>\` and the restore
  point name, and how to reverse each change.
- **Don't leave a straggler hunt running.** A 12 MB helper that clears at the next reboot
  is a footnote, not a second UAC prompt.
