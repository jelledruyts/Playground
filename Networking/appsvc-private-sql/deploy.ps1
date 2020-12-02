function New-RegionDeployment {
    param (
        $Location, $Prefix, $Suffix = "", $VNetId = 1, $SqlAdministratorLoginName, [SecureString]$SqlAdministratorLoginPassword, $SkipSqlDatabase = $False
    )
    New-AzResourceGroup -Name "$ResourceGroupNamePrefix$Suffix" -Location $Location -Verbose -Force

    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName "$ResourceGroupNamePrefix$Suffix" `
        -TemplateFile "deploy-region.json" `
        -location $Location `
        -uniquePrefix $Prefix `
        -resourceSuffix $Suffix `
        -vnetId $VNetId `
        -sqlAdministratorLoginName $sqlAdministratorLoginName `
        -sqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
        -skipSqlDatabase $SkipSqlDatabase
}

function New-RemotePrivateEndpointDeployment {
    param (
        $Location, $Prefix, $Suffix, $RemoteSuffix, $SubnetResourceId, $SqlResourceId
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName "$ResourceGroupNamePrefix$Suffix" `
        -TemplateFile "deploy-remote-privateendpoint.json" `
        -location $Location `
        -uniquePrefix $Prefix `
        -remoteSuffix $RemoteSuffix `
        -subnetResourceId $SubnetResourceId `
        -sqlResourceId $SqlResourceId
}

function New-RemoteDnsRecordDeployment {
    param (
        $Suffix, $HostName, $PrivateEndpointNicResourceId
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName "$ResourceGroupNamePrefix$Suffix" `
        -TemplateFile "deploy-remote-dnsrecord.json" `
        -hostName $HostName `
        -privateEndpointNicResourceId $PrivateEndpointNicResourceId
}

function New-SqlFailoverGroupDeployment {
    param (
        $Location, $Prefix, $Suffix, $PrimarySqlServerName, $SecondarySqlServerResourceId, $SqlDatabaseName
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName "$ResourceGroupNamePrefix$Suffix" `
        -TemplateFile "deploy-sql-failovergroup.json" `
        -location $Location `
        -uniquePrefix $Prefix `
        -sqlServerPrimaryName $PrimarySqlServerName `
        -sqlServerSecondaryResourceId $SecondarySqlServerResourceId `
        -sqlDatabaseName $SqlDatabaseName
}

$ErrorActionPreference = "Stop" # Break on errors

$SubscriptionName = "Azure CXP FTA Internal Subscription JELLED"
$ResourceGroupNamePrefix = "appsvc-private-sql-multiregion"
$UniquePrefix = "jelled"
$PrimaryLocation = "West Europe"
$PrimarySuffix = "-primary"
$SecondaryLocation = "North Europe"
$SecondarySuffix = "-secondary"
$sqlAdministratorLoginName = "sqladmin"
$SqlAdministratorLoginPassword = Read-Host "Enter the password for the SQL administrator" -AsSecureString

if ($(Get-AzContext).Subscription.Name -ne $SubscriptionName)
{
    Connect-AzAccount
    Set-AzContext $SubscriptionName
}

$Choice = Read-Host -Prompt "Enter 'S' to deploy to a Single region or 'M' to deploy to Multiple regions"
Write-Host ""
switch ($Choice)
{
    "S"
    {
        Write-Host "Deploying services..."
        $OutputsRegion = New-RegionDeployment -Location $PrimaryLocation -Prefix $UniquePrefix -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword -SkipSqlDatabase $True
        break
    }
    "M"
    {
        # Deploy the regional services.
        # Note that the primary and secondary deployments must each have their own Resource Group as the
        # DNS Private Zone must be unique within the Resource Group (and each region needs its own different copy).
        Write-Host "Deploying services to primary region..."
        $PrimaryOutputsRegion = New-RegionDeployment -Location $PrimaryLocation -Prefix $UniquePrefix -Suffix $PrimarySuffix -VNetId 1 -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword -SkipSqlDatabase $False
        Write-Host "Deploying services to secondary region..."
        $SecondaryOutputsRegion = New-RegionDeployment -Location $SecondaryLocation -Prefix $UniquePrefix -Suffix $SecondarySuffix -VNetId 2 -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword -SkipSqlDatabase $True
        Write-Host "Deploying SQL Failover group..."
        $PrimaryOutputsSqlFailoverGroup = New-SqlFailoverGroupDeployment -Location $PrimaryLocation -Prefix $UniquePrefix -Suffix $PrimarySuffix -PrimarySqlServerName $PrimaryOutputsRegion.Outputs['sqlServerName'].value -SecondarySqlServerResourceId $SecondaryOutputsRegion.Outputs['sqlResourceId'].value -SqlDatabaseName $PrimaryOutputsRegion.Outputs['sqlDatabaseName'].value

        # Deploy the additional private endpoints cross-region.
        Write-Host "Deploying cross-region private endpoints..."
        $PrimaryOutputsPrivateEndpoint = New-RemotePrivateEndpointDeployment -Location $PrimaryLocation -Prefix $UniquePrefix -Suffix $PrimarySuffix -RemoteSuffix $SecondarySuffix -SubnetResourceId $PrimaryOutputsRegion.Outputs['sqlSubnetResourceId'].value -SqlResourceId $SecondaryOutputsRegion.Outputs['sqlResourceId'].value
        $SecondaryOutputsPrivateEndpoint = New-RemotePrivateEndpointDeployment -Location $SecondaryLocation -Prefix $UniquePrefix -Suffix $SecondarySuffix -RemoteSuffix $PrimarySuffix -SubnetResourceId $SecondaryOutputsRegion.Outputs['sqlSubnetResourceId'].value -SqlResourceId $PrimaryOutputsRegion.Outputs['sqlResourceId'].value

        # The Private Endpoint NIC information cannot be referenced directly from within the previous ARM template, so we deploy
        # the DNS records as a separate step (as an alternative to using nested templates).
        # See https://www.huuhka.net/automating-azure-private-link-storage-private-endpoints/ for details on the challenges.
        Write-Host "Deploying cross-region DNS records..."
        $PrimaryOutputsDnsRecord = New-RemoteDnsRecordDeployment -Suffix $PrimarySuffix -HostName $SecondaryOutputsRegion.Outputs['sqlServerName'].value -PrivateEndpointNicResourceId $PrimaryOutputsPrivateEndpoint.Outputs['privateEndpointNicResourceId'].value
        $SecondaryOutputsDnsRecord = New-RemoteDnsRecordDeployment -Suffix $SecondarySuffix -HostName $PrimaryOutputsRegion.Outputs['sqlServerName'].value -PrivateEndpointNicResourceId $SecondaryOutputsPrivateEndpoint.Outputs['privateEndpointNicResourceId'].value
        break
    }
}
