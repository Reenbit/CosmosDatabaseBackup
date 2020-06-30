#Requires -Version 3.0

Param(
    [string] [Parameter(Mandatory = $true)] $ResourceGroupName,
    [string] [Parameter(Mandatory = $true)] $WebAppName,
    [hashtable] [Parameter(Mandatory = $true)] $AppSettings
)

function MergeAppSettings($CurrentSettings)
{
    $hash = @{}
    ForEach ($kvp in $CurrentSettings) {
        $hash[$kvp.Name] = $kvp.Value
    }

    $AppSettings.GetEnumerator() | ForEach-Object {
        $hash[$_.key] = $_.value
    }

    return $hash
}

Write-Host "Configuring Application Settings for application $WebAppName..."

$webApp = Get-AzureRmWebApp `
    -ResourceGroupName $ResourceGroupName `
    -Name $WebAppName

if (!$webApp) {
    throw "Web App $WebAppName not found"
}

$settings = MergeAppSettings -CurrentSettings $webApp.SiteConfig.AppSettings

Set-AzureRmWebApp `
    -ResourceGroupName $ResourceGroupName `
    -Name $WebAppName `
    -AppSettings $settings

$slots = Get-AzureRMWebAppSlot `
    -ResourceGroupName $ResourceGroupName `
    -Name $WebAppName

ForEach ($slot in $slots) {
    $indexOf = $slot.Name.IndexOf('/')
    $slotName = $slot.Name.SubString($indexOf+1)

    $slot = Get-AzureRMWebAppSlot `
        -ResourceGroupName $ResourceGroupName `
        -Name $WebAppName `
        -Slot $slotName

    $settings = MergeAppSettings -CurrentSettings $slot.SiteConfig.AppSettings

    Write-Host "Configuring Application Settings for application $WebAppName slot $slotName..."

    Set-AzureRmWebAppSlot `
        -ResourceGroupName $ResourceGroupName `
        -Name $WebAppName `
        -AppSettings $settings `
        -Slot $slotName
}
