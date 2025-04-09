param(
    [Parameter(Mandatory=$true)]
    [string]$parametro
)

# Configuración inicial
$bloque1 = "172.20.0.0/16"
$bloque2 = "172.20.140.0/26"
$region = "us-east-1"
$zona = "us-east-1a"
$outputFile = "ServiciosWeb$parametro-output.txt"

# Dominios fijos (siempre terminan en 02)
$linuxHostname = "ubu.alisal02.com.es"
$windowsHostname = "win.alisal02.com.es"

# Iniciar el archivo de salida
"=== INFRAESTRUCTURA CREADA ===" | Out-File -FilePath $outputFile
"Fecha: $(Get-Date)" | Out-File -FilePath $outputFile -Append
"Parámetro proporcionado: $parametro" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear VPC
$vpc = New-EC2Vpc -CidrBlock $bloque1 -Region $region -VpcName "$parametro-vpc"
$vpcId = $vpc.VpcId
New-EC2Tag -Resource $vpcId -Tag @{ Key="Name"; Value="$parametro-vpc" } -Region $region
"VPC creada:" | Out-File -FilePath $outputFile -Append
"- ID: $vpcId" | Out-File -FilePath $outputFile -Append
"- CIDR Block: $bloque1" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-vpc" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear Subred
$subred = New-EC2Subnet -CidrBlock $bloque2 -Region $region -VpcId $vpcId -AvailabilityZone $zona -SubnetName "$parametro-subnet"
$subnetId = $subred.SubnetId
New-EC2Tag -Resource $subnetId -Tag @{ Key="Name"; Value="$parametro-subnet" } -Region $region
"Subred creada:" | Out-File -FilePath $outputFile -Append
"- ID: $subnetId" | Out-File -FilePath $outputFile -Append
"- CIDR Block: $bloque2" | Out-File -FilePath $outputFile -Append
"- Zona de disponibilidad: $zona" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-subnet" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear Route Table
$routeTable = New-EC2RouteTable -VpcId $vpcId -Region $region -RouteTableName "$parametro-rt"
$routeTableId = $routeTable.RouteTableId
New-EC2Tag -Resource $routeTableId -Tag @{ Key="Name"; Value="$parametro-rt" } -Region $region
"Route Table creada:" | Out-File -FilePath $outputFile -Append
"- ID: $routeTableId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-rt" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear y asociar Internet Gateway
$igw = New-EC2InternetGateway -Region $region -InternetGatewayName "$parametro-igw"
$igwId = $igw.InternetGatewayId
New-EC2Tag -Resource $igwId -Tag @{ Key="Name"; Value="$parametro-igw" } -Region $region
Add-EC2VpcInternetGatewayAttachment -VpcId $vpcId -InternetGatewayId $igwId -Region $region
New-EC2Route -RouteTableId $routeTableId -DestinationCidrBlock "0.0.0.0/0" -GatewayId $igwId -Region $region
New-EC2SubnetRouteTableAssociation -RouteTableId $routeTableId -SubnetId $subnetId -Region $region
"Internet Gateway creado y asociado:" | Out-File -FilePath $outputFile -Append
"- ID: $igwId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-igw" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear Security Group para Linux
$sgLinux = New-EC2SecurityGroup -VpcId $vpcId -GroupName "$parametro-sg-linux" -Description "Security group for Linux instance" -Region $region
$sgLinuxId = $sgLinux.GroupId
New-EC2Tag -Resource $sgLinuxId -Tag @{ Key="Name"; Value="$parametro-sg-linux" } -Region $region

@(
    @{IpProtocol="tcp"; FromPort=80; ToPort=80; IpRanges=@("0.0.0.0/0")},
    @{IpProtocol="tcp"; FromPort=443; ToPort=443; IpRanges=@("0.0.0.0/0")},
    @{IpProtocol="tcp"; FromPort=22; ToPort=22; IpRanges=@("0.0.0.0/0")}
) | ForEach-Object {
    Grant-EC2SecurityGroupIngress -GroupId $sgLinuxId -IpPermission $_ -Region $region
}

"Security Group para Linux creado:" | Out-File -FilePath $outputFile -Append
"- ID: $sgLinuxId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-sg-linux" | Out-File -FilePath $outputFile -Append
"- Reglas: HTTP(80), HTTPS(443), SSH(22)" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear Security Group para Windows
$sgWindows = New-EC2SecurityGroup -VpcId $vpcId -GroupName "$parametro-sg-windows" -Description "Security group for Windows instance" -Region $region
$sgWindowsId = $sgWindows.GroupId
New-EC2Tag -Resource $sgWindowsId -Tag @{ Key="Name"; Value="$parametro-sg-windows" } -Region $region

