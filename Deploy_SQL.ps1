#Subscription ID to deploy the cluster on
$subscriptionId = "f86c3XXXXX-XXXXXX-XXXXXX-XXXXXX2"
#Resource Group for the SQL Cluster
$resourceGroup = "petesqlrg01"
#Resource Group Location
$location ="centralus"
#Staging location to upload artifacts
$artifactslocation = "https://peteafs01.blob.core.windows.net/sqlinstall"
#Storage Account Key to be able to access the location above
$artifactskey = "XXXXXXXXXXXXXXXXXXX"
#Artifacts local location
$locallocation = "C:\Source\PowerSchool\SQLServerInstalledByDsc\"
#Location of the template file
$TemplateFile = $locallocation + "azuredeploy.json"
#Location of the parameters file
$TemplateParametersFile = $locallocation + "azuredeploy.parameters.json"

#zip up DSC files
$dscRoot = $locallocation + "dsc"
$dscModuleDirs = @("SQLInstall.ps1")

foreach ($moduleDir in $dscModuleDirs)
{
    $dscPath = $dscRoot + "\" + $moduleDir
    $zipFileName = $dscPath + ".zip"
    Compress-Archive -Path $($dscPath + "\*") -DestinationPath $zipFileName -Update -Verbose

}

#Upload all artifacts
$azcopyExe="{0}\Microsoft SDKs\Azure\AzCopy\azcopy.exe" -f ${env:ProgramFiles(x86)}
& $azcopyExe /source:$locallocation /dest:$artifactslocation /Destkey:$artifactskey /s /y


#Login to Azure Account
#Connect-AzureRmAccount

#Select the Subscription
Select-AzureRmSubscription -Subscription $subscriptionId

# Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $resourceGroup -Location $location -Verbose -Force

#Deploy Template
New-AzureRmResourceGroupDeployment -Name "deploySQLServer" `
                                       -ResourceGroupName $resourceGroup `
                                       -TemplateFile $TemplateFile `
                                       -TemplateParameterFile $TemplateParametersFile `
                                       -Force -Verbose `
                                       -ErrorVariable ErrorMessages

if ($ErrorMessages) 
{
Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
}

