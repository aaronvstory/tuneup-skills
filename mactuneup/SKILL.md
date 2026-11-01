---
name: mactuneup
description: Full read-only health scan of this Mac — performance, memory, startup cruft, network, disk, audio, DNS — delivered as a polished HTML report saved locally to ~/Downloads/Claude-MacTuneUp/ and opened in the browser (About This Mac, networking, before/after scoreboard, findings, recommendations), then applies only the fixes the user picks from an the question tool menu. Use when the user says "tune up this mac", "why is my mac slow", "/mactuneup", "check my mac", "mac health check", or reports sluggishness, fan noise, flaky network, or DNS/connection errors with no obvious cause. Scans first, changes nothing without an explicit pick.
---

# Mac Tune-Up

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
| Baseline / final numbers | `bash <skill-folder>/measure.sh --inventory` (`--now` skips the 30 s settle) |
| Heat, throttle, and temperature | `bash <skill-folder>/thermal.sh` (no sudo) |
| Network analysis | `bash <skill-folder>/network.sh` (`--no-speed` to skip transfers) |
| Full diagnostic scan | `bash <skill-folder>/scan.sh` |
| Report starting point | `<skill-folder>/report-template.html` |
| Where reports go | `~/Downloads/Claude-MacTuneUp/mac-health-<date>.html` → `open` it (never published) |
| Run sudo work | put it ALL in one root script, then `osascript -e 'do shell script "bash <script>" with administrator privileges'` — one real system auth prompt |
| Backups / undo | `~/mac-tuneup-bak-<date>/` |

**The five rules that matter most** — everything below elaborates on these:

1. **Settle before measuring.** Only `measure.sh` takes numbers. Never `apply.sh`'s inline ones.
2. **Verify every scan finding before repeating it.** `scan.sh` has known false positives.
3. **Kill patterns come from `ps`, never from the app's name** — then verify the kill took.
4. **Ask with the question tool**, with the cost in every option, never a freeform list.
5. **The report states findings, never your process.** No corrections, no "I got this wrong".

## Workflow

1. **Baseline** — `bash <skill-folder>/measure.sh --now --inventory`.
   Keep this output. It is the "before" column of every number you will later claim.
2. **Scan** — `bash <skill-folder>/scan.sh`. Read-only, no sudo, ~30s.
3. **Verify before believing.** The scan reports symptoms — several of its checks are
   known-buggy (see *Verification rules*). Confirm each cause yourself before naming it.
   A confident wrong diagnosis is worse than "I don't know yet".
4. **Report** — write an HTML file to `~/Downloads/Claude-MacTuneUp/` and `open` it.
   Never a terminal wall, never published online. See *Reporting*.
5. **Ask with the the question tool tool** — always, never a freeform "which numbers?".
   See *Asking*. Only then write a script.
6. **Apply** — see *Applying fixes*. Verify each retirement actually took.
7. **Re-measure** — `bash <skill-folder>/measure.sh --inventory` (settles
   30 s automatically). Diff against step 1, rewrite the report file with the results,
   and tell the user to refresh the tab.

### Efficiency — don't hand-roll what the scripts already do

The failure mode is thirty ad-hoc `Bash` calls that each re-derive the same state.

- **Batch verification into one call.** After the scan, resolve every questionable
  finding in a single command — one loop over all flagged plists, one loop over all
  suspect processes. Not one call per item.
- **`measure.sh` is the only way you take a measurement.** Never hand-roll `top`/`ps`
  for before/after; the whole point is that both sides ran identical code.
- **Never poll in the foreground.** For load-decay sampling use `run_in_background`
  and read the file when it lands.
- **Don't re-scan what hasn't changed.** Disk layout and inventory move slowly; take
  them once at baseline.
- **Total budget for a clean run: baseline + scan + ~4 verification calls + apply +
  re-measure.** If you are past a dozen calls before writing the report, you are
  re-deriving state instead of reading it.

## Applying fixes

Goal: the user types **one** thing, not a wall of pasted commands.

- **Do everything that doesn't need sudo yourself**, directly, once they've confirmed.
  User-level launchd jobs (`~/Library/LaunchAgents`), login items, killing processes,
  files in the home directory — all of that you can just do. Don't put it in a script.
