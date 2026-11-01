<#
Report self-check. Renders report-template.html in headless Chrome at desktop and phone width, for every mood.
Opens every section, then fails on horizontal overflow, clipped text, or an empty status icon. Skips cleanly with no Chrome.
#>
param([string]$Path = (Join-Path $PSScriptRoot 'report-template.html'))
$chrome = @((Get-Command chrome -ErrorAction SilentlyContinue).Source, 'C:\Program Files\Google\Chrome\Application\chrome.exe', 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe') | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $chrome) { 'SKIP no Chrome or Edge'; exit 0 }
$tmp = Join-Path $env:TEMP "tuneup-report-test-$PID"; New-Item -ItemType Directory -Force $tmp | Out-Null
$html = [IO.File]::ReadAllText($Path)
$fail = 0
foreach ($mood in 'happy', 'ok', 'hot', 'sad') {
    foreach ($w in 1280, 400) {
        # Chrome will not open a window under 500 px, so the page itself is held at the test width.
        $probe = "<script>addEventListener('load',function(){document.body.style.width='${w}px';document.querySelectorAll('details').forEach(function(d){d.open=true});var b=[];document.querySelectorAll('h1,h3,p,li,dd,dt,td,.pill,.v,.k,.n,.hop b,.gb,.what,summary,nav a').forEach(function(e){if(e.scrollWidth>e.clientWidth+1&&e.clientWidth>0&&getComputedStyle(e).display!=='inline')b.push(e.className+':'+e.textContent.slice(0,40))});var m=document.querySelector('svg.mascot'),g=m.querySelector('g').getBBox(),a=document.getElementById('app');document.body.setAttribute('data-r','app='+a.scrollWidth+' over='+b.length+' icon='+Math.round(g.width)+'x'+Math.round(g.height)+' sections='+document.querySelectorAll('details').length+' '+b.slice(0,4).join('|'))})</script>"
        $page = Join-Path $tmp "$mood-$w.html"
        $t = [regex]::Replace($html, '"mood":\s*"\w+"', "`"mood`": `"$mood`"")
        [IO.File]::WriteAllText($page, $t.Replace('</body>', $probe + '</body>'))
        $url = 'file:///' + ($page -replace '\\', '/')
        $out = & $chrome --headless=new --disable-gpu --disable-software-rasterizer "--window-size=$([math]::Max($w,600)),1000" "--user-data-dir=$tmp\p" --virtual-time-budget=1500 --dump-dom $url 2>$null | Out-String
        $r = if ($out -match 'data-r="([^"]*)"') { $Matches[1] } else { 'NO RESULT' }
        $bad = ($r -eq 'NO RESULT') -or ($r -notmatch ' over=0 ') -or ($r -match 'icon=0x') -or ($r -match 'app=(\d+)' -and [int]$Matches[1] -gt $w)
        if ($bad) { $fail++ }
        "{0} {1,-5} {2}: {3}" -f $(if ($bad) { 'FAIL' } else { 'ok  ' }), $mood, $w, $r
    }
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($fail) { "$fail failed"; exit 1 } else { 'all passed' }
