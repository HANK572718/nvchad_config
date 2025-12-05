# Check user PATH for MSYS2 entries

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")

Write-Host "=== 檢查個人帳號 PATH 環境變數 ===" -ForegroundColor Cyan
Write-Host ""

$paths = $userPath -split ';'
$msysPaths = $paths | Where-Object { $_ -like '*msys*' }

if ($msysPaths) {
    Write-Host "找到的 MSYS2 路徑：" -ForegroundColor Green
    foreach ($path in $msysPaths) {
        Write-Host "  - $path"

        # Check if path exists
        if (Test-Path $path) {
            Write-Host "    [✓] 路徑存在" -ForegroundColor Green
        } else {
            Write-Host "    [✗] 路徑不存在" -ForegroundColor Red
        }
    }
} else {
    Write-Host "❌ 沒有找到任何 MSYS2 相關路徑！" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 正確的路徑應該是 ===" -ForegroundColor Yellow
Write-Host "  C:\msys64_2\ucrt64\bin" -ForegroundColor Yellow
Write-Host ""

# Check if fd and rg exist
$fdPath = "C:\msys64_2\ucrt64\bin\fd.exe"
$rgPath = "C:\msys64_2\ucrt64\bin\rg.exe"

Write-Host "=== 檢查工具是否存在 ===" -ForegroundColor Cyan
if (Test-Path $fdPath) {
    Write-Host "  [✓] fd.exe 存在於: $fdPath" -ForegroundColor Green
} else {
    Write-Host "  [✗] fd.exe 不存在" -ForegroundColor Red
}

if (Test-Path $rgPath) {
    Write-Host "  [✓] rg.exe 存在於: $rgPath" -ForegroundColor Green
} else {
    Write-Host "  [✗] rg.exe 不存在" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== 建議操作 ===" -ForegroundColor Cyan

if (-not $msysPaths -or $msysPaths -notcontains "C:\msys64_2\ucrt64\bin") {
    Write-Host "請執行以下命令來添加正確的路徑：" -ForegroundColor Yellow
    Write-Host ""
    Write-Host '[Environment]::SetEnvironmentVariable("Path", [Environment]::GetEnvironmentVariable("Path", "User") + ";C:\msys64_2\ucrt64\bin", "User")' -ForegroundColor White
    Write-Host ""
    Write-Host "然後重新啟動 PowerShell！" -ForegroundColor Yellow
}
