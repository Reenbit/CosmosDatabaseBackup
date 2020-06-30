Param(
    [string] [Parameter(Mandatory=$true)] $ResourceGroupLocation,
    [string] [Parameter(Mandatory=$true)] $ResourceGroupName,
    [string] [Parameter(Mandatory=$true)] $StorageAccountName,
	[string] [Parameter(Mandatory = $true)] $FactoryName,
	[string] [Parameter(Mandatory = $true)] $KeyVaultName,
	[string] [Parameter(Mandatory = $true)] $CosmosDBAccount,
	[string] [Parameter(Mandatory = $true)] $CosmosDBName
)

$TemplateFile = '../Templates/data-factory-backupdb.json'
$TemplateParametersFile = '../Templates/data-factory-backupdb.parameters.json'
$ArtifactStagingDirectory = '../DBBackup/Templates'
$StorageContainerName = 'backupartifacts'
$DSCSourceFolder = 'DSC'
$PipelineName = 'Main'
$PipelineFolderName = 'Backup'
$ReferencePipelineName = 'CopySingleCollection'

$TemplateParameters = @{}

$TemplateParameters['factoryName'] = $FactoryName
$TemplateParameters['factoryLocation'] = $ResourceGroupLocation
$TemplateParameters['keyVaultName'] = $KeyVaultName
$TemplateParameters['dataFactoryTemplateFolder'] = './data-factory'
$TemplateParameters['sourceCosmosDbToBeBackupConnectionStringSecretName'] = 'CosmosDbBackup-Read'
$TemplateParameters['targetBlobForBackupConnectionStringSecretName'] = 'Storage-ReadWrite'
$TemplateParameters['cosmosDbRestoreConnectionStringSecretName'] = 'CosmosDbBackup-Write'

try {
    [Microsoft.Azure.Common.Authentication.AzureSession]::ClientFactory.AddUserAgent("VSAzureTools-$UI$($host.name)".replace(' ','_'), '3.0.0')
} catch { }

#disabling triggers from Data Factory before deploying it
try #doing this in try cause for the first time Data Factory will not be available
{
	$triggersADF = Get-AzureRmDataFactoryV2Trigger -DataFactoryName $FactoryName -ResourceGroupName $ResourceGroupName
	$triggersADF | ForEach-Object { Stop-AzureRmDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $FactoryName -Name $_.name -Force }
	Write-Host 'All triggers from Data Factory were disabled'
}
catch {}

#start provisioning resources for Data Factory

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3

function Format-ValidationOutput {
    param ($ValidationOutput, [int] $Depth = 0)
    Set-StrictMode -Off
    return @($ValidationOutput | Where-Object { $_ -ne $null } | ForEach-Object { @('  ' * $Depth + ': ' + $_.Message) + @(Format-ValidationOutput @($_.Details) ($Depth + 1)) })
}

$OptionalParameters = New-Object -TypeName Hashtable
$TemplateFile = [System.IO.Path]::Combine($ArtifactStagingDirectory, $TemplateFile)
$TemplateParametersFile = [System.IO.Path]::Combine($ArtifactStagingDirectory, $TemplateParametersFile)

$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))

# Convert relative paths to absolute paths if needed
$ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
$DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

# Parse the parameter file and update the values of artifacts location and artifacts location SAS token if they are present
$JsonParameters = Get-Content $TemplateParametersFile -Raw | ConvertFrom-Json
if (($JsonParameters | Get-Member -Type NoteProperty 'parameters') -ne $null) {
    $JsonParameters = $JsonParameters.parameters
}
$ArtifactsLocationName = 'artifactsLocation'
$ArtifactsLocationSasTokenName = 'artifactsLocationSasToken'
$OptionalParameters[$ArtifactsLocationName] = $JsonParameters | Select -Expand $ArtifactsLocationName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore
$OptionalParameters[$ArtifactsLocationSasTokenName] = $JsonParameters | Select -Expand $ArtifactsLocationSasTokenName -ErrorAction Ignore | Select -Expand 'value' -ErrorAction Ignore

