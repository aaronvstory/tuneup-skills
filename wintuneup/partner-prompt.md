# Prompt to paste into Claude Code on another Windows PC

Copy everything below the line into Claude Code. It's self-contained — the other PC
doesn't need the `/wintuneup` skill installed.

---

I want you to do a careful health check of this Windows PC. It has felt slow and I don't
know why. **Scan and report first — do not change anything until I say so.**

Work read-only, then give me one report. Check all of these:

**Heat first**
- Read CPU temperature, power, and throttle limits yourself. Ask before you install HWiNFO for this. Never ask me for a screenshot.
- High temperature at low power is a cooling fault that looks like a hidden process.

**Performance — and check the instrument before you trust it**
- **First**, check whether the performance-counter registry is intact:
  `@((Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009').Counter).Count`.
  If that's near zero, `Get-Counter` and every `Win32_PerfFormattedData_*` class return
  **nothing**, and any script using them will report a perfectly idle machine no matter
  how loaded it is. In that case derive CPU from per-process CPU-time deltas
  (`Get-Process`, sample `.CPU` twice a few seconds apart, divide by elapsed time and by
  logical processor count) — and tell me the counters are broken, because that's its own
  finding.
- Memory: report **commit charge vs commit limit**, not just "available RAM" — available
  swings wildly because Windows fills free RAM with cache. `Memory Compression` holding
  several GB is normal, not a leak.
- Top CPU and memory processes, **grouped by process name** so a browser's 40 helpers
  show as one line. Sample **twice a few minutes apart** so you can tell a temporary
  burst from something genuinely stuck.
- Total process, thread and handle counts.
- Uptime — under ~10 minutes, everything you measure is a boot burst. Say so.

**Startup cruft — this is usually the biggest find**
- An app can start itself from **five** independent places. Check all five or a "removal"
  is cosmetic:
  1. `HKLM\...\CurrentVersion\Run` **and** `HKLM\SOFTWARE\Wow6432Node\...\Run`
     (a separate key, not a view — things hide there)
  2. `HKCU\...\CurrentVersion\Run`
  3. Startup folders: `shell:startup` and `shell:common startup`
  4. Scheduled Tasks — `Get-ScheduledTask | Where TaskPath -notlike '\Microsoft\*'`
  5. Auto-start services — `Get-CimInstance Win32_Service | Where StartMode -eq 'Auto'`
- For each, pull the executable and check it still exists. Anything missing is a leftover
  from an uninstalled app that still fires at every boot.
- **Critical parsing warning:** do **not** split a command line on whitespace to find the
  executable. `C:\Program Files\Vendor\App.exe -flag` would become three "missing files"
  and one healthy entry would be reported as broken. Parse the quoted token first, then
  fall back to a non-greedy match up to the first `.exe`. Also watch for values that are
  quoted **and** backslash-escaped: `"\"C:\path\app.exe\" --startup"`.
- **Two more false positives to avoid:** svchost-hosted services all share `svchost.exe`
  (never "missing"), and a bare name like `powershell.exe` resolves via `PATH`.
- Read the `StartupApproved` values so you can tell me which entries are **already
  disabled** — don't offer to disable those again.
- If several unrelated vendors all point at `C:\Users\<some-other-name>\...`, the finding
  is **one abandoned user profile**, not five broken apps. Check `Get-ChildItem C:\Users`.

**Explorer**
- List third-party context-menu handlers (`HKLM\SOFTWARE\Classes\*\shellex\ContextMenuHandlers`
  and the `Directory`, `Directory\Background`, `Folder`, `AllFilesystemObjects` variants),
  resolve each CLSID to its DLL, and flag any DLL that no longer exists. Explorer loads
  every handler in-process, so a missing one costs a failed load on every right-click and
  is invisible in Task Manager.

**Security stack**
- `Get-MpComputerStatus`. Read `AntivirusEnabled`, `RealTimeProtectionEnabled`,
  `AntivirusSignatureVersion`, `AntivirusSignatureLastUpdated` and
  `DefenderSignaturesOutOfDate` **together**. Real-time protection can report `True` while
  the signature version is empty — that means the engine is loaded with no definitions,
  which is not protection. A signature age of `65535` is the "never updated" sentinel.
