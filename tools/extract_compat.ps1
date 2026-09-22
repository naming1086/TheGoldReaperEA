$ErrorActionPreference = "Stop"
$src = "f:\GithubCode\MyBlog\TheGoldReaperEA\MQL5\Experts\GoldReaper\The Gold Reaper English MT5.mq5"
$dstDir = "f:\GithubCode\MyBlog\TheGoldReaperEA\MQL5\Include"
if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }
$dst = Join-Path $dstDir "MQL4Compat.mqh"

$lines = [System.IO.File]::ReadAllLines($src)

$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($startIdx -lt 0 -and $lines[$i] -match '#ifndef __MQL4COMPAT_MQH__') { $startIdx = $i }
    if ($startIdx -ge 0 -and $lines[$i] -match '#endif // __MQL4COMPAT_MQH__') { $endIdx = $i; break }
}
if ($startIdx -lt 0 -or $endIdx -lt 0) { throw "boundary not found start=$startIdx end=$endIdx" }

Write-Output ("compat range: line " + ($startIdx+1) + " .. " + ($endIdx+1) + "  total " + ($endIdx-$startIdx+1))

$body = $lines[$startIdx..$endIdx]

$converted = 0
for ($i = 0; $i -lt $body.Count; $i++) {
    if ($body[$i] -match 'g_chartSymbol') {
        $body[$i] = $body[$i] -replace 'g_chartSymbol', 'Symbol()'
        $converted++
    }
}
Write-Output ("g_chartSymbol replaced lines: " + $converted)

$header = @(
    '//+------------------------------------------------------------------+',
    '//| MQL4Compat.mqh                                                    |',
    '//| MQL4 -> MQL5 compatibility layer (standalone include version)     |',
    '//|                                                                  |',
    '//| Source: extracted from The Gold Reaper English MT5.mq5 [S2].      |',
    '//| Purpose: run MQL4-style code (OrderSend/OrderSelect/OrderModify/  |',
    '//|          MarketInfo/iMA/Time* ...) under MQL5.                    |',
    '//|                                                                  |',
    '//| Only one change during extraction: g_chartSymbol -> Symbol(),     |',
    '//| so this include has no dependency on host EA globals.             |',
    '//|                                                                  |',
    '//| NOTE: hedging account is REQUIRED for multi-position EAs.         |',
    '//+------------------------------------------------------------------+',
    '',
    ''
)

$out = @()
$out += $header
$out += $body
$out += ''
$out += '//===================================================================='
$out += '// Standalone-include additions: helpers used by Gold Trade Pro'
$out += '//===================================================================='
$out += 'int AccountNumber() { return (int)AccountInfoInteger(ACCOUNT_LOGIN); }'
$out += 'string AccountName() { return AccountInfoString(ACCOUNT_NAME); }'
$out += 'double AccountFreeMargin() { return AccountInfoDouble(ACCOUNT_MARGIN_FREE); }'
$out += 'double AccountMargin() { return AccountInfoDouble(ACCOUNT_MARGIN); }'
$out += 'double AccountCredit() { return AccountInfoDouble(ACCOUNT_CREDIT); }'
$out += 'double AccountProfit() { return AccountInfoDouble(ACCOUNT_PROFIT); }'
$out += 'int AccountLeverage() { return (int)AccountInfoInteger(ACCOUNT_LEVERAGE); }'
$out += 'bool IsConnected() { return (bool)TerminalInfoInteger(TERMINAL_CONNECTED); }'
$out += 'bool IsTradeAllowed() { return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED); }'
$out += ''

[System.IO.File]::WriteAllLines($dst, $out, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("written: " + $dst)
Write-Output ("total lines: " + $out.Count)
