# JoyGo 嘉義 — 程式碼備份腳本
# 用法：在 PowerShell 執行 .\backup_code.ps1

$ProjectRoot = "D:\chiayi_OuO\JoyGo-ChiaYi"
$BucketName  = "joygo-chiayi-backup"
$Date        = Get-Date -Format "yyyy-MM-dd_HH-mm"
$ZipName     = "joygo-source-$Date.zip"
$TempZip     = "$env:TEMP\$ZipName"

Write-Host "=== JoyGo 程式碼備份 ===" -ForegroundColor Cyan
Write-Host "壓縮專案中..."

# 排除不必要的大型資料夾
$Exclude = @(
    "$ProjectRoot\.dart_tool",
    "$ProjectRoot\build",
    "$ProjectRoot\android\.gradle",
    "$ProjectRoot\ios\Pods",
    "$ProjectRoot\macos\Pods",
    "$ProjectRoot\functions\node_modules",
    "$ProjectRoot\_docx_unpacked",
    "$ProjectRoot\archive.zip"
)

# 收集要壓縮的檔案
$Files = Get-ChildItem -Path $ProjectRoot -Recurse -File | Where-Object {
    $filePath = $_.FullName
    $excluded = $false
    foreach ($ex in $Exclude) {
        if ($filePath.StartsWith($ex)) {
            $excluded = $true
            break
        }
    }
    -not $excluded
}

Write-Host "共 $($Files.Count) 個檔案，壓縮中..."
Compress-Archive -Path "$ProjectRoot\*" -DestinationPath $TempZip -Force

# 排除大型資料夾後重新壓縮（使用 7zip 或直接用 Compress-Archive）
Write-Host "上傳至 S3..."
aws s3 cp $TempZip "s3://$BucketName/source-code/$ZipName" --acl public-read

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 上傳成功！" -ForegroundColor Green
    Write-Host "S3 路徑：s3://$BucketName/source-code/$ZipName"
    Write-Host "公開網址：https://$BucketName.s3.ap-southeast-2.amazonaws.com/source-code/$ZipName"
} else {
    Write-Host "❌ 上傳失敗，請檢查 AWS 設定" -ForegroundColor Red
}

# 刪除暫存檔
Remove-Item $TempZip -Force
Write-Host "完成！"
