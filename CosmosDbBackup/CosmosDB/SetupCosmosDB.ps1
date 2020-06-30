Param(
    [string] [Parameter(Mandatory = $true)] $CosmosDBAccount,
	[string] [Parameter(Mandatory = $true)] $CosmosDBName,
	[string] [Parameter(Mandatory = $true)] $CosmosDBPrimaryKey,
	[hashtable] [Parameter(Mandatory = $true)] $Collections
)

#Installing CosmosDB module
if (!(Get-Module CosmosDB)) {
	Write-Host "Installing/updating CosmosDB module..."
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
	Install-Module -Name CosmosDB -MaximumVersion 2.50 -Scope CurrentUser -Force
}

$primaryKey = ConvertTo-SecureString -String $CosmosDBPrimaryKey -AsPlainText -Force	
$cosmosDbContext = New-CosmosDbContext -Account $CosmosDBAccount -Key $primaryKey
try
{
	#if database doesn't exist exception will be thrown
	Get-CosmosDbDatabase -Context $cosmosDbContext -Id $CosmosDBName
}
catch
{
	New-CosmosDbDatabase -Context $cosmosDbContext -Id $CosmosDBName
}

$cosmosDbContext = New-CosmosDbContext -Account $CosmosDBAccount -Database $CosmosDBName -Key $primaryKey

$Collections.keys | ForEach-Object{
	$name = $Collections[$_].name
	$ru = $Collections[$_].ru
	
	try 
	{
		Write-Host 
		#if collection doesn't exist exception will be thrown
		Get-CosmosDbCollection -Context $cosmosDbContext -Id $name
	}
	catch
	{
		New-CosmosDbCollection -Context $cosmosDbContext -Id $name -OfferThroughput $ru
	}
}