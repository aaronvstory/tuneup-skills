#Requires -Version 5.1
<#
Read-only disk accounting, at low priority. Run elevated for the allocation summary.
  powershell -ExecutionPolicy Bypass -File disksweep.ps1      (every connected drive, one at a time)
  powershell -ExecutionPolicy Bypass -File disksweep.ps1 C:   (one drive)
Prints the NTFS allocation summary, then folders and files over the limit.
Junctions and symlinks are never followed, so a linked folder counts once, on its real drive.
#>
param([string]$Drive, [int]$MinGb = 5, [int]$MaxDepth = 5)
try { (Get-Process -Id $PID).PriorityClass = 'BelowNormal' } catch {}

Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO;
public static class TuneUpSweep {
  public static List<string> Lines = new List<string>(); public static int Errors;
  public static long Walk(string dir, int depth, long min, int maxDepth) {
    long total = 0; DirectoryInfo info = new DirectoryInfo(dir);
    FileSystemInfo[] items;
    try { items = info.GetFileSystemInfos(); } catch { Errors++; return 0; }
    foreach (FileSystemInfo i in items) {
      try {
        if ((i.Attributes & FileAttributes.ReparsePoint) != 0) continue;
        if ((i.Attributes & FileAttributes.Directory) != 0) { total += Walk(i.FullName, depth + 1, min, maxDepth); continue; }
        long n = ((FileInfo)i).Length; total += n;
        if (n >= min) Lines.Add(String.Format("{0,9:N1} GB  FILE {1}", n / 1073741824.0, i.FullName));
      } catch { Errors++; }
    }
    if (depth <= maxDepth && total >= min) Lines.Add(String.Format("{0,9:N1} GB  DIR  {1}", total / 1073741824.0, dir));
    return total;
  }
}
'@
$drives = if ($Drive) { @($Drive.TrimEnd('\', ':') + ':') } else {
    [IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -in 'Fixed', 'Removable' } | ForEach-Object { $_.Name.TrimEnd('\') }
}
foreach ($Drive in $drives) {
    $d = [IO.DriveInfo]::new($Drive + '\')
    "########## $Drive {0:N0} GB free of {1:N0} GB, {2}, label '{3}' ##########" -f ($d.AvailableFreeSpace / 1GB), ($d.TotalSize / 1GB), $d.DriveType, $d.VolumeLabel
    '===== ALLOCATION (what folder tools cannot see) ====='
    fsutil volume allocationReport $Drive 2>&1 | Select-String -Pattern '^(Total|Free|Allocated) clusters|^System files|^System Volume|^User files|under \$Txf|^\s+Allocated\s+:|\$Mft\s*$' | ForEach-Object { $_.Line.TrimEnd() }
    [TuneUpSweep]::Lines.Clear(); [TuneUpSweep]::Errors = 0
    $total = [TuneUpSweep]::Walk("$Drive\", 0, [long]$MinGb * 1GB, $MaxDepth)
    "===== COUNTED {0:N0} GB, unreadable {1} =====" -f ($total / 1GB), [TuneUpSweep]::Errors
    [TuneUpSweep]::Lines | Sort-Object { ($_ -split ' GB')[0].Trim() -replace ',', '' -as [double] } -Descending
}
