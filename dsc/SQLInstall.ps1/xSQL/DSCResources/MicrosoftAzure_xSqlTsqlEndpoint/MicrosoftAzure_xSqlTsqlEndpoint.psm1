#
# xSqlTsqlEndpoint: DSC resource to configure SQL Server instance 
#                   TCP/IP listening port for T-SQL connection  
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1,65535)]
        [uint32] $PortNumber = 1433,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $bConfigured = Test-TargetResource -InstanceName $InstanceName -Name $Name -PortNumber $PortNumber -SqlAdministratorCredential $SqlAdministratorCredential

    $retVal = @{
        InstanceName = $InstanceName
        PortNumber = $PortNumber
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
        Configured = $bConfigured
    }

    $retVal
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1,65535)]
        [uint32] $PortNumber = 1433,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )
    Import-Module -Name SqlServer

    try
    {
        # set sql server port
        Set-SqlTcpPort -InstanceName $InstanceName -EndpointPort $PortNumber -Credential $SqlAdministratorCredential
    }
    catch
    {
        Write-Host "Error setting SQL Server instance. Instance: $InstanceName, Port: $PortNumber"
        throw $_
    }   
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1,65535)]
        [uint32] $PortNumber = 1433,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )
    Import-Module -Name SqlServer

    $testPort = Test-SqlTcpPort -InstanceName $InstanceName -EndpointPort $PortNumber

    if($testPort -ne $true)
    {
        return $false
    }

    $true
}

#Return a SMO object to a SQL Server instance using the provided credentials
function Get-SqlServer([string]$InstanceName, [PSCredential]$Credential)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1 -and $list[1] -eq "MSSQLSERVER")
    {
        $ServerInstance = $list[0]
    }
    else
    {
        $ServerInstance = "(local)"
    }

    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    $s = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance

    $s
}

#The function sets local machine SQL Server instance TCP port
function Set-SqlTcpPort([string]$InstanceName, [uint32]$EndpointPort, [PSCredential]$Credential)
{
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

    $Server = Get-SqlServer -InstanceName $InstanceName -Credential $Credential

    $mc = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $Server.Name
    
    $computerName = $env:COMPUTERNAME

    # For the named instance, on the current computer, for the TCP protocol,
    #  loop through all the IPs and configure them to set the port value
    $uri = "ManagedComputer[@Name='$computerName']/ ServerInstance[@Name='$InstanceName']/ServerProtocol[@Name='Tcp']"
    $Tcp = $mc.GetSmoObject($uri)
    foreach ($ipAddress in $Tcp.IPAddresses)
    {
        $ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
        $ipAddress.IPAddressProperties["TcpPort"].Value = $EndpointPort.ToString()
    }
    $Tcp.Alter()
}

#The function test if the instance on the local machine TCP port is set to 
#the endpoint provided. This is a WMI ready access, so credentials is not required. 
function Test-SqlTcpPort([string]$InstanceName, [uint32]$EndpointPort)
{
    #Load the assembly containing the classes
    #[reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")

    $list = $InstanceName.Split("\")

    if ($list.Count -gt 1)
    {
        $InstanceName = $list[1]
    }
    else
    {
        $InstanceName = "MSSQLSERVER"
    }

    $mc = New-Object -TypeName Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $env:COMPUTERNAME

    $instance=$mc.ServerInstances[$InstanceName]

    $protocol=$instance.ServerProtocols['Tcp']

    for($i =0; $i -le $protocol.IPAddresses.Length.Count - 1; $i++) 
    {
       $ip=$protocol.IPAddresses[$i]

       $port=$ip.IPAddressProperties['TcpPort']

       if($port.Value -ne $EndpointPort)
       {
            return $false
       }
    }

    return $true
}

Export-ModuleMember -Function *-TargetResource