- **Everything needing sudo goes into one script**, always written to the same path:
  `<skill-folder>/apply.sh` (overwrite it each run). Then give the user
  exactly one line:

  ```bash
  osascript -e 'do shell script "bash /Users/<you>/.claude/skills/mactuneup/apply-root.sh 2>&1" \
    with administrator privileges'
  ```

  **`!` does NOT give sudo a terminal — this was wrong for a long time and cost a whole
  session.** A script run as `! bash apply.sh` fails every sudo line with
  `sudo: a terminal is required to read the password`. Verified on macOS 27,
  2026-09-20: all 11 sudo steps failed, the run was a clean no-op.

  `do shell script ... with administrator privileges` runs the WHOLE script as root
  from **one** native macOS auth prompt (Touch ID or password), and it works from your
  own Bash tool. So write the root work to `apply-root.sh`, keep it to a single
  osascript call, and run it yourself.

  **Never build a homemade password box** (`display dialog ... with hidden answer`
  feeding `SUDO_ASKPASS`). It is indistinguishable from a phishing prompt and teaches
  the user a dangerous habit. The system dialog is strictly better.

  **Homebrew is the one thing this cannot do.** `brew` refuses to run as root, so
  `pkg`-installer casks (macFUSE, Docker, RealVNC…) still need a real Terminal window.
  Hand the user those specific commands and say why — do not try to script around it.
- **Before handing it over, show what the script will do** as a short bullet list, and
  say it will ask for their password once.
- Try `sudo -n true` first. If a credential happens to be cached you can run sudo
  steps directly and skip the script entirely. Don't count on it.
- Build the script from the fixes they actually picked — not everything you found.

### Retiring a background service — the full recipe

A service has **up to four independent anchors**. Miss one and it survives or returns.
Handle all four, in this order, or the "retirement" is cosmetic:

| # | Anchor | Command | Sudo? |
|---|---|---|---|
| 1 | System daemon | `sudo launchctl bootout system/<label>` then move plist from `/Library/LaunchDaemons` | yes |
| 2 | System agent | `launchctl bootout gui/$(id -u)/<label>` then move plist from `/Library/LaunchAgents` | move needs sudo |
| 3 | **User agent** | `launchctl bootout gui/$(id -u)/<label>`, move from `~/Library/LaunchAgents` | **no** |
| 4 | **BTM / SMLoginItem** | app's own `defaults write … OpenAtLogin -bool false`, or `osascript … delete login item` | **no** |

- **Check `launchctl list \| grep -i <vendor>` before declaring it done.** Anchors 3 and 4
  are invisible in `/Library/` and are the usual reason a killed process reappears within
  seconds. CleanMyMac's `HealthMonitor` and `Menu` live in the *user* domain even though
  its `Agent` is a system daemon.
- **A moved plist does not stop a running service.** launchd keeps the loaded job in
  memory; `bootout` must come *before* the `mv`, and a root-owned process that respawns
  anyway needs `sudo launchctl bootout` or a reboot. Say which, and don't burn a second
  password prompt on a 9 MB straggler — note it clears at reboot.

### Kill patterns must come from `ps`, never from the app's name

**This is the single most common way an apply script silently under-delivers.** Vendor
process names rarely match the product name:

| You'd guess | Actually runs as |
|---|---|
| Adobe Creative Cloud | `Creative Cloud Content Manager.node`, `Adobe Crash Processor` |
| CleanMyMac | `com.macpaw.CleanMyMac4.HealthMonitor`, `…Menu` |
| Wispr Flow | 11 processes, ignores `osascript … quit` |

Before writing any `pkill`, dump the real names and build the pattern from that output:

```bash
ps -axo pid,rss,comm | grep -i <vendor> | grep -v grep
```

**Always verify after killing** — re-run the same `grep` and report what survived. Never
report a service as retired without that second check.

### Measuring — settle before you believe

- **Never measure inside the apply script.** A `sleep 3` before/after on a busy Mac
  measures scheduler noise: one run showed processes *rising* and free RAM *falling*
  immediately after retiring 578 MB of services. **Do not publish that output** — take
  the script's numbers as informational only.
- **Settle ≥ 30 s** before any post-change measurement, and prefer `top -l 3` (discard
  the first sample — it is a cumulative average since boot, not an instant reading).
- **Compare like for like**: same command, same settle time, both sides.
- **`compressor` and `swap used` are the honest memory metrics.** `unused` swings wildly
  second to second because macOS opportunistically fills free RAM; a single `unused`
  reading proves nothing on its own.
- Re-measure everything once at the end, in one command, and let *that* be the scoreboard.

