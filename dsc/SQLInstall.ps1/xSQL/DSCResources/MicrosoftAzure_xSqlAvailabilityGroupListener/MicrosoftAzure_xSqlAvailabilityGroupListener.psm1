#
# xSqlAvailabilityGroupListener: DSC resource that configures a SQL AlwaysOn Availability Group Listener.
#

function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String] $ListenerIPAddress,

        [UInt32] $ListenerPortNumber = 1433,

        [UInt32] $ProbePortNumber = 59999,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $bConfigured = Test-TargetResource -Name $Name -AvailabilityGroupName $AvailabilityGroupName -DomainNameFqdn $DomainNameFqdn -ListenerPortNumber $ListenerPortNumber -ProbePortNumber $ProbePortNumber -InstanceName  $InstanceName -DomainCredential $DomainCredential -SqlAdministratorCredential $SqlAdministratorCredential

    $returnValue = @{
        Name = $Name
        AvailabilityGroupName = $AvailabilityGroupName
        DomainNameFqdn = $DomainNameFqdn
        ListenerPortNumber = $ListenerPortNumber
        InstanceName = $InstanceName
        DomainCredential = $DomainCredential.UserName
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
        Configured = $bConfigured
    }

    $returnValue
}

function Set-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String] $ListenerIPAddress,

        [UInt32] $ListenerPortNumber = 1433,

        [UInt32] $ProbePortNumber = 59999,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Import-Module -Name SqlServer
    Write-Verbose -Message "Configuring the Availability Group Listener port to '$($ListenerPortNumber)' ..."

    Write-Verbose -Message "Stopping cluster resource '$($AvailabilityGroupName)' ..."
    Stop-ClusterResource -Name $AvailabilityGroupName -ErrorAction SilentlyContinue | Out-Null

    if (!(Get-ClusterResource $Name -ErrorAction Ignore))
    {
        Write-Verbose -Message "Creating Network Name resource '$($Name)' ..."
        $params= @{
            Name = $Name
            DnsName = $Name
        }
        Add-ClusterResource -Name $Name -ResourceType "Network Name" -Group $AvailabilityGroupName -ErrorAction Stop |
            Set-ClusterParameter -Multiple $params -ErrorAction Stop

        Write-Verbose -Message "Setting resource dependency between '$($AvailabilityGroupName)' and '$($Name)' ..."
        Get-ClusterResource -Name $AvailabilityGroupName | Set-ClusterResourceDependency "[$Name]" -ErrorAction Stop
    }

    if (!(Get-ClusterResource "IP Address $ListenerIPAddress" -ErrorAction Ignore))
    {
        Write-Verbose -Message "Creating IP Address resource for '$($ListenerIPAddress)' ..."
        $params = @{
            Address = $ListenerIpAddress
            ProbePort = $ProbePortNumber
            SubnetMask = "255.255.255.255"
            Network = (Get-ClusterNetwork)[0].Name
            OverrideAddressMatch = 1
            EnableDhcp = 0
            }
        Add-ClusterResource -Name "IP Address $ListenerIPAddress" -ResourceType "IP Address" -Group $AvailabilityGroupName -ErrorAction Stop |
            Set-ClusterParameter -Multiple $params -ErrorAction Stop

        Write-Verbose -Message "Setting resource dependency between '$($Name)' and '$($ListenerIpAddress)' ..."
        Get-ClusterResource -Name $Name | Set-ClusterResourceDependency "[IP Address $ListenerIpAddress]" -ErrorAction Stop
    }

    Write-Verbose -Message "Starting cluster resource '$($Name)' ..."
    Start-ClusterResource -Name $Name -ErrorAction Stop | Out-Null

    Write-Verbose -Message "Starting cluster resource '$($AvailabilityGroupName)' ..."
    Start-ClusterResource -Name $AvailabilityGroupName -ErrorAction Stop | Out-Null
    
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $AvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $DomainNameFqdn,

        [String] $ListenerIPAddress,

        [UInt32] $ListenerPortNumber = 1433,

        [UInt32] $ProbePortNumber = 59999,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String] $InstanceName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $DomainCredential,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Import-Module -Name SqlServer
    Write-Verbose -Message "Checking if SQL AG Listener '$($Name)' exists on instance '$($InstanceName)' ..."

    $instance = Get-SqlInstanceName -Node  $env:COMPUTERNAME -InstanceName $InstanceName
    $s = Get-SqlServer -InstanceName $instance -Credential $SqlAdministratorCredential

    $ag = $s.AvailabilityGroups
    $agl = $ag.AvailabilityGroupListeners
    $bRet = $true

    if ($agl)
    {
        Write-Verbose -Message "SQL AG Listener '$($Name)' found."
    }
    else
    {
        Write-Verbose "SQL AG Listener '$($Name)' NOT found."
        $bRet = $false
    }

    return $bRet
}


function Get-SqlServer
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential]$Credential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstanceName
    )
    
    $LoginCreationRetry = 0

    While ($true) {
        
        try {

            $list = $InstanceName.Split("\")
            if ($list.Count -gt 1 -and $list[1] -eq "MSSQLSERVER")
            {
                $ServerInstance = $list[0]
            }
            else
            {
                $ServerInstance = $InstanceName
            }
            
            #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

            $s = New-Object Microsoft.SqlServer.Management.Smo.Server $ServerInstance 
            
            if ($s.Information.Version) {
            
                $s.Refresh()
            
                Write-Verbose "SQL Management Object Created Successfully, Version : '$($s.Information.Version)' "   
            
            }
            else
            {
                throw "SQL Management Object Creation Failed"
            }
            
            return $s

        }
        catch [System.Exception] 
        {
            $LoginCreationRetry = $LoginCreationRetry + 1
            
            if ($_.Exception.InnerException) {                   
             $ErrorMSG = "Error occured: '$($_.Exception.Message)',InnerException: '$($_.Exception.InnerException.Message)',  failed after '$($LoginCreationRetry)' times"
            } 
            else 
            {               
             $ErrorMSG = "Error occured: '$($_.Exception.Message)', failed after '$($LoginCreationRetry)' times"
            }
            
            if ($LoginCreationRetry -eq 30) 
            {
                Write-Verbose "Error occured: $ErrorMSG, reach the maximum re-try: '$($LoginCreationRetry)' times, exiting...."

                Throw $ErrorMSG
            }

            start-sleep -seconds 60

            Write-Verbose "Error occured: $ErrorMSG, retry for '$($LoginCreationRetry)' times"
        }
    }
}

function Get-SqlInstanceName([string]$Node, [string]$InstanceName)
{
    $pureInstanceName = Get-PureSqlInstanceName -InstanceName $InstanceName
    if ("MSSQLSERVER" -eq $pureInstanceName)
    {
        $Node
    }
    else
    {
        $Node + "\" + $pureInstanceName
    }
}

function Get-PureSqlInstanceName([string]$InstanceName)
{
    $list = $InstanceName.Split("\")
    if ($list.Count -gt 1)
    {
        $list[1]
    }
    else
    {
        "MSSQLSERVER"
    }
}

function Get-SqlAvailabilityGroup([string]$Name, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    $s.AvailabilityGroups | where { $_.Name -eq $Name }
}

Export-ModuleMember -Function *-TargetResource