- List `Get-MpPreference` exclusions. Flag any pointing at paths that no longer exist.
- Check `root\SecurityCenter2` for a second registered antivirus. Two real-time scanners
  inspecting each other's I/O is a genuine slowdown — but Defender demotes itself to
  passive automatically, so check `AMRunningMode` before claiming a conflict.

**Disk**
- Free space per volume, and bus type per physical disk (USB/removable is never a safe
  relocation target).
- **Shadow-copy store**: `vssadmin list shadowstorage /for=C:` (needs admin). Restore
  points pin deleted files — deleting something large may free nothing until the store is
  capped. If you can't run it elevated, say the value is **unknown**, not clean.
- Sizes of `%TEMP%`, `C:\Windows\Temp`, `C:\Windows\SoftwareDistribution\Download`,
  `C:\Windows\Installer`, `C:\Windows.old`.

**Network**
- Identify the active adapter from the **routing table**, not "first one that's Up" —
  with Wi-Fi and Ethernet both connected, interface status names the wrong one.
- `netsh int tcp show global` — compare against Windows defaults (auto-tuning `normal`,
  RSS enabled, ECN disabled). "Optimizer" apps and old forum guides wreck these.
- Per-interface MTU. A tunnel at 1280 next to a 1500 physical link is normal.
- Count virtual adapters and running VPN daemons.
- Check for an orphaned proxy config. Note that `ProxyServer` set with `ProxyEnable=0`
  is **inert** — don't report it as a cause of anything.

**DNS — test it properly**
- Do **not** test a common name through the system resolver; it comes back from cache and
  always passes. Use random labels that were never looked up, aimed at a specific server.
- **NXDOMAIN is a successful lookup** — the server answered. Only timeouts count.
- Run at a 1-second timeout and again at 5 seconds. If failures shrink as the timeout
  grows, the resolver is fine and the PC is just too loaded to answer in time — fix the
  load, don't blame the network.

**Devices**
- `Get-CimInstance Win32_PnPEntity | Where ConfigManagerErrorCode -ne 0`.
- Error **22 means the user disabled it deliberately** — don't offer to "fix" those.
  Code 28 (no driver) on `ROOT\USBDEVICE\*` is a genuine ghost-device pile. Code 31 is a
  driver that failed to load.

**Then give me:**
1. A short plain-English verdict on the PC's overall condition
2. A vitals table
3. Findings ordered by impact, each with the evidence you actually observed
4. Numbered recommendations — what, why, whether it needs admin, how to undo it
5. A "checked out fine" list so I know what you ruled out

**When I pick fixes:**
- **Take a System Restore point first.** `Checkpoint-Computer`. If it fails, stop and tell
  me — a tune-up without an undo isn't worth it.
- Do everything that doesn't need admin yourself — don't make me paste commands.
- Put everything that *does* need admin into one self-elevating script, then give me one
  line to run it in the form `! powershell -ExecutionPolicy Bypass -File <path>`. The `!`
  prefix runs it in my terminal so the UAC dialog can appear. Your own shell can't
  elevate — don't try.
- Tell me what the script does before I run it.

**Rules while you work:**
- Verify before you conclude. If you have a theory, test it — don't tell me a plausible
  story you haven't checked.
- Sample twice before calling something a permanent problem.
- **Disable, never delete.** Export a scheduled task to XML before disabling it, export a
  registry key before removing a value, record a service's StartMode before changing it.
  Move files to `%USERPROFILE%\win-tuneup-bak-<date>\`. Never `sc delete`.
- Don't touch my documents, downloads, or media without asking about that specific file,
  showing me its size and path.
- Don't touch BitLocker, Secure Boot, Tamper Protection, Defender real-time protection,
  the Windows Search index, `C:\Windows\Installer` by hand, or run `DISM /ResetBase`.
- Ask before disabling VPNs, sync clients, backup agents, remote-access hosts, or
  licensing helpers.
- If something is idling at ~0% CPU, say it's not worth removing rather than padding the
  list.
- State security findings factually. Report what's configured and what it exposes — how
  it got there isn't the report's business unless I ask.
- Tell me honestly if a fix didn't help.

Start with the scan and show me the report.