## Verification rules

- **`du` overcounts APFS clones. Never bank a `du` figure as reclaimable until a delete
  of a sample moves `df`.** Chrome's `/private/var/folders/*/X/com.google.Chrome.code_sign_clone`
  showed 60 copies, 125 GB by `du`. They are `clonefile()` copies sharing blocks with
  `Chrome.app`. Deleting 59 freed ~1 GB (2026-10-29), after the report had promised
  123 GB. Same trap: any `*.code_sign_clone`, Xcode/Finder duplicates, iMazing versions.
  Delete one item, measure `df`, then extrapolate. Also, when user-visible `du` totals fall
  far short of the volume's `Volume Used Space`, the gap is root-only dirs or snapshots;
  measure it with a root `du -xhd1 /System/Volumes/Data` before naming a cause.
- **Never purge temp or cache folders by file age.** Apps keep live data there, and an old file is not an unused file. List each top-level folder with size and newest file date, and offer it as a pick. Never offer a folder that holds the path of a running process, or one named after an installed app until you know it holds only cache.
- **Measure disk with BOTH numbers, always.** `df` free space and
  `diskutil info / | grep "Container Free Space"` disagree whenever an APFS snapshot
  pins deleted files, and on a machine taking hourly local snapshots that is *most of
  the time*. On 2026-09-20, 8 GB of files were deleted and `df` moved by **zero**; a
  snapshot taken mid-delete held all of it. Quoting `df` alone will make you report a
  cleanup as a failure — or a regression you did not cause. Thinning snapshots is what
  realises the space: two passes took 25 → 8 snapshots and free space 69 → 80 GB.
- **A launchd job that is not loaded frees nothing.** Check
  `launchctl list | grep <label>` (or `launchctl print`) before you put a number on
  retiring it. On 2026-09-20 all 8 "dead" jobs were `loaded=0`, so retiring them
  returned **0 MB and 0 % CPU**. It is still worth doing for attack surface — but say
  that, and never bank it as a performance win.
