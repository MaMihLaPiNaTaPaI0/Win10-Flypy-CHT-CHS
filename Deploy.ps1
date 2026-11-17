$baseDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($baseDir)) { $baseDir = (Get-Location).Path }

Write-Host "=== Step 1: Applying Registry & Win10 Compatibility Mode ===" -ForegroundColor Cyan
$regPath = "HKCU:\Software\Microsoft\InputMethod\Settings\CHS"
if (!(Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

# 1. 自动写入小鹤双拼键位方案与防乱跳开关（纯英文防 Big5 编码错误）
Set-ItemProperty -Path $regPath -Name "UserDefinedDoublePinyinScheme0" -Value "Flypy*2*^*iuvdjhcwfg^xmlnpbksqszxkrltvyovt" -Type String
Set-ItemProperty -Path $regPath -Name "DoublePinyinScheme" -Value 10 -Type DWord
Set-ItemProperty -Path $regPath -Name "Enable Double Pinyin" -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "Enable Cloud Candidate" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "Enable Dynamic Candidate Ranking" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "EnableSmartSelfLearning" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "Enable self-learning" -Value 0 -Type DWord
Set-ItemProperty -Path $regPath -Name "Enable EUDP" -Value 1 -Type DWord
Set-ItemProperty -Path $regPath -Name "OutputCharSet" -Value 1 -Type DWord

# 2. 自动开启 Win10 "使用以前版本的微软拼音" 兼容模式
Set-ItemProperty -Path $regPath -Name "EnableLegacyIME" -Value 1 -Type DWord -ErrorAction SilentlyContinue

Write-Host "=== Step 2: Compiling CHT Lex from clean_cht.txt ===" -ForegroundColor Cyan
$chtTxt = Join-Path $baseDir "clean_cht.txt"
$chtLex = Join-Path $baseDir "flypy_cht.lex"
$chsLex = Join-Path $baseDir "original_backup.lex"

if (Test-Path $chtTxt) {
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
        $bwData.Write([uint16]16); $bwData.Write([uint16]16); $bwData.Write([uint16](16 + $cb.Length))
        $bwData.Write([byte]$item.p); $bwData.Write([byte]6); $bwData.Write([uint64]0)
        $bwData.Write($cb); $bwData.Write($wb)
        $off += [uint32](16 + $cb.Length + $wb.Length)
    }
    $indexBytes = $msIndex.ToArray(); $dataBytes = $msData.ToArray()
    $totalSize = [uint32](64 + $indexBytes.Length + $dataBytes.Length)

    $fs = [System.IO.File]::Open($chtLex, 'Create'); $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([System.Text.Encoding]::ASCII.GetBytes("mschxudp"))
    $bw.Write([uint32]0x00600002); $bw.Write([uint32]1)
    $bw.Write($indexOffset); $bw.Write($dataOffset); $bw.Write($totalSize); $bw.Write($count)
    $bw.Write([uint32]([DateTimeOffset]::Now.ToUnixTimeSeconds())); $bw.Write([byte[]]::new(28))
    $bw.Write($indexBytes); $bw.Write($dataBytes); $bw.Close(); $fs.Close()
    Write-Host "Compiled $count entries into flypy_cht.lex" -ForegroundColor Green
}

Write-Host "=== Step 3: Generating Switch Scripts & Desktop Shortcuts ===" -ForegroundColor Cyan
$chsPs1 = Join-Path $baseDir "switch_chs.ps1"
$chtPs1 = Join-Path $baseDir "switch_cht.ps1"

$chsScript = @"
Stop-Process -Name 'ChsIME','ctfmon' -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Copy-Item -LiteralPath '$chsLex' -Destination "`$env:APPDATA\Microsoft\InputMethod\Chs\ChsPinyinEUDPv1.lex" -Force
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\InputMethod\Settings\CHS' -Name 'OutputCharSet' -Value 0 -Type DWord
Start-Process 'ctfmon.exe'
Add-Type -AssemblyName System.Windows.Forms
`$n = New-Object System.Windows.Forms.NotifyIcon
`$n.Icon = [System.Drawing.SystemIcons]::Information; `$n.Visible = `$true
`$n.ShowBalloonTip(2000, 'Flypy IME', 'Switched to Simplified (CHS)', [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 2; `$n.Dispose()
"@
[System.IO.File]::WriteAllText($chsPs1, $chsScript, [System.Text.UTF8Encoding]::new($true))

$chtScript = @"
Stop-Process -Name 'ChsIME','ctfmon' -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
Copy-Item -LiteralPath '$chtLex' -Destination "`$env:APPDATA\Microsoft\InputMethod\Chs\ChsPinyinEUDPv1.lex" -Force
Set-ItemProperty -Path 'HKCU:\Software\Microsoft\InputMethod\Settings\CHS' -Name 'OutputCharSet' -Value 1 -Type DWord
Start-Process 'ctfmon.exe'
Add-Type -AssemblyName System.Windows.Forms
`$n = New-Object System.Windows.Forms.NotifyIcon
`$n.Icon = [System.Drawing.SystemIcons]::Information; `$n.Visible = `$true
`$n.ShowBalloonTip(2000, 'Flypy IME', 'Switched to Traditional (CHT)', [System.Windows.Forms.ToolTipIcon]::Info)
Start-Sleep -Seconds 2; `$n.Dispose()
"@
[System.IO.File]::WriteAllText($chtPs1, $chtScript, [System.Text.UTF8Encoding]::new($true))

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

Write-Host "=== Step 4: Activating CHT Mode Immediately ===" -ForegroundColor Cyan
$sysDir = "$env:APPDATA\Microsoft\InputMethod\Chs"
if (!(Test-Path $sysDir)) { New-Item -Path $sysDir -ItemType Directory -Force | Out-Null }
Stop-Process -Name "ChsIME","ctfmon" -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 300
if (Test-Path $chtLex) { Copy-Item -LiteralPath $chtLex -Destination "$sysDir\ChsPinyinEUDPv1.lex" -Force }
Start-Process "ctfmon.exe"

Write-Host "`nDEPLOYMENT COMPLETE! Press Win+Space twice to refresh IME." -ForegroundColor Green
Start-Sleep -Seconds 3
