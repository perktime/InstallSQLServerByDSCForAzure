Configuration SQLInstall
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$PackagePath,

        [Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$AdminCreds,
		
		[Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$FileShareCreds,
		
		[Parameter(Mandatory)]
		[String]$InstallDir,
		
		[Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$SQLAgentCreds,
		
		[Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$SQLServiceCreds,
		
		[Parameter(Mandatory)]
		[System.Management.Automation.PSCredential]$SQLSAAccountCreds,
        
        [Parameter(Mandatory)]
		[String]$ProductKey,
        
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Features,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$UpdateSource,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$UpdateEnabled,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$InstallSharedDir,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$InstallSharedWOWDir,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLInstanceName,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLInstanceDir,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SecurityMode,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLSysAdminAccounts,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLUserDBDir,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLUserDBLogDir,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLTempDBDir,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLTempDBLogDir,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLBackupDir,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$SQLCollation,

		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$DomainName,
		
		[Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$DomainCreds,

        [Parameter(Mandatory)]
        [UInt32]$NumberOfDataDisks = 2,

        [Parameter(Mandatory)]
        [UInt32]$NumberOfLogDisks = 2,

        [Parameter(Mandatory)]
        [String[]]$DataDiskLetters,
        
        [Parameter(Mandatory)]
        [String[]]$DataDiskSizes,

        [Parameter(Mandatory)]
        [String[]]$LogDiskLetters,
        
        [Parameter(Mandatory)]
        [String[]]$LogDiskSizes,

        [Parameter(Mandatory)]
        [String]$WorkloadType = "GENERAL",

        [String]$OUPath,
        [Parameter(Mandatory)]
		[int]$maxDegreeOfParallelism,           

		[Parameter(Mandatory)]
		[int]$OSReservedMemoryInGB

		

    )
	Import-DscResource -ModuleName xSQLServer, xComputerManagement, CDisk, xDisk, xSQL
    $startingLogDeviceId = $NumberOfDataDisks + 2

    Node localhost
    {
        Log ParamLog
        {
            Message = "Running SQLInstall. PackagePath = $PackagePath"
        }

        #
        # Ensure that .NET framework features are installed (pre-reqs for SQL)
        #
        WindowsFeature NetFramework35Core
        {
            Name = "NET-Framework-Core"
            Ensure = "Present"
        }

        WindowsFeature NetFramework45Core
        {
            Name = "NET-Framework-45-Core"
            Ensure = "Present"            
        }  
        $RebootVirtualMachine = $false

        xSqlCreateVirtualDataDisk NewVirtualDataDisk
        {
            NumberOfDisks = $NumberOfDataDisks
            NumberOfColumns = $NumberOfDataDisks
            DiskLetters = $DataDiskLetters
            DiskSizes = $DataDiskSizes
            OptimizationType = $WorkloadType
            StartingDeviceID = 2
            RebootVirtualMachine = $RebootVirtualMachine
        }

        xSqlCreateVirtualDataDisk NewVirtualLogDisk
        {
            NumberOfDisks = $NumberOfLogDisks
            NumberOfColumns = $NumberOfLogDisks
            DiskLetters = $LogDiskLetters
            DiskSizes = $LogDiskSizes
            OptimizationType = $WorkloadType
            StartingDeviceID = $startingLogDeviceId
            RebootVirtualMachine = $RebootVirtualMachine
            DependsOn = "[xSqlCreateVirtualDataDisk]NewVirtualDataDisk"
        }

		xComputer DomainJoin
        {			
            Name = $env:COMPUTERNAME
            DomainName = $DomainName
            Credential = $DomainCreds
            JoinOU = $OUPath             
        }

		xSQLServerSetup SQLServerSetup
		{ 
            SourcePath = $PackagePath
            SourceFolder = $InstallDir
            SourceCredential = $FileShareCreds           
            SetupCredential = $AdminCreds
			SQLSvcAccount = $SQLServiceCreds
            AgtSvcAccount = $SQLAgentCreds
			SAPWd = $SQLSAAccountCreds			
			PID = $ProductKey
			InstanceName =  $SQLInstanceName  
			InstanceDir = $SQLInstanceDir  
            SecurityMode =  $SecurityMode 
            SQLSysAdminAccounts =  @($SQLSysAdminAccounts)
			UpdateSource = $UpdateSource 
     		InstallSharedDir = $InstallSharedDir
            InstallSharedWOWDir = $InstallSharedWOWDir
			Features = "$Features" 
            UpdateEnabled =  $UpdateEnabled 
            SQLUserDBDir = $SQLUserDBDir
            SQLUserDBLogDir = $SQLUserDBLogDir
            SQLTempDBDir = $SQLTempDBDir
            SQLTempDBLogDir = $SQLTempDBLogDir
            SQLBackupDir = $SQLBackupDir
            SQLCollation = $sqlCollation
            DependsOn = "[xSqlCreateVirtualDataDisk]NewVirtualLogDisk"
        }  
        xSQLServerMaxDop MaxDegParallelism
			{
				Ensure = 'Present'
				MaxDop = $maxDegreeOfParallelism
				SQLInstanceName = $SQLInstanceName
				SQLServer = $env:COMPUTERNAME
			}
			
        $SQLServerMemory = GetServerAvailableMemory($OSReservedMemoryInGB)
        Write-Verbose -Message "Setting SQL Server Memory to $SQLServerMemory" -Verbose 
        xSQLServerMemory ServerMaxMemory
        {
            SQLInstanceName = $SQLInstanceName
            SQLServer = $env:COMPUTERNAME
            Ensure = 'Present'
            DynamicAlloc = $false
            MinMemory = $SQLServerMemory			
            MaxMemory = $SQLServerMemory 
        }  

        File SSMSInstallCopyDir
        {
            Ensure = "Present"
            Type = "Directory"
            Recurse = $True
            SourcePath = $PackagePath + "\ssms"
            DestinationPath = "d:\ssms"
            Credential = $FileShareCreds            
        }

        WindowsProcess SSMSInstall
        {
            Arguments = '/install /quiet /passive /norestart'
            Path = "d:\ssms\SSMS-Setup-ENU.exe"        
        }

		LocalConfigurationManager 
        {
            RebootNodeIfNeeded = $True
        }

    }
}

function GetServerAvailableMemory()
	{
		[cmdletbinding()]
		Param( 
			[int]$OSReservedMemoryInGB
		)
		$totalMemory = Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property capacity -Sum | Foreach {"{0:N2}" -f ([math]::round(($_.Sum / 1GB),2))}
		$totalMemory = ($totalMemory - $OSReservedMemoryInGB) * 1024

		return $totalMemory			
	}
