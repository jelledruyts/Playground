function New-RegionDeployment {
    param (
        $ResourceGroupName, $Location, $UniquePrefix, $ResourceSuffix = "", $VNetId = 1, `
        $SqlAdministratorLoginName, [SecureString]$SqlAdministratorLoginPassword, $SkipSqlDatabase = $False
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "deploy-privateendpoint-region.json" `
        -location $Location `
        -uniquePrefix $UniquePrefix `
        -resourceSuffix $ResourceSuffix `
        -vnetId $VNetId `
        -sqlAdministratorLoginName $SqlAdministratorLoginName `
        -sqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
        -skipSqlDatabase $SkipSqlDatabase
}

function New-RemotePrivateEndpointDeployment {
    param (
        $ResourceGroupName, $UniquePrefix, $RemoteSuffix, $SubnetResourceId, $SqlResourceId
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "deploy-privateendpoint-remote-privateendpoint.json" `
        -uniquePrefix $UniquePrefix `
        -remoteSuffix $RemoteSuffix `
        -subnetResourceId $SubnetResourceId `
        -sqlResourceId $SqlResourceId
}

function New-RemoteDnsRecordDeployment {
    param (
        $ResourceGroupName, $HostName, $PrivateEndpointNicResourceId
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "deploy-privateendpoint-remote-dnsrecord.json" `
        -hostName $HostName `
        -privateEndpointNicResourceId $PrivateEndpointNicResourceId
}

function New-SqlFailoverGroupDeployment {
    param (
        $ResourceGroupName, $UniquePrefix, $PrimarySqlServerName, $SecondarySqlServerResourceId, $SqlDatabaseName
    )
    New-AzResourceGroupDeployment `
        -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
        -ResourceGroupName $ResourceGroupName `
        -TemplateFile "deploy-privateendpoint-sql-failovergroup.json" `
        -uniquePrefix $UniquePrefix `
        -sqlServerPrimaryName $PrimarySqlServerName `
        -sqlServerSecondaryResourceId $SecondarySqlServerResourceId `
        -sqlDatabaseName $SqlDatabaseName
}

$ErrorActionPreference = "Stop" # Break on errors

$SubscriptionName = "Azure CXP FTA Internal Subscription JELLED"
$UniquePrefix = "jelled"
$PrimaryLocation = "westeurope"
$PrimarySuffix = "-primary"
$SecondaryLocation = "northcentralus"
$SecondarySuffix = "-secondary"
$SqlAdministratorLoginName = "sqladmin"
$SqlAdministratorLoginPassword = Read-Host "Enter the password for the SQL administrator" -AsSecureString

if ($(Get-AzContext).Subscription.Name -ne $SubscriptionName) {
    Connect-AzAccount
    Set-AzContext $SubscriptionName
}

$Choice = Read-Host -Prompt "Enter 'S' to deploy using Service Endpoints or 'P' to use Private Endpoints"
switch ($Choice) {
    "S" {
        Write-Host "Deploying services..."
        $ResourceGroupName = "$UniquePrefix-appsvc-sql-serviceendpoint"
        $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $PrimaryLocation -Verbose -Force
        $Outputs = New-AzResourceGroupDeployment `
            -Mode Incremental -DeploymentDebugLogLevel All -Force -Verbose `
            -ResourceGroupName $ResourceGroupName `
            -TemplateFile "deploy-serviceendpoint.json" `
            -uniquePrefix $UniquePrefix `
            -sqlAdministratorLoginName $SqlAdministratorLoginName `
            -sqlAdministratorLoginPassword $SqlAdministratorLoginPassword
        break
    }
    "P" {
        $Choice = Read-Host -Prompt "Enter 'S' to deploy to a Single region, 'P' to deploy to Peered regions, 'U' to deploy to Unpaired regions"
        switch ($Choice) {
            "S" {
                Write-Host "Deploying services..."
                $ResourceGroupName = "$UniquePrefix-appsvc-sql-privateendpoint"
                $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $PrimaryLocation -Verbose -Force
                $OutputsRegion = New-RegionDeployment `
                    -ResourceGroupName $ResourceGroupName -Location $PrimaryLocation -UniquePrefix $UniquePrefix `
                    -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
                    -SkipSqlDatabase $True
                break
            }
            "U" {
                # Deploy the regional services.
                # Note that the primary and secondary deployments must each have their own Resource Group as the
                # DNS Private Zone must be unique within the Resource Group (and each region needs its own different copy).
                Write-Host "Deploying services to primary region..."
                $PrimaryResourceGroupName = "$UniquePrefix-appsvc-sql-privateendpoint$PrimarySuffix"
                $PrimaryResourceGroup = New-AzResourceGroup -Name $PrimaryResourceGroupName -Location $PrimaryLocation -Verbose -Force
                $PrimaryOutputsRegion = New-RegionDeployment `
                    -ResourceGroupName $PrimaryResourceGroupName -Location $PrimaryLocation `
                    -UniquePrefix $UniquePrefix -ResourceSuffix $PrimarySuffix -VNetId 1 `
                    -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
                    -SkipSqlDatabase $False

                Write-Host "Deploying services to secondary region..."
                $SecondaryResourceGroupName = "$UniquePrefix-appsvc-sql-privateendpoint$SecondarySuffix"
                $SecondaryResourceGroup = New-AzResourceGroup -Name $SecondaryResourceGroupName -Location $SecondaryLocation -Verbose -Force
                $SecondaryOutputsRegion = New-RegionDeployment `
                    -ResourceGroupName $SecondaryResourceGroupName -Location $SecondaryLocation `
                    -UniquePrefix $UniquePrefix -ResourceSuffix $SecondarySuffix -VNetId 2 `
                    -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
                    -SkipSqlDatabase $True

                Write-Host "Deploying SQL Failover Group..."
                $PrimaryOutputsSqlFailoverGroup = New-SqlFailoverGroupDeployment `
                    -ResourceGroupName $PrimaryResourceGroupName -UniquePrefix $UniquePrefix `
                    -PrimarySqlServerName $PrimaryOutputsRegion.Outputs['sqlServerName'].value `
                    -SecondarySqlServerResourceId $SecondaryOutputsRegion.Outputs['sqlResourceId'].value `
                    -SqlDatabaseName $PrimaryOutputsRegion.Outputs['sqlDatabaseName'].value
        
                # Deploy the additional private endpoints cross-region.
                Write-Host "Deploying cross-region private endpoints..."
                $PrimaryOutputsPrivateEndpoint = New-RemotePrivateEndpointDeployment `
                    -ResourceGroupName $PrimaryResourceGroupName -UniquePrefix $UniquePrefix -RemoteSuffix $SecondarySuffix `
                    -SubnetResourceId $PrimaryOutputsRegion.Outputs['sqlSubnetResourceId'].value `
                    -SqlResourceId $SecondaryOutputsRegion.Outputs['sqlResourceId'].value
                $SecondaryOutputsPrivateEndpoint = New-RemotePrivateEndpointDeployment `
                    -ResourceGroupName $SecondaryResourceGroupName -UniquePrefix $UniquePrefix -RemoteSuffix $PrimarySuffix `
                    -SubnetResourceId $SecondaryOutputsRegion.Outputs['sqlSubnetResourceId'].value `
                    -SqlResourceId $PrimaryOutputsRegion.Outputs['sqlResourceId'].value
        
                # The Private Endpoint NIC information cannot be referenced directly from within the previous ARM template, so we deploy
                # the DNS records as a separate step (as an alternative to using nested templates).
                # See https://www.huuhka.net/automating-azure-private-link-storage-private-endpoints/ for details on the challenges.
                Write-Host "Deploying cross-region DNS records..."
                $PrimaryOutputsDnsRecord = New-RemoteDnsRecordDeployment `
                    -ResourceGroupName $PrimaryResourceGroupName `
                    -HostName $SecondaryOutputsRegion.Outputs['sqlServerName'].value `
                    -PrivateEndpointNicResourceId $PrimaryOutputsPrivateEndpoint.Outputs['privateEndpointNicResourceId'].value
                $SecondaryOutputsDnsRecord = New-RemoteDnsRecordDeployment `
                    -ResourceGroupName $SecondaryResourceGroupName `
                    -HostName $PrimaryOutputsRegion.Outputs['sqlServerName'].value `
                    -PrivateEndpointNicResourceId $SecondaryOutputsPrivateEndpoint.Outputs['privateEndpointNicResourceId'].value
                break
            }
            "P" {
                Write-Host "Deploying services to primary region..."
                $ResourceGroupName = "$UniquePrefix-appsvc-sql-privateendpoint"
                $ResourceGroup = New-AzResourceGroup -Name $ResourceGroupName -Location $PrimaryLocation -Verbose -Force
                $PrimaryOutputsRegion = New-RegionDeployment `
                    -ResourceGroupName $ResourceGroupName -Location $PrimaryLocation `
                    -UniquePrefix $UniquePrefix -ResourceSuffix $PrimarySuffix -VNetId 1 `
                    -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
                    -SkipSqlDatabase $False

                Write-Host "Deploying services to secondary region..."
                $SecondaryOutputsRegion = New-RegionDeployment `
                    -ResourceGroupName $ResourceGroupName -Location $SecondaryLocation `
                    -UniquePrefix $UniquePrefix -ResourceSuffix $SecondarySuffix -VNetId 2 `
                    -SqlAdministratorLoginName $SqlAdministratorLoginName -SqlAdministratorLoginPassword $SqlAdministratorLoginPassword `
                    -SkipSqlDatabase $True

                Write-Host "Peering VNets..."
                $PrimaryVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $PrimaryOutputsRegion.Outputs['vnetName'].value
                $SecondaryVNet = Get-AzVirtualNetwork -ResourceGroupName $ResourceGroupName -Name $SecondaryOutputsRegion.Outputs['vnetName'].value
                $PrimaryVNetPeering = Add-AzVirtualNetworkPeering `
                    -Name "Peering-Primary-Secondary" `
                    -VirtualNetwork $PrimaryVNet `
                    -RemoteVirtualNetworkId $SecondaryVNet.Id
                $SecondaryVNetPeering = Add-AzVirtualNetworkPeering `
                    -Name "Peering-Secondary-Primary" `
                    -VirtualNetwork $SecondaryVNet `
                    -RemoteVirtualNetworkId $PrimaryVNet.Id
    
                Write-Host "Deploying SQL Failover Group..."
                $PrimaryOutputsSqlFailoverGroup = New-SqlFailoverGroupDeployment `
                    -ResourceGroupName $ResourceGroupName -UniquePrefix $UniquePrefix `
                    -PrimarySqlServerName $PrimaryOutputsRegion.Outputs['sqlServerName'].value `
                    -SecondarySqlServerResourceId $SecondaryOutputsRegion.Outputs['sqlResourceId'].value `
                    -SqlDatabaseName $PrimaryOutputsRegion.Outputs['sqlDatabaseName'].value
                break
            }
        }
        break
    }
}
