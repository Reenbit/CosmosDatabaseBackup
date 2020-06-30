#
# localdeploy.ps1
# script can be used for deployment from local pc to Azure

clear

if ((Get-AzureRmContext).Subscription.Name -ne "NovaX")
{
    Login-AzureRmAccount

    Set-AzureRmContext -Subscription NovaX
}

$AadAdmin = "vmagometa@outlook.com"
$AadPassword = ConvertTo-SecureString "..." -AsPlainText -Force
$ResourceGroupLocation = "eastus"
$Environment = "dev"

.\Deploy-App.ps1 -AadAdmin $AadAdmin `
   -AadPassword $AadPassword `
   -ResourceGroupLocation $ResourceGroupLocation `
   -Environment $Environment