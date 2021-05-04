# InstallSQLServerByDSCForAzure

This ARM Template installs SQL Server onto a Windows Server using PowerShell DSC. It does the following:

* Creates a StoragePool for use by SQL Server
* Uses an Azure Files share with the SQL Server installation files to install SQL Server
* Domain joins the SQL Server
* Allows you to specify which SQL Server features you want installed

It allows you to customize many settings for the installation including:

* The operating disk size
* The number of data disks to use for databases 
* The number of data disks to use for logs (note: will have host caching turned off for these)
* The sizes of the virtual disks and drive letters for each of the disks
* Settings for maximum degree of parallelism, collation, reserved memory, etc.
* The instance name


