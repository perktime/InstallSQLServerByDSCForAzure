function Get-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String[]]$DatabaseNames,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PrimaryReplica,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondaryReplica,
         
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SqlAlwaysOnAvailabilityGroupName
    )

   $retVal = @{
        DatabaseNames = $DatabaseNames
        PrimaryReplica = $PrimaryReplica
        SecondaryReplica = $SecondaryReplica
        SqlAlwaysOnAvailabilityGroupName = $SqlAlwaysOnAvailabilityGroupName
        SqlAdministratorCredential = $SqlAdministratorCredential.UserName
    }

    $retVal
}

function Set-TargetResource
{
    param
    (
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SqlAlwaysOnAvailabilityGroupName,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String[]]$DatabaseNames,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PrimaryReplica,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondaryReplica,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential

      
    )
    Import-Module -Name SqlServer

    Configure-Databases -DatabaseNames $DatabaseNames -SqlAdministratorCredential $SqlAdministratorCredential -PrimaryReplica $PrimaryReplica -SecondaryReplica $SecondaryReplica -SqlAlwaysOnAvailabilityGroupName $SqlAlwaysOnAvailabilityGroupName
 
}

function Test-TargetResource
{
    param
    (
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [PSCredential] $SqlAdministratorCredential,

        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String[]]$DatabaseNames,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PrimaryReplica,
        
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SecondaryReplica,
         
        [parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$SqlAlwaysOnAvailabilityGroupName
    )
    Import-Module -Name SqlServer
    
    Test-Databases -DatabaseNames $DatabaseNames -SqlAdministratorCredential $SqlAdministratorCredential -PrimaryReplica $PrimaryReplica -SecondaryReplica $SecondaryReplica -SqlAlwaysOnAvailabilityGroupName $SqlAlwaysOnAvailabilityGroupName
}


function Test-Databases
{
    param(
        [String[]]$DatabaseNames,
        [PSCredential]$SqlAdministratorCredential,
        [string]$PrimaryReplica,
        [string]$SecondaryReplica,
        [string]$SqlAlwaysOnAvailabilityGroupName
    )

    # Required SQL managability modules
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null

    
    if ($null -ne $DatabaseNames) {
        # Primamry Replica connection
        $primaryServer = Get-SqlServer -InstanceName $PrimaryReplica -Credential $SqlAdministratorCredential
        $replicaServer = Get-SqlServer -InstanceName $SecondaryReplica -Credential $SqlAdministratorCredential
        
        $primaryAG = $primaryServer.AvailabilityGroups | where { $_.Name -eq $SqlAlwaysOnAvailabilityGroupName }
        $secondaryAG = $replicaServer.AvailabilityGroups | where { $_.Name -eq $SqlAlwaysOnAvailabilityGroupName }

        foreach ($database in $DatabaseNames)
        {

            if($null -ne $primaryServer.Databases[$database] ) {

                if (($secondaryAG.AvailabilityDatabases | Where-Object { $_.Name -eq $database }).IsJoined) {
                    continue
                }
                else {
                    return $false
                }
                 
            }
            else {
                return $false
            }
        } 
    }

    return $true
}
function Configure-Databases
{
    param(
        [String[]]$DatabaseNames,
        [PSCredential]$SqlAdministratorCredential,
        [string]$PrimaryReplica,
        [string]$SecondaryReplica,
        [string]$SqlAlwaysOnAvailabilityGroupName
    )
    
    # Required SQL managability modules
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null


    #If there are databases specified, then we create them, backup them up and add them to the specified AG replicas
    if ($null -ne $DatabaseNames)
    {
        
        # Primamry Replica connection
        $primaryServer = Get-SqlServer -InstanceName $PrimaryReplica -Credential $SqlAdministratorCredential

        #create database on the primary, then add them to all replicas and sync them
        foreach ($database in $DatabaseNames)
        {
            Write-Verbose -Message "Creating sample database '$($database)' ..."
            Create-SqlAlwaysOnDatabase -DatabaseName $database -Server $primaryServer

            #synchronize existing availability group replicas
            Update-SqlAlwaysOnAvailabilityGroupDatabases -SqlAlwaysOnAvailabilityGroupName $SqlAlwaysOnAvailabilityGroupName -PrimaryReplica $PrimaryReplica -SecondaryReplica $SecondaryReplica -SqlAdministratorCredential $SqlAdministratorCredential
        }

        Write-Verbose -Message "Adding databases Availability Group '$SqlAlwaysOnAvailabilityGroupName' completed."
    }
    else
    {
        Write-Verbose -Message "No databases were specified to add to Availability Group '$SqlAlwaysOnAvailabilityGroupName'."
    }
}

