# UUID替换脚本
# 用法: .\replace_uuid.ps1 [文件路径] [可选:行号]

param(
    [string]$FilePath = "README.md",
    [int]$LineNumber = 0
)

# 生成新的UUID
$newUuid = [System.Guid]::NewGuid().ToString()

try {
    # 读取文件内容
    $content = Get-Content $FilePath -Raw -ErrorAction Stop
    
    if ($LineNumber -gt 0) {
        # 如果指定了行号，只替换该行的UUID
        $lines = Get-Content $FilePath -ErrorAction Stop
        if ($LineNumber -le $lines.Count) {
            $oldLine = $lines[$LineNumber - 1]
            if ($oldLine -match '"uuid":\s*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"') {
                $oldUuid = $matches[1]
                $lines[$LineNumber - 1] = $oldLine -replace $oldUuid, $newUuid
                Set-Content $FilePath -Value $lines -Encoding UTF8
                Write-Host "✅ 第 $LineNumber 行的UUID已替换" -ForegroundColor Green
                Write-Host "   旧UUID: $oldUuid" -ForegroundColor Yellow
                Write-Host "   新UUID: $newUuid" -ForegroundColor Cyan
            } else {
                Write-Host "❌ 第 $LineNumber 行未找到有效的UUID格式" -ForegroundColor Red
            }
        } else {
            Write-Host "❌ 行号超出文件范围" -ForegroundColor Red
        }
    } else {
        # 替换所有UUID
        $uuidPattern = '"uuid":\s*"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"'
        $matches = [regex]::Matches($content, $uuidPattern)
        
        if ($matches.Count -gt 0) {
            $replacedCount = 0
            foreach ($match in $matches) {
                $oldUuid = $match.Groups[1].Value
                $content = $content -replace [regex]::Escape($oldUuid), $newUuid
                $replacedCount++
                Write-Host "   替换UUID: $oldUuid → $newUuid" -ForegroundColor Yellow
            }
            
            Set-Content $FilePath -Value $content -NoNewline -Encoding UTF8
            Write-Host "✅ 成功替换 $replacedCount 个UUID" -ForegroundColor Green
        } else {
            Write-Host "❌ 文件中未找到UUID格式" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "❌ 错误: $($_.Exception.Message)" -ForegroundColor Red
}

# 显示使用说明
Write-Host "`n📖 使用说明:" -ForegroundColor Magenta
Write-Host "   替换所有UUID:     .\replace_uuid.ps1" -ForegroundColor White
Write-Host "   替换指定文件:     .\replace_uuid.ps1 config.json" -ForegroundColor White
Write-Host "   替换指定行:       .\replace_uuid.ps1 README.md 375" -ForegroundColor White