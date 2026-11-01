<#
  Self-check for Get-ExePath - the one piece of non-trivial parsing in the scan.

  It exists because command-line parsing is where this whole class of tool goes wrong:
  split a Program Files path on whitespace and one healthy entry becomes three
  "missing files", which is how a scanner confidently invents findings.

      powershell -ExecutionPolicy Bypass -File test-parse.ps1
#>
$ErrorActionPreference = 'Stop'

function Get-ExePath([string]$cmd) {
    if ([string]::IsNullOrWhiteSpace($cmd)) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c -match '^"\\"') { $c = ($c -replace '^"','' -replace '"$','') -replace '\\"','"' }
    if ($c -match '^\s*"([^"]+)"')                                         { return $matches[1] }
    if ($c -match '^\s*([A-Za-z]:\\.*?\.(?:exe|com|bat|cmd|scr|dll|msc))(?:\s|,|$)') { return $matches[1] }
    if ($c -match '^\s*(\S+\.(?:exe|com|bat|cmd|scr))(?:\s|$)')            { return $matches[1] }
    return $null
}

# Every case here is a real value observed in a live registry / task store.
$cases = @(
    @{ in = '"\"C:\Users\me\AppData\Local\AnthropicClaude\claude.exe\" --startup"'
       out = 'C:\Users\me\AppData\Local\AnthropicClaude\claude.exe'; why = 'quoted AND backslash-escaped' }
    @{ in = '"C:\Program Files\TightVNC\tvnserver.exe" -controlservice -slave'
       out = 'C:\Program Files\TightVNC\tvnserver.exe'; why = 'quoted path + args' }
    @{ in = 'C:\Program Files\Elgato\ControlCenter\ControlCenter.exe -runinbk'
       out = 'C:\Program Files\Elgato\ControlCenter\ControlCenter.exe'; why = 'UNQUOTED path with spaces - the classic trap' }
    @{ in = 'C:\Windows\system32\rundll32.exe C:\Windows\System32\LogiLDA.dll,LogiFetch'
       out = 'C:\Windows\system32\rundll32.exe'; why = 'rundll32 host (the DLL is the real payload)' }
    @{ in = 'C:\WINDOWS\system32\rundll32.exe "C:\Program Files (x86)\Stardock\Fences\FencesMenu64.dll",StartFencesAsUser'
       out = 'C:\WINDOWS\system32\rundll32.exe'; why = 'rundll32 with a quoted DLL argument' }
    @{ in = '"%AppData%\Preme for Windows\bin\preme.exe" logon'
       out = "$env:APPDATA\Preme for Windows\bin\preme.exe"; why = 'environment variable expansion' }
    @{ in = 'powershell.exe -NoProfile -Command "Checkpoint-Computer -Description x"'
       out = 'powershell.exe'; why = 'bare interpreter - resolves via PATH, never an orphan' }
    @{ in = ''; out = $null; why = 'empty' }
)

$fail = 0
foreach ($c in $cases) {
    $got = Get-ExePath $c.in
    if ($got -eq $c.out) { "  PASS  {0}" -f $c.why }
    else { $fail++; "  FAIL  {0}`n        in:       {1}`n        expected: {2}`n        got:      {3}" -f $c.why, $c.in, $c.out, $got }
}
if ($fail) { "`n$fail of $($cases.Count) FAILED"; exit 1 } else { "`nall $($cases.Count) passed"; exit 0 }
