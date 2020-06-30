Param(
    [string] [Parameter(Mandatory = $true)] $ResourceGroupName,
	[string] [Parameter(Mandatory = $true)] $FactoryName,
	[string] [Parameter(Mandatory = $true)] $PipelineName,
	[string] [Parameter(Mandatory = $true)] $PipelineFolderName,
	[string] [Parameter(Mandatory = $true)] $ReferencePipelineName,
	[string] [Parameter(Mandatory = $true)] $CosmosDBAccount,
	[string] [Parameter(Mandatory = $true)] $CosmosDBName
)

#Installing CosmosDB module
if (!(Get-Module CosmosDB)) {
	Write-Host "Installing/updating CosmosDB module..."
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
	Install-Module -Name CosmosDB -MaximumVersion 2.50 -Scope CurrentUser -Force
}

$primaryKey = Get-CosmosDbAccountMasterKey -Name $CosmosDBAccount -ResourceGroupName $ResourceGroupName
$cosmosDbContext = New-CosmosDbContext -Account $CosmosDBAccount -Database $CosmosDBName -Key $primaryKey
$CollectionNames = Get-CosmosDbCollection -Context $cosmosDbContext

#if DB contains one collection then $CollectionNames will be the object not the list (so we always create a list)
$CollectionNames = @($CollectionNames)

$jsonActivities = @()

$CollectionNames.ForEach({
	$jsonActivities = $jsonActivities + @{
		name = 'Copy ' + $_.id;
		type = 'ExecutePipeline';
		userProperties = @();
		typeProperties = @{
			pipeline = @{
				referenceName = $ReferencePipelineName;
				type = 'PipelineReference';
			};
			parameters = @{
				collection = $_.id
			}
		}
	}
})

$finalRepresentation = @{
	name = $PipelineName;
	properties = @{
		activities = $jsonActivities;
		folder = @{
			name = $PipelineFolderName;
		}
	}
}

$finalRepresentation | ConvertTo-Json -depth 100 `
					 | Out-File ".\pipeline.json" -Encoding UTF8

Set-AzureRmDataFactoryV2Pipeline `
	-ResourceGroupName $ResourceGroupName `
	-Name $PipelineName `
	-DataFactoryName $FactoryName `
	-File ".\pipeline.json" -Force