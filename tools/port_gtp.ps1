$ErrorActionPreference = "Stop"
$root = "f:\GithubCode\MyBlog\TheGoldReaperEA"

# locate source folder without embedding CJK in this script (PS 5.1 reads .ps1 as ANSI)
$sub = [System.IO.Directory]::GetDirectories($root, "Gold Trade Pro*") | Select-Object -First 1
if (-not $sub) { throw "source folder not found" }
$src = Join-Path $sub "Gold Trade Pro.mq4"
if (-not (Test-Path -LiteralPath $src)) { throw ("source not found: " + $src) }

$outDir = Join-Path $root "MQL5\Experts\GoldTradePro"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$dst = Join-Path $outDir "Gold Trade Pro MT5.mq5"

$c1 = [string][char]0x6797
$c2 = [string][char]0x8F69
$c3 = [string][char]0x6587
$c4 = [string][char]0x80DC

$lines = [System.IO.File]::ReadAllLines($src)
Write-Output ("source: " + $src)
Write-Output ("source lines: " + $lines.Count)

$out = New-Object System.Collections.Generic.List[string]
$nRename = 0; $nExtern = 0; $nStrict = 0; $nVersion = 0; $nInit = 0; $nDeinit = 0

for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]

    if ($l.IndexOf($c1) -ge 0 -or $l.IndexOf($c2) -ge 0 -or $l.IndexOf($c3) -ge 0 -or $l.IndexOf($c4) -ge 0) {
        $l = $l.Replace($c1, 'L').Replace($c2, 'X').Replace($c3, 'W').Replace($c4, 'S')
        $nRename++
    }

    if ($l -match '^\s*#property\s+strict') { $nStrict++; continue }

    if ($l -match '^\s*#property\s+version\s+""') {
        $l = '#property version   "1.00"'
        $nVersion++
    }

    if ($l -match '^\s*extern\s') {
        $l = $l -replace '^(\s*)extern(\s)', '$1input$2'
        $nExtern++
    }

    if ($l -match '^\s*int\s+init\s*\(\s*\)\s*$') { $l = 'int OnInit()'; $nInit++ }
    if ($l -match '^\s*int\s+deinit\s*\(\s*\)\s*$') { $l = 'void OnDeinit(const int reason)'; $nDeinit++ }

    $out.Add($l)
}

$insertAt = 0
for ($i = 0; $i -lt $out.Count; $i++) {
    if ($out[$i] -match '^\s*#property') { $insertAt = $i + 1 }
}
$hdr = @(
    '',
    '// ============================================================================',
    '// Gold Trade Pro - MT5 build (MQL4 -> MQL5 compatibility-layer port)',
    '// ----------------------------------------------------------------------------',
    '// Source   : Gold Trade Pro.mq4 (5779 lines, decompiled/reconstructed)',
    '// Method   : keep the original MQL4 logic untouched; run it on MQL5 through',
    '//            <MQL4Compat.mqh>. Automatic transforms applied by port_gtp.ps1:',
    '//              . CJK identifier prefixes -> ASCII (MQL5 allows ASCII only)',
    '//              . extern -> input; drop #property strict; fix #property version',
    '//              . int init()   -> int OnInit()',
    '//              . int deinit() -> void OnDeinit(const int reason)',
    '//            OnTick() already used that name in the source, unchanged.',
    '// NOTE     : this EA opens multiple concurrent positions -> HEDGING account.',
    '// DISCLAIM  : source origin unknown (shared group resource, batch-renamed',
    '//            decompiler output). Research only. Do not run on live funds.',
    '// ============================================================================',
    '',
    '#include <MQL4Compat.mqh>',
    '',
    ''
)
$hdrList = New-Object System.Collections.Generic.List[string]
foreach ($h in $hdr) { $hdrList.Add([string]$h) }
$out.InsertRange($insertAt, $hdrList)

[System.IO.File]::WriteAllLines($dst, $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("written: " + $dst)
Write-Output ("total lines: " + $out.Count)
Write-Output ("rename=" + $nRename + " extern=" + $nExtern + " strict=" + $nStrict + " version=" + $nVersion + " init=" + $nInit + " deinit=" + $nDeinit)
