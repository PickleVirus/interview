<#
.SYNOPSIS
    
    Script was created for testing purposes of CI/CD deployment proccess.
   
.DESCRIPTION
    
    Use in VSTS enviroment carefully.
    Map this script to the Azure Powershell task in release definition.
    Always use -ResourceGroupLocation and -ResourceGroupName arguments.
    Don't forget to change storage name with making new resource group in the same location.
     
.NOTES
    File Name      : ContiniousDeploument-AzureResourceGroup.ps1
    Author         : G.A. Sobolev (gasobolev@gmail.com)
    Prerequisite   : PowerShell V3
    Copyright 2017

#>


Param(
  [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
  [string] [Parameter(Mandatory=$true)] $ResourceGroupName,
  [switch] $UploadArtifacts = $true, ### Delete if unnecessary argument
  [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
  [string] $TemplateFile = '..\Templates\azuredeploy.json',
  [string] $TemplateParametersFile = '..\Templates\azuredeploy.parameters.json',
  [string] $ArtifactStagingDirectory = '..\..',
  [string] $DSCSource = "ConfigureWebServer.ps1",
  [string] $DSCOperationConfiguration = "Main", ### If you need to change or add configuration manualy
  [string] $ApplicationName, ### Need to get this from artifact .zip file
  [string] $VMName ### Need to get it from json parameters file
)

### Unnecessary operations?
<#
Set-StrictMode -Version 3
Import-Module Azure -ErrorAction SilentlyContinue
try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-HostInCloud$($host.name)".replace(" ","_"), "2.8")
} catch { }
#>


### Resource group deployment functions


Write-Host Starting to deploy $ApplicationName project

### Preparing constants
$ResourceGroupLocation = $ResourceGroupLocation.ToLowerInvariant() -replace "\s",""
$TemplateFile = [System.IO.Path]::Combine($PSScriptRoot, $TemplateFile)
$TemplateParametersFile = [System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile)
$DSCSourceFilePath = [System.IO.Path]::Combine($PSScriptRoot, $DSCSource)
$ArtifactStagingDirectory = [System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory)
[string]$ApplicationName = (Get-Childitem $ArtifactStagingDirectory -File *zip ) -replace ".zip",""

Write-Host Staging directory is $ArtifactStagingDirectory

### Get VMName from JSON configuration
$JsonContent = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json 
               $VMName = $JsonContent.parameters.vmName.value
               $StorageAccountName = $JsonContent.parameters.StorageAccountName.value
    

### Create or update the resource group using the specified template file and template parameters file
New-AzureRmResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force -ErrorAction Stop 

New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                   -ResourceGroupName $ResourceGroupName `
                                   -TemplateFile $TemplateFile `
                                   -TemplateParameterFile $TemplateParametersFile `
                                   -Mode Complete -Force -Verbose -ErrorAction Stop


### Artifact delivery function


### Get artifacts
$Files = (Get-ChildItem $ArtifactStagingDirectory -File).FullName


### Get storage account context
$AzureStorageContext = (Get-AzureRmStorageAccount -ResourceGroupName $ResourceGroupName ).Context

### Make new blob container if not exists
$AzureStorageContainer = New-AzureStorageContainer -Name $StorageContainerName `
                                                   -Context $AzureStorageContext `
                                                   -ErrorAction SilentlyContinue

### Remove old blobs if exists
$blobs = Get-AzureStorageBlob -Container $StorageContainerName -Context $AzureStorageContext
$blobs | Remove-AzureStorageBlob -ErrorAction SilentlyContinue

### Add artifacts to container 
foreach ($File in $Files ){

$AzureStorageContext | Set-AzureStorageBlobContent -Container $StorageContainerName -File $File

}


### Unnecessary file checking
### $AzureStorageContext | Get-AzureStorageBlob -Container $StorageContainerName

### Making transfer variables with SAS token generation for DSC deployment
[string]$ArtifactsLocation = $AzureStorageContext.BlobEndPoint + $StorageContainerName
[string]$ArtifactsLocationSasToken = New-AzureStorageContainerSASToken -Container $StorageContainerName `
                                                                       -Context $AzureStorageContext `
                                                                       -Permission r -ExpiryTime (Get-Date).AddHours(2)


### DSC template deployment function

### Create and set DSC template resource 
Publish-AzureRmVMDscConfiguration -ConfigurationPath $DSCSourceFilePath -ResourceGroupName $ResourceGroupName -StorageAccountName $StorageAccountName -ErrorAction Stop -force 
Set-AzureRmVmDscExtension -Version 2.21 -ResourceGroupName $ResourceGroupName `
                          -VMName "$VMName" -ArchiveStorageAccountName $StorageAccountName `
                          -ArchiveBlobName "$DSCSource.zip" -AutoUpdate:$true `
                          -ConfigurationName "$DSCOperationConfiguration" `
                          -ConfigurationArgument @{"nodeName" = "$VMName";"containerUrl" = $ArtifactsLocation;"SASToken" = $ArtifactsLocationSasToken; "ApplicationName" = $ApplicationName } `
                          -ErrorAction Stop

### Apply DSC template to VM
Update-AzureRmVM -VM (Get-AzureRmVM -Name $VMName -ResourceGroupName $ResourceGroupName) -ResourceGroupName $ResourceGroupName

### Remove template for further operations with templates on VM (Only one template could be applied to VM at once)
Remove-AzureRmVMDscExtension -ResourceGroupName $ResourceGroupName -VMName $VMName