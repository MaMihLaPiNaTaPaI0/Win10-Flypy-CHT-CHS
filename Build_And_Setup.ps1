# 自动锁定当前脚本所在的文件夹路径
$baseDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($baseDir)) { $baseDir = (Get-Location).Path }

$chtTxt = Join-Path $baseDir "clean_cht.txt"
$chtLex = Join-Path $baseDir "flypy_cht.lex"
$chsLex = Join-Path $baseDir "original_backup.lex"

# 1. 编译台湾正体词库 (clean_cht.txt -> flypy_cht.lex)
if (Test-Path $chtTxt) {
    Write-Host "Compiling clean_cht.txt..." -ForegroundColor Cyan
    $lines = Get-Content $chtTxt -Encoding UTF8
    $list = New-Object System.Collections.Generic.List[Object]

    foreach ($l in $lines) {
        $t = $l.Trim()
        $commaIdx = $t.IndexOf(',')
        $eqIdx = $t.IndexOf('=')
        
        if ($commaIdx -gt 0 -and $eqIdx -gt ($commaIdx + 1)) {
            $c = $t.Substring(0, $commaIdx).ToLower()
            $pStr = $t.Substring($commaIdx + 1, $eqIdx - $commaIdx - 1)
            $w = $t.Substring($eqIdx + 1)
            
            $pInt = 1
            if ([int]::TryParse($pStr, [ref]$pInt)) {
                $p = [byte]([Math]::Min([Math]::Max($pInt, 1), 255))
                $list.Add([PSCustomObject]@{ c = $c; p = $p; w = $w })
            }
        }
    }

    $sorted = $list | Sort-Object c, p
    $count = [uint32]$sorted.Count
    $indexOffset = [uint32]64
    $dataOffset = [uint32](64 + ($count * 4))

    $msIndex = New-Object System.IO.MemoryStream
    $bwIndex = New-Object System.IO.BinaryWriter($msIndex)
    $msData = New-Object System.IO.MemoryStream
    $bwData = New-Object System.IO.BinaryWriter($msData, [System.Text.Encoding]::Unicode)

    $off = [uint32]0
    foreach ($item in $sorted) {
        $bwIndex.Write($off)
        $cb = [System.Text.Encoding]::Unicode.GetBytes($item.c + "`0")
        $wb = [System.Text.Encoding]::Unicode.GetBytes($item.w + "`0")
        $recLen = [uint32](16 + $cb.Length + $wb.Length)
        
        $bwData.Write([uint16]16)
        $bwData.Write([uint16]16)
        $bwData.Write([uint16](16 + $cb.Length))
        $bwData.Write([byte]$item.p)
        $bwData.Write([byte]6)
        $bwData.Write([uint64]0)
        $bwData.Write($cb)
        $bwData.Write($wb)
        $off += $recLen
    }

    $indexBytes = $msIndex.ToArray()
    $dataBytes = $msData.ToArray()
    $totalSize = [uint32](64 + $indexBytes.Length + $dataBytes.Length)

    $fs = [System.IO.File]::Open($chtLex, 'Create')
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("mschxudp"))
    $bw.Write([uint32]0x00600002)
    $bw.Write([uint32]1)
    $bw.Write($indexOffset)
    $bw.Write($dataOffset)
    $bw.Write($totalSize)
    $bw.Write($count)
    $bw.Write([uint32]([DateTimeOffset]::Now.ToUnixTimeSeconds()))
    $bw.Write([byte[]]::new(28))

    $bw.Write($indexBytes)
    $bw.Write($dataBytes)
    $bw.Close(); $fs.Close()
    Write-Host "Built flypy_cht.lex successfully ($count entries)." -ForegroundColor Green
} else {
    Write-Host "Warning: clean_cht.txt not found, skipping compilation." -ForegroundColor Yellow
}

# 2. 生成后台切换脚本 (switch_chs.ps1 与 switch_cht.ps1)
$chsPs1 = Join-Path $baseDir "switch_chs.ps1"
$chtPs1 = Join-Path $baseDir "switch_cht.ps1"

$chsScript = @"
Stop-Process -Name 'ChsIME','ctfmon' -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Copy-Item -LiteralPath '$chsLex' -Destination "`$env:APPDATA\Microsoft\InputMethod\Chs\ChsPinyinEUDPv1.lex" -Force
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\InputMethod\Settings\CHS' -Name 'OutputCharSet' -Value 0 -Type DWord
Start-Process 'ctfmon.exe'

Add-Type -AssemblyName System.Windows.Forms
`$notify = New-Object System.Windows.Forms.NotifyIcon
`$notify.Icon = [System.Drawing.SystemIcons]::Information
`$notify.Visible = `$true
`$notify.ShowBalloonTip(2000, 'Flypy IME Switched', 'Current Mode: Simplified Chinese (CHS)', [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 2
`$notify.Dispose()
"@
[System.IO.File]::WriteAllText($chsPs1, $chsScript, [System.Text.UTF8Encoding]::new($true))

$chtScript = @"
Stop-Process -Name 'ChsIME','ctfmon' -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Copy-Item -LiteralPath '$chtLex' -Destination "`$env:APPDATA\Microsoft\InputMethod\Chs\ChsPinyinEUDPv1.lex" -Force
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\InputMethod\Settings\CHS' -Name 'OutputCharSet' -Value 1 -Type DWord
Start-Process 'ctfmon.exe'

Add-Type -AssemblyName System.Windows.Forms
`$notify = New-Object System.Windows.Forms.NotifyIcon
`$notify.Icon = [System.Drawing.SystemIcons]::Information
`$notify.Visible = `$true
`$notify.ShowBalloonTip(2000, 'Flypy IME Switched', 'Current Mode: Traditional Chinese (CHT)', [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 2
`$notify.Dispose()
"@
[System.IO.File]::WriteAllText($chtPs1, $chtScript, [System.Text.UTF8Encoding]::new($true))

# 3. 创建桌面快捷方式
$desk = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders").Desktop
$wsh = New-Object -ComObject WScript.Shell

$s1 = $wsh.CreateShortcut("$desk\Flypy_CHS.lnk")
$s1.TargetPath = "powershell.exe"
$s1.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$chsPs1`""
$s1.Save()

$s2 = $wsh.CreateShortcut("$desk\Flypy_CHT.lnk")
$s2.TargetPath = "powershell.exe"
$s2.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$chtPs1`""
$s2.Save()

Write-Host "ALL DONE! Desktop shortcuts (Flypy_CHS & Flypy_CHT) created." -ForegroundColor Cyan
Start-Sleep -Seconds 2
