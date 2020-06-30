Param (
	# Azure AD
	[Parameter(Mandatory=$true)]
    [string] $AadAdmin,

	[Parameter(Mandatory=$true)]
    [secureString] $AadPassword,
	
	# Resource group
	[Parameter(Mandatory=$true)]
	[string] $ResourceGroupLocation,

    [string] $ResourceGroupName = 'cosmos-test',

	[string] $ResourceNamePrefix = 'bk',

    [string] $TemplateFile = 'azuredeploy.json',

	# General
	[Parameter(Mandatory=$true)]
	[string] $Environment = 'dev',

	[bool] $IsDevelopment = $true,

	#CosmosDB
	[string] $CosmosDbName = 'dataStorageDb',

	[string] $CosmosDbDefaultRu = '400',

	# App service plan
	[string] $AppServicePlanSKUTier = 'Standard',

	[string] $AppServicePlanSKUName = 'S1'
)

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$AadTenantId = (Get-AzureRmContext).Tenant.Id
$ArtifactsStorageAccountName = $ResourceNamePrefix + $Environment + 'artifacts'
$ArtifactsStorageContainerName = 'artifacts'
$ArtifactsStagingDirectory = '.\Artifacts'
$FactoryName = $ResourceNamePrefix + $Environment + 'datafactory'

$collectionsForCosmosDB = @{
	collection1 = @{
			name  = 'documents'
			ru = $CosmosDbDefaultRu
		}
}

function CreateResourceGroup() {
	$parameters = New-Object -TypeName Hashtable

	# general
	$parameters['project'] = $ResourceNamePrefix
	$parameters['environment'] = $Environment
	$parameters['isDevelopment'] = $IsDevelopment

	#CosmosDB
	$parameters['cosmosDbName'] = $CosmosDbName

	# App service plan
	$parameters['appServicePlanSKUTier'] = $AppServicePlanSKUTier
	$parameters['appServicePlanSKUName'] = $AppServicePlanSKUName

	.\Deploy-AzureResourcegroup.ps1 `
	    -resourcegrouplocation $resourcegrouplocation `
		-resourcegroupname $resourcegroupname `
		-uploadartifacts `
		-storageaccountname $artifactsstorageaccountname `
		-storagecontainername $artifactsstoragecontainername `
		-artifactstagingdirectory $artifactsstagingdirectory `
		-templatefile $templatefile `
		-templateparameters $parameters
}

function Main() {
	$deployment = CreateResourceGroup
	$deployment

	if ($deployment.ProvisioningState -eq 'Failed'){
		throw "Deployment was unsuccessful"
	}

	$webApiName = $deployment.outputs.webApiName.Value
	$keyVaultName = $deployment.outputs.keyVaultName.Value
	$appInsightsName = $deployment.outputs.appInsightsName.Value
	$appInsightsInstrumentationKey = $deployment.outputs.appInsightsInstrumentationKey.Value
	$cosmosDbAccountName = $deployment.outputs.cosmosDbAccountName.Value
	$cosmosDbAccountUri = $deployment.outputs.cosmosDbAccountUri.Value
	$cosmosDbAccountPrimaryKey = $deployment.outputs.cosmosDbAccountPrimaryKey.Value
	
	#Create database and collections for CosmosDB
	.\CosmosDB\SetupCosmosDB.ps1 `
	-CosmosDBAccount $cosmosDbAccountName `
	-CosmosDBName $CosmosDbName `
	-CosmosDBPrimaryKey $cosmosDbAccountPrimaryKey `
	-Collections $collectionsForCosmosDB

	#Creates Azure Data Factory for backups of Cosmos DB
	.\DBBackup\Add-CosmosDbBackup.ps1 `
	-ResourceGroupLocation $ResourceGroupLocation `
	-ResourceGroupName $ResourceGroupName `
	-StorageAccountName $ArtifactsStorageAccountName `
	-FactoryName $FactoryName `
	-KeyVaultName $keyVaultName `
	-CosmosDBAccount $cosmosDbAccountName `
	-CosmosDBName $CosmosDbName
	
	# set application settings for web api
	$apiAppSettings = @{
		'KeyVault:Name' = $keyVaultName;
		'ApplicationInsights:InstrumentationKey' = $appInsightsInstrumentationKey;
		'CosmosDb:AccountUri' = $cosmosDbAccountUri;
	}
	.\Configure-AppSettings.ps1 `
	-ResourceGroupName $ResourceGroupName `
	-WebAppName $webApiName `
	-AppSettings $apiAppSettings
}

Main