@(
    @{IpProtocol="tcp"; FromPort=80; ToPort=80; IpRanges=@("0.0.0.0/0")},
    @{IpProtocol="tcp"; FromPort=443; ToPort=443; IpRanges=@("0.0.0.0/0")},
    @{IpProtocol="tcp"; FromPort=3389; ToPort=3389; IpRanges=@("0.0.0.0/0")}
) | ForEach-Object {
    Grant-EC2SecurityGroupIngress -GroupId $sgWindowsId -IpPermission $_ -Region $region
}

"Security Group para Windows creado:" | Out-File -FilePath $outputFile -Append
"- ID: $sgWindowsId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-sg-windows" | Out-File -FilePath $outputFile -Append
"- Reglas: HTTP(80), HTTPS(443), RDP(3389)" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear claves SSH
$keyLinuxName = "$parametro-key-linux"
$keyLinuxPair = Get-EC2KeyPair -KeyName $keyLinuxName -Region $region -ErrorAction SilentlyContinue
if (-not $keyLinuxPair) {
    $keyLinuxPair = New-EC2KeyPair -KeyName $keyLinuxName -Region $region
    $keyLinuxPair.KeyMaterial | Out-File -FilePath "$keyLinuxName.pem" -Encoding ASCII
    "Clave SSH para Linux creada y guardada en: $keyLinuxName.pem" | Out-File -FilePath $outputFile -Append
} else {
    "Clave SSH para Linux ya existente, usando: $keyLinuxName" | Out-File -FilePath $outputFile -Append
}

$keyWindowsName = "$parametro-key-windows"
$keyWindowsPair = Get-EC2KeyPair -KeyName $keyWindowsName -Region $region -ErrorAction SilentlyContinue
if (-not $keyWindowsPair) {
    $keyWindowsPair = New-EC2KeyPair -KeyName $keyWindowsName -Region $region
    $keyWindowsPair.KeyMaterial | Out-File -FilePath "$keyWindowsName.pem" -Encoding ASCII
    "Clave SSH para Windows creada y guardada en: $keyWindowsName.pem" | Out-File -FilePath $outputFile -Append
} else {
    "Clave SSH para Windows ya existente, usando: $keyWindowsName" | Out-File -FilePath $outputFile -Append
}
"" | Out-File -FilePath $outputFile -Append

# Configurar User Data para Linux
$userDataLinux = @"
#!/bin/bash
apt-get update
apt-get install -y nginx
systemctl start nginx
systemctl enable nginx
hostnamectl set-hostname $linuxHostname
echo "<html><body><h1>$parametro - Nginx instalado via AWS PowerShell</h1><p>Hostname: $linuxHostname</p></body></html>" > /var/www/html/index.html
"@
$userDataLinuxEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($userDataLinux))

# Configurar User Data para Windows
$userDataWindows = @"
<powershell>
Install-WindowsFeature -name Web-Server -IncludeManagementTools
Remove-Item -Path C:\inetpub\wwwroot\iisstart.htm
Add-Content -Path C:\inetpub\wwwroot\iisstart.htm -Value "<html><body><h1>$parametro - IIS Instalado via AWS PowerShell</h1><p>Hostname: $windowsHostname</p></body></html>"
Rename-Computer -NewName $($windowsHostname.Split('.')[0]) -Force
</powershell>
"@
$userDataWindowsEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($userDataWindows))

# Crear instancia Linux con IP elástica
$eipLinux = New-EC2Address -Domain vpc -Region $region
$instanceLinux = New-EC2Instance -ImageId "ami-0fc5d935ebf8bc3bc" -InstanceType "t2.micro" -KeyName $keyLinuxName -SecurityGroupId $sgLinuxId -SubnetId $subnetId -UserData $userDataLinuxEncoded -Region $region -MinCount 1 -MaxCount 1
$instanceLinuxId = $instanceLinux.Instances[0].InstanceId
New-EC2Tag -Resource $instanceLinuxId -Tag @{ Key="Name"; Value="$parametro-instance-linux" } -Region $region

# Asociar IP elástica a instancia Linux
Register-EC2Address -InstanceId $instanceLinuxId -AllocationId $eipLinux.AllocationId -Region $region