- **Never remove a package because a same-named binary exists elsewhere.** Check what
  it *uniquely* provides first. `openclaw` was installed by both npm and a cask; npm
  owned the `PATH` symlink, so the cask looked redundant — but it was the only source
  of `/Applications/OpenClaw.app` (npm ships a CLI only). Removing it deleted the GUI
  app, and Homebrew's own purge then deleted the backup it had just made. `brew info
  --cask <name>` lists the artifacts; read them before uninstalling.
- **Check for open documents before quitting an app group.** `ps | grep -i adobe`
  returned 11 processes that looked like background helpers — one was
  `Adobe Photoshop 2026` with the user's work in it. Dump the full list and read every
  name before building the kill pattern. Quit the helpers, leave the editor.

These exist because each one has already caught a wrong diagnosis.

- **A cached DNS lookup cannot fail.** Testing `github.com` through the system
  resolver proves nothing — mDNSResponder serves it from cache. Use random
  never-seen names, and query the resolver directly with `dig @<server>`.
- **Separate a bad resolver from a starved client.** If failures shrink as the
  timeout grows (3/15 at 1s, 0/15 at 5s), the resolver is fine and *this Mac* is too
  loaded to answer in time. Fix the load, not the DNS. Check `load1 ÷ cores` before
  blaming any network component.
- **Verify the owning app exists before calling a launchd job orphaned.** The scan's
  `REVIEW` tier flags jobs that only invoke `/usr/bin/osascript` or `/bin/sh` —
  nothing is missing on disk even when the vendor app was deleted years ago. Check
  `/Applications` and `/Library/Application Support` for the vendor yourself.
- **Don't infer a cause from a plausible story.** Test it. "Spotlight is churning
  because the sync folder changes constantly" is checkable in one command
  (`mdfind -onlyin <dir>`) — and has been wrong.
- **Two installs of a thing are not automatically fighting.** Confirm both are
  actually running before blaming a conflict. Check for the *process*, not the
  leftover config.
- **Distinguish a burst from a steady state.** Sample twice, minutes apart. Transient
  indexing work completes on its own and needs no fix.
- **Confirm a knob is actually connected before concluding from it.** `mssdflt` only
  applies when the path MTU is unknown; on a normal 1500-MTU interface macOS derives
  MSS from the interface and ignores it. Sweeping a setting that does nothing produces
  a uniform row of failures that reads exactly like a ruled-out hypothesis. If every
  value gives an identical result, suspect the knob before believing the conclusion.
- **Another machine on the same LAN is the best instrument available.** If a Windows
  box on the same network doesn't have the problem, everything shared is innocent —
  the router, the tunnel, the exit IP, the ISP, the remote service. Ask early.
- **`scan.sh` splits program paths on spaces — every space in a path becomes a fake
  "missing file".** `/Applications/Utilities/Adobe Creative Cloud/…` reports as three
  missing files and the job is called an ORPHAN. On a 2026-08-02 run **all 11 flagged
  orphans existed on disk**. Never repeat an ORPHAN line without re-resolving it:
  `/usr/libexec/PlistBuddy -c "Print :Program" <plist>` (fall back to
  `:ProgramArguments:0`), then test that one path with `[ -e ]`. The tell that run: a
  job flagged as orphaned while burning 96% CPU.
- **Uptime first — a load average under ~10 minutes of uptime is a boot burst.** One
  scan measured 405 on 10 cores at 3 minutes up; it decayed to 12 in twenty minutes with
  no intervention. Sample the curve before naming load a fault, and check whether memory
  moves with it. **Load falling while memory stays flat means the memory is the finding
  and the load was noise.**
- **A tunable with no persistence mechanism is a kernel default, not a tweak.** Before
  "fixing" any `sysctl` deviation, prove something re-applies it: check `/etc/sysctl.conf`,
  `/etc/sysctl.d`, launchd jobs invoking `sysctl`, and grep for the tunable name. If
  nothing sets it and it survived a reboot, it *is* the default. On **macOS 27**,
  `net.inet.tcp.mssdflt = 512` and `net.inet.tcp.win_scale_factor = 3` are stock — the
  "should be 1460" row in the pathologies table below is stale for this OS.
- **Look for a second config before declaring a config fixed. For MCP there are
  THREE places.** (1) `~/Library/Application Support/Claude/claude_desktop_config.json`
  → `mcpServers`, (2) `~/Library/Application Support/Claude/Claude Extensions/` with
  `extensions-installations.json` — MCPB extensions, which is where Desktop Commander
  actually lives, so an empty `mcpServers` does **not** mean "no servers", and
  (3) `~/.claude.json` for the agent, global *and* per-project. Trimming one leaves
  the others resident. Two more traps: `allowedDirectories: []` in Desktop Commander
  means **unrestricted**, not locked down (`dist/tools/filesystem.js`), and per-server
  logs are **UTC** while `main.log` is **local** — the same event looks hours apart
  across the two files. Same trap for login items vs `~/Library/LaunchAgents` vs
  `sfltool dumpbtm`. Check `ps -o ppid=` on a survivor to find who really spawned it.
- **Grep for a process name, not a substring.** "Stash" matched `@upstash/context7-mcp`,
  "Fing" matched Apple's `…SELFIngestor`, and **"edge" matched `knowledge-agent`,
  `siriknowledged` and `spotlightknowledged`** — that last one nearly had Apple's
  Spotlight daemons killed as "Microsoft Edge helpers" while Edge was not running at
  all. Anchor the pattern or verify each hit's full path, every time.

## Homebrew during a tune-up

**Updating software can make disk space WORSE. Plan for it.** A 14-cask upgrade run
pulled ~8 GB of downloads, an hourly snapshot caught them mid-flight, and free space
went 69 → 61 GB. Always: clean the cache afterwards, then thin snapshots, then
re-measure. Never report the mid-upgrade disk figure.

**Three separate places hoard gigabytes:**

| Location | 2026-09-20 | Cleared by |
|---|---|---|
| `$(brew --cache)` | 1.7 GB | `brew cleanup --prune=all` |
| `/opt/homebrew/var/homebrew/tmp/.caskroom/` | **4.1 GB** | nothing — `rm -rf` its contents yourself |
| `/opt/homebrew/Caskroom/<orphan>/` | 2.1 GB (Docker) | remove the directory |

That middle one is staging left by **failed** installs and `brew cleanup` does not touch
it. Check it after any run where casks errored.

**`HOMEBREW_DOWNLOAD_CONCURRENCY=1` fixes a crashing fetch.** `brew install --cask` died
three times with a Ruby backtrace at `download_queue.rb:289 → Concurrent::Event#wait`;
serial download worked first try. Reach for this on any brew Ruby backtrace during a
fetch, before assuming the cask or the network is at fault.