# Create DSC configuration archive
if (Test-Path $DSCSourceFolder) {
    $DSCSourceFilePaths = @(Get-ChildItem $DSCSourceFolder -File -Filter '*.ps1' | ForEach-Object -Process {$_.FullName})
    foreach ($DSCSourceFilePath in $DSCSourceFilePaths) {
        $DSCArchiveFilePath = $DSCSourceFilePath.Substring(0, $DSCSourceFilePath.Length - 4) + '.zip'
        Publish-AzureRmVMDscConfiguration $DSCSourceFilePath -OutputArchivePath $DSCArchiveFilePath -Force -Verbose
    }
}

# Create a storage account name if none was provided
if ($StorageAccountName -eq '') {
    $StorageAccountName = 'stage' + ((Get-AzureRmContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 19)
}

$StorageAccount = (Get-AzureRmStorageAccount | Where-Object{$_.StorageAccountName -eq $StorageAccountName})

# Create the storage account if it doesn't already exist
if ($StorageAccount -eq $null) {
    New-AzureRmResourceGroup -Location "$ResourceGroupLocation" -Name $ResourceGroupName -Force
    $StorageAccount = New-AzureRmStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $ResourceGroupName -Location "$ResourceGroupLocation"
}

# Generate the value for artifacts location if it is not provided in the parameter file
if ($OptionalParameters[$ArtifactsLocationName] -eq $null) {
    $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
}

# Copy files from the local storage staging location to the storage account container
New-AzureStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1

$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process {$_.FullName}
foreach ($SourcePath in $ArtifactFilePaths) {
    Set-AzureStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
        -Container $StorageContainerName -Context $StorageAccount.Context -Force
}

# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
if ($OptionalParameters[$ArtifactsLocationSasTokenName] -eq $null) {
    $OptionalParameters[$ArtifactsLocationSasTokenName] = New-AzureStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)
}

Write-Host 'Start deploying Azure Data Factory for doing backups for Cosmos DB'

New-AzureRmResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
                                    -ResourceGroupName $ResourceGroupName `
                                    -TemplateFile $TemplateFile `
                                    -TemplateParameterFile $TemplateParametersFile `
									@TemplateParameters `
                                    @OptionalParameters `
                                    -Force -Verbose `
                                    -ErrorVariable ErrorMessages
if ($ErrorMessages) {
    Write-Output '', 'Template deployment returned the following errors:', @(@($ErrorMessages) | ForEach-Object { $_.Exception.Message.TrimEnd("`r`n") })
	throw "Deployment of ADF was unsuccessful"
}

#Adding Main pipeline for orchestration of copies pipelines 
.\DBBackup\AddDataFactoryOrchestrationPipeline.ps1 `
	-ResourceGroupName $ResourceGroupName `
	-FactoryName $FactoryName `
	-PipelineName $PipelineName `
	-PipelineFolderName $PipelineFolderName `
	-ReferencePipelineName $ReferencePipelineName `
	-CosmosDBAccount $CosmosDBAccount `
	-CosmosDBName $CosmosDBName

#Adding ADF to KeyVault policies
$dataFactoryIdentity = (Get-AzureRmDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $FactoryName).Identity

Set-AzureRmKeyVaultAccessPolicy -VaultName $KeyVaultName -ObjectId $dataFactoryIdentity.PrincipalId -PermissionsToSecrets Get -BypassObjectIdValidation 

#enabling triggers from Data Factory after it was deployed
$triggersADF = Get-AzureRmDataFactoryV2Trigger -DataFactoryName $FactoryName -ResourceGroupName $ResourceGroupName
$triggersADF | ForEach-Object { Start-AzureRmDataFactoryV2Trigger -ResourceGroupName $ResourceGroupName -DataFactoryName $FactoryName -Name $_.name -Force }
Write-Host 'All triggers from Data Factory were enabled'

Write-Host 'Successfully created/update ADF to do backups for Cosmos DB'
