# Prompt to paste into Claude Code on another Mac

Copy everything below the line into Claude Code. It's self-contained — the other Mac
doesn't need the `/mactuneup` skill installed.

---

I want you to do a careful health check of this Mac. It has felt slow and I don't
know why. **Scan and report first — do not change anything until I say so.**

Work read-only, then give me one report. Check all of these:

**Performance**
- Load average vs actual core count (`sysctl -n hw.ncpu`) — flag if load ÷ cores > 2
- Top CPU and memory processes, sampled **twice a few minutes apart** so you can tell
  a temporary burst from something genuinely stuck
- Swap usage and pageouts
- Total process count

**Startup cruft — this is usually the biggest find**
- Every plist in `/Library/LaunchAgents`, `/Library/LaunchDaemons`, and
  `~/Library/LaunchAgents` (skip `com.apple.*`)
- For each, pull the `Program` / `ProgramArguments` and check whether the paths still
  exist. Anything missing = a leftover from an uninstalled app that still runs at
  every boot.
- **Important:** jobs that only run `/usr/bin/osascript` or `/bin/sh` will look fine
  because the interpreter exists. For those, check whether the *vendor's app* is
  still in `/Applications` or `/Library/Application Support`. Deleted "cleaner" and
  "optimizer" apps are the worst offenders — they leave jobs behind that keep running
  for years.
- Login items (`osascript -e 'tell application "System Events" to get the name of every login item'`)

**Audio**
- List `/Library/Audio/Plug-Ins/HAL/`. `coreaudiod` loads every driver there
  in-process; if there are lots, check whether `coreaudiod` is burning CPU. Tell me
  which drivers belong to apps I still have installed before suggesting removal.

**Network**
- Compare TCP tunables to macOS defaults, especially
  `net.inet.tcp.mssdflt` (should be **1460**) and `net.inet.tcp.win_scale_factor`
  (should be **4**). "Optimizer" apps wreck these and re-apply the damage at boot.
- Check `/etc/sysctl.conf` for persistent overrides
- Count `utun` interfaces and list running VPN daemons
- DNS config (`scutil --dns`)

**DNS health — test it properly**
- Do **not** test with a common name like `github.com` through the system resolver;
  it comes back from cache and always passes. Use random names that were never
  looked up, sent straight to the resolver with `dig @<server>`.
- Run the test at a 1-second timeout and again at 5 seconds. If failures shrink as
  the timeout grows, the resolver is fine and the Mac is just too loaded to answer in
  time — fix the load, don't blame the network.

**Disk**
- Free space, largest folders in home, and count APFS local snapshots
  (`tmutil listlocalsnapshots /`) — these pin deleted files, so deleting something
  large may free nothing until snapshots are thinned

**Then give me:**
1. A short plain-English verdict on the Mac's overall condition
2. A vitals table
3. Findings ordered by impact, each with the evidence you actually observed
4. Numbered recommendations — exact command, whether it needs sudo, how to undo it
5. A "checked out fine" list so I know what you ruled out

**When I pick fixes:**
- Do everything that doesn't need `sudo` yourself — don't make me paste commands.
- Put everything that *does* need `sudo` into one single script, then give me one
  line to run it in the form `! bash <path>`. The `!` prefix runs it in my terminal so
  sudo can ask for my password there. Your own shell has no terminal attached, so
  sudo won't work from it — don't try.
- Tell me what the script does before I run it.

**Rules while you work:**
- Verify before you conclude. If you have a theory, test it — don't tell me a
  plausible story you haven't checked.
- Sample twice before calling something a permanent problem.
- Never delete anything. Move things to `~/mac-tuneup-bak-<date>/` so it's reversible.
- Don't touch my documents, downloads, or media without asking about that specific
  file, showing me its size and path.
- Don't touch the Spotlight index, FileVault, SIP, Gatekeeper, or `/System`.
- Ask before disabling VPNs, sync tools, backup agents, or licensing helpers.
- If something is idling at ~0% CPU, say it's not worth removing rather than padding
  the list.
- Tell me honestly if a fix didn't help.

Start with the scan and show me the report.