**A cask whose app was hand-deleted can never upgrade — and that is the source of
recurring "install this app?" prompts.** It fails
`It seems the App source '/Applications/X.app' is not there` forever. Users click Cancel
for months without knowing why. Find them:

```bash
for c in $(brew list --cask); do
  app=$(brew info --cask "$c" 2>/dev/null | grep -oE "/Applications/[^ ]*\.app" | head -1)
  [ -n "$app" ] && [ ! -e "$app" ] && echo "$c -> $app MISSING"
done
```

`brew list --cask` just enumerates `/opt/homebrew/Caskroom/*`, so **removing that
directory both deregisters the cask and reclaims its payload** — which is the way out
when `brew uninstall --cask` itself demands sudo for system paths that are already gone.
Before doing that, confirm the system artifacts really are absent (privileged helpers,
`/Library/LaunchDaemons`, `/usr/local/bin` symlinks); if any remain, remove them as root
first.

**Some casks are disabled upstream and are simply unfixable.** `chromium` was disabled
2026-09-01 for failing macOS Gatekeeper; `caprine` and `chromedriver` likewise. They
will sit in `brew outdated` forever. Say so once and stop offering to fix them.

**A cask is not a candidate for removal just because you do not recognise it.** Ask.
The user is the one who knows they stopped using Warp six months ago — and that same
answer is what tells you the prompts they have been cancelling are safe to kill.

## Heat — check before any process hunt

A hot Mac feels like a hidden process: every app is slow and no process stands out.
Read the sensors yourself. Never ask the user for a screenshot.

- **Run `thermal.sh` first, while the Mac is slow.** It needs no sudo.
- **Pressure level:** 0 nominal, 1 moderate, 2 or higher is real throttling.
- **Temperatures and power need macmon on Apple silicon.** With the user's yes: `brew install macmon`.
- **Temperature at a given power is the finding.** High temperature at low `CPU_WATTS` is a cooling fault. High temperature at full load can be normal.
- **Read the load.** A load average far above `CPU_COUNT` explains slowness without any heat. Find the jobs before you blame the hardware.
- **Fanless Macs throttle by design.** A MacBook Air under sustained load is not faulty.
- **Fix order.** Clear the vents, clean the fans, then consider service. Do not suggest a repaste on a soldered Apple silicon Mac as a home job.

## Do not become the load

- **Check the Mac before you add work.** If it is hot or slow, do the light checks first.
- **Run sweeps with `nice -n 19`, one at a time.**
- **Other agents count.** Look for parallel tests, builds, and scans before you blame an app. Do not pause another agent's work unless the user asks.
- **If the user says it is slow, stop your own jobs first, then measure.**

## Known pathologies

| Symptom | Usual cause | Notes |
|---|---|---|
| `coreaudiod` pegged at 100%+ | Many virtual audio HAL drivers | `coreaudiod` loads every driver in `/Library/Audio/Plug-Ins/HAL/` in-process. 10+ is a red flag. |
| `mssdflt` ≠ 1460 | An "optimizer" app applied a dial-up-era tweak | **Only if a launchd job re-applies it.** On macOS 27, 512 is the stock default — prove persistence exists before touching it. |
| Deleting files frees no space | An APFS snapshot taken *before* the delete still pins them | Compare snapshot timestamps to the delete. Either `sudo tmutil thinlocalsnapshots / <bytes> 4` or wait ~24 h for it to age out — say which, and that thinning is not reversible. `diskutil info` "Container Free Space" vs `df` reveals the purgeable gap. |
| Load high, CPU mostly idle | Memory compressor, not CPU | High `sys%` with idle CPU means the compressor is working. Fix memory; CPU headroom is irrelevant. |
| Startup cruft | Uninstalled apps leaving launchd jobs | Cleaner suites are the worst offenders and often orphan themselves. |
| `load ÷ cores` > 2 | Too many resident background apps | Causes network timeouts that masquerade as ISP/DNS faults. |
| `mds`/`corespotlightd` hot | Indexing, often semantic/AI embeddings | Usually legitimate transient work. **Never** erase the index — that forces a worse full rebuild. |
| Many `utun` interfaces | Several VPN stacks resident | Each adds MTU/routing complexity. |
| Uploads die, downloads fine | MTU too big for a tunnel on the **router** | Downloads, browsing and DNS all look healthy — only large POSTs reset. Lower `en0` MTU until a 1 MB POST completes. Real fix is MSS clamping on the router. |
| Heavy swap with RAM free | A "memory purge/booster" utility | These *cause* swapping by dropping the file cache. |
| Swap stays full after freeing GB of RAM | macOS never shrinks the swap file while running | **Only a reboot clears it.** Quitting apps cannot. Report the compressor as the win and name the reboot as the fix — do not promise a swap drop you cannot deliver. |
| Freed RAM does not show in `unused` | macOS refills it with file cache within seconds | Expected. `unused` is not a scoreboard metric; compressor and swap are. |
| One app pegged at ~100 % CPU for days | A runaway that nobody noticed | Check `etime` in `ps`. An OBS instance had burned 88–100 % for **3 d 20 h** and was dragging `WindowServer` to 71 %. Restarting it was the single biggest win of the session — but **ask first**, it may be a live capture or stream. |
| Bundled-app MCP server "cannot find node" | It does not use your `PATH` | Claude Desktop ships its own Node (`Using built-in Node.js for MCP server: …` in `main.log`). Never debug PATH for it. |