function Update-SqlAlwaysOnAvailabilityGroupDatabases([String]$SqlAlwaysOnAvailabilityGroupName, [String]$PrimaryReplica, [String]$SecondaryReplica, [PSCredential]$SqlAdministratorCredential)
{
    # Required SQL managability modules
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null

    # Primamry Replica connection
    $primaryServer = Get-SqlServer -InstanceName $PrimaryReplica -Credential $SqlAdministratorCredential

    # Secondary Replica connection
    $replicaServer = Get-SqlServer -InstanceName $SecondaryReplica -Credential $SqlAdministratorCredential

    # AG on primary
    $primaryAG = $primaryServer.AvailabilityGroups | where { $_.Name -eq $SqlAlwaysOnAvailabilityGroupName }

    # AG on secondary
    $secondaryAG = $replicaServer.AvailabilityGroups | where { $_.Name -eq $SqlAlwaysOnAvailabilityGroupName }

    # Prepare the backup share
    $backupFolder = [guid]::NewGuid().ToString()
    $backupPath = "$env:TEMP\$backupFolder"
    $backupShare = "\\$env:COMPUTERNAME\$backupFolder"
    Create-SqlAlwaysOnBackupShare -BackupShare $backupFolder -BackupPath $backupPath -ServiceAccount $primaryServer.ServiceAccount

    # Sync existing primary and secondary databases
    $databases = $primaryServer.Databases | where { $_.IsSystemObject -eq $false }

    foreach ($database in $databases)
    {
        # Skip any databases joined to the availability group on the secondary replica.
        if (($secondaryAG.AvailabilityDatabases | Where-Object { $_.Name -eq $Database.Name }).IsJoined)
        {
            Write-Verbose -Message "Database '$($database.Name)' already joined to availability group '$($secondaryAG.Name)', skipping ..."
            continue
        }

        # Backup the database and log from the primary replica.
        $device = "$backupShare\$($database.Name).bak"
        Write-Verbose -Message "Backing up database '$($database.Name)' from '$($primaryServer.Name)' to '$($device)' ..."
        $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
        $backup.Database = $database.Name
        $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
        $backup.Initialize = $true
        $backup.Devices.AddDevice($device, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)

        $backup.SqlBackup($primaryServer)
        Write-Verbose -Message "Successfully backed up database '$($database.Name)'."

        $device = "$backupShare\$($database.Name).log"
        Write-Verbose -Message "Backing up log for database '$($database.Name)' from '$($primaryServer.Name)' to '$($device)' ..."
        $backup = New-Object Microsoft.SqlServer.Management.Smo.Backup
        $backup.Database = $database.Name
        $backup.Action = [Microsoft.SqlServer.Management.Smo.BackupActionType]::Log
        $backup.Initialize = $true
        $backup.Devices.AddDevice($device, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
        $backup.SqlBackup($PrimaryServer)
        Write-Verbose -Message "Successfully backed up log for database '$($database.Name)'."

        # Restore the database and log to the secondary replica.
        $device = "$backupShare\$($database.Name).bak"
        Write-Verbose -Message "Restoring database '$($database.Name)' from '$($device)' to '$($PrimaryServer.Name)' ..."
        $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
        $restore.Database = $database.Name
        $restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Database
        $restore.Devices.AddDevice($device, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
        $restore.NoRecovery = $true
        $restore.SqlRestore($replicaServer)
        Write-Verbose -Message "Successfully restored database '$($database.Name)'."

        $device = "$backupShare\$($database.Name).log"
        Write-Verbose -Message "Restoring log for database '$($database.Name)' from '$($device)' to '$($PrimaryServer.Name)' ..."
        $restore = New-Object Microsoft.SqlServer.Management.Smo.Restore
        $restore.Database = $database.Name
        $restore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Log
        $restore.Devices.AddDevice($device, [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
        $restore.NoRecovery = $true
        $restore.SqlRestore($replicaServer)
        Write-Verbose -Message "Successfully restored database '$($database.Name)'."

        # Add the database to the availability group.
        if (-not ($primaryAG.AvailabilityDatabases | Where-Object { $_.Name -eq $Database.Name }))
        {
            Write-Verbose -Message "Adding database '$($database.Name)' to availability group '$($primaryAG.Name)' ..."
            $adb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase $primaryAG,$database.Name
            $primaryAG.AvailabilityDatabases.Add($adb)
            $adb.Create()
            #$primaryAG.Alter()
            Write-Verbose -Message "Successfully added database '$($database.Name)' to availability group."
        }

        # It can take some time before the database shows up in the availability group on the secondary replica.
        while ($true)
        {
            $secondaryAG.AvailabilityDatabases.Refresh()
            $databaseOnSecondary = $secondaryAG.AvailabilityDatabases | Where-Object { $_.Name -eq $Database.Name }
            if ($databaseOnSecondary)
            {
                break
            }

            Write-Verbose -Message "Waiting for database '$($database.Name)' to be available ..."
            Start-Sleep -Seconds 20
        }

        # Join the database to availabiliy group on secondary replica.
        if (-not $databaseOnSecondary.IsJoined)
        {
            Write-Verbose -Message "Joining database '$($databaseOnSecondary.Name)' to availability group '$($secondaryAG.Name)' ..."
            $databaseOnSecondary.JoinAvailablityGroup()
            Write-Verbose -Message "Successfully joined database '$($databaseOnSecondary.Name)' to availability group."
        }
    }

    # AG Replica
    $primaryAG.AvailabilityReplicas.Refresh()
    $secondaryAGReplica = $primaryAG.AvailabilityReplicas | where { $_.Name -eq $SecondaryReplica }

    # Verify the replica is in read only mode. If not, then set it
    if($secondaryAGReplica.ConnectionModeInSecondaryRole -ne [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::AllowReadIntentConnectionsOnly)
    {
        Write-Verbose -Message "Setting replica $SecondaryReplica read only mode"

        $secondaryAGReplica.ConnectionModeInSecondaryRole = [Microsoft.SqlServer.Management.Smo.AvailabilityReplicaConnectionModeInSecondaryRole]::AllowReadIntentConnectionsOnly
        #$secondaryAGReplica.Alter()

        Write-Verbose -Message "Set replica $SecondaryReplica read only mode completed!"
    }
    else
    {
        Write-Verbose -Message "Replica $SecondaryReplica is already in read only mode"
    }

    Write-Verbose -Message "Cleaning up backups ..."
    Remove-SmbShare -Name $backupFolder -Force | Out-Null

    Write-Verbose -Message "Removed share '$($backupShare)'."
    Remove-Item -Path $backupPath -Recurse -Force | Out-Null
    Write-Verbose -Message "Removed directory '$($backupPath)'."
}


# Create a database on a SQL Server instance if the database does not already exists. The user can provide a custom location of the database
# Data and Log files or accept the default by not setting the corresponding variables.
function Create-SqlAlwaysOnDatabase([string]$DatabaseName, [string]$DataPath, [string]$LogPath, [Microsoft.SqlServer.Management.Smo.Server]$Server)
{
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

    if($null -eq $Server.Databases[$DatabaseName] )
    {
        #create the database
        $db = New-Object Microsoft.SqlServer.Management.Smo.Database $Server,$DatabaseName


        # if a location for data and log is provided then use the user provided. Otherwise, we create it using the default ones
        if($DataPath -and $LogPath)
        {
            if (!(Test-Path -path $DataPath))
            {
                #create the flder
                New-Item $DataPath -Type Directory
            }

            if (!(Test-Path -path $LogPath))
            {
                #create the flder
                New-Item $LogPath -Type Directory
            }

            $sysfg = New-Object Microsoft.SqlServer.Management.Smo.FileGroup $db,'PRIMARY'

            $db.FileGroups.Add($sysfg)

            $appfg = New-Object Microsoft.SqlServer.Management.Smo.FileGroup $db,'AppFileGroup'

            $db.FileGroups.Add($appfg)

            $syslogname = $DatabaseName + '_SysData'

            $dbdsysfile = New-Object Microsoft.SqlServer.Management.Smo.DataFile $sysfg,$syslogname

            # Create the file for the raw data
            $sysfg.Files.Add($dbdsysfile)
            $dbdsysfile.FileName = $DataPath + '\' + $syslogname + '.mdf'
            $dbdsysfile.Size = [double](5.0 * 1024.0)
            $dbdsysfile.GrowthType = 'None'
            $dbdsysfile.IsPrimaryFile = 'True'

            # Create the file for the Application tables
            $applogname = $DatabaseName + '_AppData'
            $dbdappfile = New-object Microsoft.SqlServer.Management.Smo.DataFile $appfg,$applogname
            $appfg.Files.Add($dbdappfile)
            $dbdappfile.FileName = $DataPath + '\' + $applogname + '.ndf'
            $dbdappfile.Size = [double](25.0 * 1024.0)
            $dbdappfile.GrowthType = 'Percent'
            $dbdappfile.Growth = 25.0
            $dbdappfile.MaxSize = [double](100.0 * 1024.0)

            # Create the file for the log
            $loglogname = $DatabaseName + '_Log'
            $dblfile = New-Object Microsoft.SqlServer.Management.Smo.LogFile $db,$loglogname
            $db.LogFiles.Add($dblfile)
            $dblfile.FileName = $LogPath + '\' + $loglogname + '.ldf'
            $dblfile.Size = [double](10.0 * 1024.0)
            $dblfile.GrowthType = 'Percent'
            $dblfile.Growth = 25.0
        }

        # Create the database
        $db.Create()

        $createDate = $db.CreateDate
        Write-Verbose -Message "Created database '$DatabaseName' on '$createDate'"

        #refresh the server connection
        $Server.Refresh()
    }
    else
    {
        Write-Verbose -Message "Database '$DatabaseName' already exists."
    }
}

# create a folder and share it for AlwaysOn backup.
# If the folder already exists, then we don't create it again
# If the folder already shared, then we don't modify sharing settings
# Otherwise, the function creates and share the folder
function Create-SqlAlwaysOnBackupShare([string]$BackupShare, [string]$BackupPath, [string]$ServiceAccount)
{
    Write-Verbose -Message "Creating directory '$($BackupFolder)' ..."

    # create folder if it does not exist
    if (!(Test-Path -path $BackupPath))
    {
        #create the flder
        New-Item $BackupPath -Type Directory
    }

    # always ACL it for service account
    icacls.exe "$BackupPath" /grant:r ($ServiceAccount + ":(OI)(CI)F") | Out-Null

    # escape '\'
    $WMIFolderPath = $BackupPath -replace '\\','\\'

    # if the directory is not shared, then share it
    if(Get-CimInstance -Query "SELECT * FROM Win32_Share WHERE Path='$WMIFolderPath'")
    {
          Write-Verbose  -Message "Folder $WMIFolderPath already shared"
    }
    else
    {
        New-SmbShare -Name $BackupShare -Path $BackupPath -FullAccess $ServiceAccount -Temporary | Out-Null

        Write-Verbose  -Message "Shared folder $BackupPath as $BackupShare"
    }
}

# Create SQL Server SMO object using provided isntance name and credentials
# Create SQL Server SMO object using provided isntance name and credentials
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
    #[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")| Out-Null
    
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


