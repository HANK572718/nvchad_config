# Check environment variable expansion

Write-Host "=== 檢查環境變數設定 ===" -ForegroundColor Cyan
Write-Host ""

# Check MY_UNIX_TOOLS
$myUnixTools = [Environment]::GetEnvironmentVariable("MY_UNIX_TOOLS", "User")
Write-Host "MY_UNIX_TOOLS = $myUnixTools"

if ($myUnixTools -eq "C:\msys64_2\ucrt64\bin") {
    Write-Host "  [✓] MY_UNIX_TOOLS 設定正確！" -ForegroundColor Green
} else {
    Write-Host "  [✗] MY_UNIX_TOOLS 設定不正確或未設定" -ForegroundColor Red
}

Write-Host ""

# Check if PATH contains %MY_UNIX_TOOLS%
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
Write-Host "User PATH 內容："
Write-Host "  $userPath"
Write-Host ""

if ($userPath -like "*%MY_UNIX_TOOLS%*") {
    Write-Host "  [✓] PATH 包含 %MY_UNIX_TOOLS% 引用" -ForegroundColor Green
} else {
    Write-Host "  [✗] PATH 不包含 %MY_UNIX_TOOLS% 引用" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 當前 PowerShell 會話的展開結果 ===" -ForegroundColor Cyan

# Check expanded PATH in current session
$expandedPath = $env:Path -split ';' | Where-Object { $_ -like '*msys*' }

if ($expandedPath) {
    Write-Host "展開後的 MSYS 路徑："
    foreach ($path in $expandedPath) {
        Write-Host "  - $path"
    }
} else {
    Write-Host "  [✗] 展開後的 PATH 中沒有 MSYS 路徑" -ForegroundColor Red
    Write-Host ""
    Write-Host "這表示環境變數沒有正確展開。" -ForegroundColor Yellow
    Write-Host "請重新啟動 PowerShell 讓環境變數生效！" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== 測試命令可用性 ===" -ForegroundColor Cyan

# Test if fd and rg are available
$fdAvailable = Get-Command fd -ErrorAction SilentlyContinue
$rgAvailable = Get-Command rg -ErrorAction SilentlyContinue

if ($fdAvailable) {
    Write-Host "  [✓] fd 命令可用" -ForegroundColor Green
} else {
    Write-Host "  [✗] fd 命令不可用" -ForegroundColor Red
}

if ($rgAvailable) {
    Write-Host "  [✓] rg 命令可用" -ForegroundColor Green
} else {
    Write-Host "  [✗] rg 命令不可用" -ForegroundColor Red
}