## Reporting

**Write an HTML file to disk and open it locally. Never publish it.** These reports
describe the user's machine, network topology and IP addresses — that stays on the
machine. **Do not call the Artifact tool for a tune-up report.**

```bash
mkdir -p ~/Downloads/Claude-MacTuneUp
REPORT=~/Downloads/Claude-MacTuneUp/mac-health-$(date +%Y-%m-%d-%H%M).html
cp <skill-folder>/report-template.html "$REPORT"
# …fill in the data…
ln -sfn "$REPORT" ~/Downloads/Claude-MacTuneUp/latest.html   # stable pointer
open "$REPORT"
```

- **One file per run**, timestamped, so past tune-ups stay comparable. `latest.html`
  always points at the newest.
- **As findings firm up, rewrite the same file** and tell the user to refresh the tab.
  Never start a second file mid-run.
- `open` uses their default browser. Say the filename in chat so they can find it again.

**Fill `report-template.html`, and do not redesign it.** It is one self-contained, minimal page: actions and findings first, collapsible detail below, and a jump bar at the top. Do not add decoration. Copy it to the report path. Then replace only the JSON inside `<script id="report-data">`.

- **Remove `"example": true`.** That key prints "sample data" on the page.
- **Delete a key to hide its section.** Never leave sample values on the page.
- **`mood`:** `happy`, `ok`, `hot`, or `sad`. Use `hot` when heat is the top finding.
- **`score`:** start at 100. Take off 25 for a heat limit, 15 for a disk over 90% full, 10 for each other serious finding, and 3 for each minor one. Never use a score to flatter a machine.
- **`s` values:** `good`, `warn`, `hot`, or `info`.
- **Check the page.** It needs no network. In strings, only `<b>` works as markup. JSON-escape backslashes in paths.

### Voice — this is a product, not a lab notebook

- **Bullets, not paragraphs.** Prose only where a bullet genuinely can't carry it. A
  reader should get the whole picture by scanning.
- **Never narrate your own process.** No "I got this wrong", no "correction", no "my
  earlier grep misfired", no "two of my own greps". The reader wants the state of their
  Mac, not a diary of how you arrived at it. **Wrong findings are deleted, not confessed.**
- Self-correction belongs in *chat*, once, briefly — never on the page.
- No hedging filler ("it seems", "possibly worth noting"). State the finding.
- Numbers carry the argument: `1401 MB / 31 proc`, not "uses a lot of memory".

### No commands in the report — exactly one exception

**The report is a snapshot, not a runbook.** The user reads it to see what they're working
with and what's up; *you* run the commands, in the agent. A page full of shell they'd
have to copy is the thing they didn't want.

- **Never** put `sudo …`, `launchctl …`, `pkill …`, `tmutil …`, `defaults write …`, or a
  "how to undo" command block on the page. Recommendations say **what** and **why**, with
  cost and effort tags — never **how**.
- Settings, paths and process names as *facts* are fine and good: `mssdflt 512`,
  `/etc/hosts`, `corespotlightd`, `utun`. A fact is not an instruction — the test is
  whether the reader is meant to type it.
- **The one exception:** commands the user genuinely must run themselves, in the
  `#pending-sudo` block (already in the template, `hidden` by default — unhide it).
  Since you now run root work via osascript, this is normally just the Homebrew
  `pkg`-cask upgrades that cannot run as root. One or two lines, no more. Swap the
  block for the "Applied" card once done.
