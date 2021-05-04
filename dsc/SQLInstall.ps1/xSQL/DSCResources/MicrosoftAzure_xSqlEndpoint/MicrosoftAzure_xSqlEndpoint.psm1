#
# xSqlEndpoint: DSC resource to configure a database mirroring endpoint for use
#   with SQL Server AlwaysOn availability groups.
#


function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1000,9999)]
        [uint32] $PortNumber = 5022,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllowedUser,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    $s = Get-SqlServer -InstanceName $InstanceName -Credential $SqlAdministratorCredential

    $endpoint = $s.Endpoints | where { $_.Name -eq $Name }

    $bConfigured = Test-TargetResource -InstanceName $InstanceName -Name $Name -PortNumber $PortNumber -AllowedUser $AllowedUser -SqlAdministratorCredential $SqlAdministratorCredential

    $retVal = @{
        InstanceName = $InstanceName
        Name = $Name
        PortNumber = $PortNumber
        AllowedUser = $AllowedUser
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
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1000,9999)]
        [uint32] $PortNumber = 5022,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllowedUser,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )
    Import-Module -Name SqlServer
    $s = Get-SqlServer -InstanceName $InstanceName -Credential $SqlAdministratorCredential

    try
    {
        if (-not ($s.Endpoints | where { $_.Name -eq $Name }))
        {
            # TODO: use Microsoft.SqlServer.Management.Smo.Endpoint instead of
            #   SqlPs since the PS cmdlets don't support impersonation.
            Write-Verbose -Message "Creating database mirroring endpoint for SQL AlwaysOn ..."
            $endpoint = New-SqlHadrEndpoint -Name $Name -Port $PortNumber -InputObject $InstanceName
            $endpoint | Set-SqlHadrEndpoint -State 'Started'
        }
    }
    catch
    {
        Write-Error "Error creating database mirroring endpoint."
        throw $_
    }

    if ($AllowedUser -ne ($($SqlAdministratorCredential.UserName).Split('\'))[1])
    {

        try
        {
            Write-Verbose -Message "Granting permissions to '$($AllowedUser)' ..."
            $perms = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet
            $perms.Connect = $true
            $endpoint = $s.Endpoints | where { $_.Name -eq $Name }
            $endpoint.Grant($perms, $AllowedUser)
        }
        catch
        {
            Write-Error "Error granting permissions to '$($AllowedUser)'."
            throw $_
        }
    }
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $InstanceName,

        [ValidateRange(1000,9999)]
        [uint32] $PortNumber = 5022,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $AllowedUser,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential
    )

    Import-Module -Name SqlServer
    $s = Get-SqlServer -InstanceName $InstanceName -Credential $SqlAdministratorCredential

    $endpoint = $s.Endpoints | where { $_.Name -eq $Name }
    if (-not $endpoint)
    {
        Write-Verbose -Message "Endpoint '$($Name)' does NOT exist."
        return $false
    }

    if ($AllowedUser -ne ($($SqlAdministratorCredential.UserName).Split('\'))[1])
    {
        $ops = New-Object Microsoft.SqlServer.Management.Smo.ObjectPermissionSet
        $ops.Add([Microsoft.SqlServer.Management.Smo.ObjectPermission]::Connect) | Out-Null
        $opis = $endpoint.EnumObjectPermissions($AllowedUser, $ops)
        if ($opis.Count -lt 1)
        {
            Write-Verbose -Message "Login '$($AllowedUser)' does NOT have the correct permissions for endpoint '$($Name)'."
            return $false
        }
    }

    $true
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


Export-ModuleMember -Function *-TargetResource