"Instancia Linux creada:" | Out-File -FilePath $outputFile -Append
"- ID: $instanceLinuxId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-instance-linux" | Out-File -FilePath $outputFile -Append
"- AMI: ami-0fc5d935ebf8bc3bc (Ubuntu)" | Out-File -FilePath $outputFile -Append
"- Tipo: t2.micro" | Out-File -FilePath $outputFile -Append
"- Clave SSH: $keyLinuxName" | Out-File -FilePath $outputFile -Append
"- IP Elástica: $($eipLinux.PublicIp)" | Out-File -FilePath $outputFile -Append
"- URL: http://$linuxHostname" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Crear instancia Windows con IP elástica
$eipWindows = New-EC2Address -Domain vpc -Region $region
$instanceWindows = New-EC2Instance -ImageId "ami-0b5eea76982371e91" -InstanceType "t2.micro" -KeyName $keyWindowsName -SecurityGroupId $sgWindowsId -SubnetId $subnetId -UserData $userDataWindowsEncoded -Region $region -MinCount 1 -MaxCount 1
$instanceWindowsId = $instanceWindows.Instances[0].InstanceId
New-EC2Tag -Resource $instanceWindowsId -Tag @{ Key="Name"; Value="$parametro-instance-windows" } -Region $region

# Asociar IP elástica a instancia Windows
Register-EC2Address -InstanceId $instanceWindowsId -AllocationId $eipWindows.AllocationId -Region $region

"Instancia Windows creada:" | Out-File -FilePath $outputFile -Append
"- ID: $instanceWindowsId" | Out-File -FilePath $outputFile -Append
"- Nombre: $parametro-instance-windows" | Out-File -FilePath $outputFile -Append
"- AMI: ami-0b5eea76982371e91 (Windows)" | Out-File -FilePath $outputFile -Append
"- Tipo: t2.micro" | Out-File -FilePath $outputFile -Append
"- Clave SSH: $keyWindowsName" | Out-File -FilePath $outputFile -Append
"- IP Elástica: $($eipWindows.PublicIp)" | Out-File -FilePath $outputFile -Append
"- URL: http://$windowsHostname" | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Obtener información de las instancias
$instances = Get-EC2Instance -Instance @($instanceLinuxId, $instanceWindowsId) -Region $region

# Configurar Route53 para los nombres de dominio (simulado, ya que necesitarías una zona hospedada)
"=== NOTA IMPORTANTE ===" | Out-File -FilePath $outputFile -Append
"Para que las URLs funcionen correctamente:" | Out-File -FilePath $outputFile -Append
"- http://$linuxHostname -> $($eipLinux.PublicIp)" | Out-File -FilePath $outputFile -Append
"- http://$windowsHostname -> $($eipWindows.PublicIp)" | Out-File -FilePath $outputFile -Append
"Debes configurar manualmente en tu DNS (Route53 o otro proveedor) las entradas anteriores." | Out-File -FilePath $outputFile -Append
"" | Out-File -FilePath $outputFile -Append

# Mostrar resumen en consola
Write-Host "`nInfraestructura creada exitosamente. Detalles guardados en $outputFile"
Write-Host "`nResumen:"
Write-Host "VPC ID: $vpcId"
Write-Host "Subnet ID: $subnetId"
Write-Host "`nInstancia Linux (Ubuntu con Nginx):"
Write-Host "Instance ID: $instanceLinuxId"
Write-Host "Public IP: $($eipLinux.PublicIp)"
Write-Host "URL: http://$linuxHostname"
Write-Host "Conectar: ssh -i $keyLinuxName.pem ubuntu@$($eipLinux.PublicIp)"
Write-Host "`nInstancia Windows (IIS):"
Write-Host "Instance ID: $instanceWindowsId"
Write-Host "Public IP: $($eipWindows.PublicIp)"
Write-Host "URL: http://$windowsHostname"
Write-Host "Conectar via RDP a: $($eipWindows.PublicIp)"
Write-Host "`nNota: Para la instancia Windows, necesitarás obtener la contraseña administrativa usando el par de claves una vez que la instancia esté running."

Write-Host "`nRecuerda configurar los registros DNS para las URLs:"
Write-Host "- http://$linuxHostname -> $($eipLinux.PublicIp)"
Write-Host "- http://$windowsHostname -> $($eipWindows.PublicIp)"