- Undo instructions live in `apply.sh`'s own output and in chat, never on the page. The
  page just names the backup directory.

### Report data

The page puts `vitals`, `offers`, `findings`, and `space` first. Network, market, machine, and cleared items start collapsed.

1. **`machine`, `headline`, `summary`, `mood`, `score`.** The headline states the top problem in plain words. `mood` only sets the small status icon.
2. **`vitals`:** CPU heat, CPU speed, memory, main disk, internet, background load. Measured values only.
3. **`spec`:** model, CPU, GPU, memory, OS, storage, uptime.
4. **`market`:** how good this machine is today. See *Market check*.
5. **`space`:** every mounted volume, internal and external, with a ranked list of its top 10 or so items as `{ "l", "n", "gb", "s" }`. `items` holds only the ones with an offer.
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

- Baseline = the **settled** figure, not the boot-burst peak. Quoting load 405 as the
  "before" when it was a 3-minute-uptime artefact inflates the win and is dishonest.
- If a change didn't help, keep the row and mark it flat. Say so in chat too.
- Never publish numbers from `apply.sh`'s inline before/after (see *Measuring*).
- Attribute honestly: a reboot pending, or Spotlight finishing on its own, is not
  something the tune-up did.

## Asking

**Always use the the question tool tool.** Never end a report with a freeform "tell me which
numbers" — it makes the user compose a list by hand from a long page. Give them clickable
options instead.

- **State your recommendation first**, in prose, then ask. They should be choosing against
  a recommendation, not from a blank menu. Mark the recommended option `(Recommended)` and
  put it first.
- **Batch by category, not one question per item.** 4 questions × 4 options is the ceiling.
  Group login items, background daemons, disk reclaim, and network changes into their own
  questions with `multiSelect: true`.
- **Put the cost in the description** — RAM, CPU, process count, GB. "Microsoft Edge Beta —
  ~900 MB across helpers" beats "browser".
- **Never list a must-keep item as an option.** Sync daemons (Syncthing), the VPN that
  carries their traffic, licensing helpers — exclude them and say in prose why. Offering to
  disable Syncthing is how you break someone's file sync.
- **When an answer contradicts their own documented setup, flag it once and re-ask.**
  Answers get inverted — "keep X" and "X is the one I don't use" look identical in a
  multi-select. If the answer would break something their notes say they depend on, show
  the consequence and confirm. Once they reaffirm, do it without further argument.
- Re-ask with the tool at each new decision point, not just once at the end.

## Change rules

- **Move, never delete.** Everything goes to `~/mac-tuneup-bak-<date>/`. Tell the
  user how to reverse it.
- **One script, shown before it runs.** No silent edits scattered across turns.
- **User files are the user's call.** Never delete documents, downloads, or media
  without an explicit yes on that specific file, with its size and path shown.
- **Check what's running before restarting a system daemon.** `killall coreaudiod`
  during a recording or call loses work — check for OBS, Zoom, Teams, QuickTime first.
- **Never touch:** the Spotlight index (erasing forces a full rebuild), FileVault,
  SIP, Gatekeeper, kernel extensions, `/System`, keychains.
- **Ask before disabling anything the user might rely on** — VPNs, sync daemons,
  backup agents, licensing helpers. Removing a licensing helper to reclaim 0% CPU is
  a bad trade; say so.
- **Sync/backup tools deserve extra care.** Confirm what they depend on before
  changing DNS, network tunables, or hostname resolution, and confirm they still work
  after.
- **Quit apps gracefully first, then verify.** `osascript -e 'tell application "X" to quit'`
  lets browsers save session state — always try it before `pkill`. But **confirm it worked**:
  Wispr Flow ignored the quit entirely and needed `pkill`. Never assume a quit succeeded.
- **Warn before quitting anything holding live state** — a browser with unsaved tabs, a
  sync client mid-transfer, a VPN carrying the current connection.
- **Re-measure and report honestly.** If a fix didn't help, say it didn't — in the chat
  *and* in the Results table.

## Post-run

- **Offer, don't assume:** a final rewrite of the report file with the results scoreboard.
- **State what's left** — pending reboot, stragglers that clear at boot, anything deferred.
- **Point at the backup dir** `~/mac-tuneup-bak-<date>/` and how to reverse each change.
- **Don't leave a straggler hunt running.** A root-owned 9 MB process that clears at the
  next reboot is a footnote, not a second password prompt.
