$labName = "DscWorkshop_$((1..6 | ForEach-Object { [char[]](97..122) | Get-Random }) -join '')"
$azureLocation = 'West Europe'

#region Lab setup
#--------------------------------------------------------------------------------------------------------------------
#----------------------- CHANGING ANYTHING BEYOND THIS LINE SHOULD NOT BE REQUIRED ----------------------------------
#----------------------- + EXCEPT FOR THE LINES STARTING WITH: REMOVE THE COMMENT TO --------------------------------
#----------------------- + EXCEPT FOR THE LINES CONTAINING A PATH TO AN ISO OR APP   --------------------------------
#--------------------------------------------------------------------------------------------------------------------

#create an empty lab template and define where the lab XML files and the VMs will be stored
New-LabDefinition -Name $labName -DefaultVirtualizationEngine Azure
Add-LabAzureSubscription -DefaultLocationName $azureLocation

#make the network definition
Add-LabVirtualNetworkDefinition -Name $labName -AddressSpace 192.168.111.0/24

#and the domain definition with the domain admin account
Add-LabDomainDefinition -Name contoso.com -AdminUser Install -AdminPassword Somepass1!

#these credentials are used for connecting to the machines. As this is a lab we use clear-text passwords
Set-LabInstallationCredential -Username Install -Password Somepass1!

# Add the reference to our necessary ISO files
Add-LabIsoImageDefinition -Name AzDevOps -Path $labSources\ISOs\mu_azure_devops_server_2019_update_1.1_x64_dvd_962550d1.iso #from https://visualstudio.microsoft.com/downloads/

#defining default parameter values, as these ones are the same for all the machines
$PSDefaultParameterValues = @{
    'Add-LabMachineDefinition:Network'         = $labName
    'Add-LabMachineDefinition:ToolsPath'       = "$labSources\Tools"
    'Add-LabMachineDefinition:DomainName'      = 'contoso.com'
    'Add-LabMachineDefinition:DnsServer1'      = '192.168.111.10'
    'Add-LabMachineDefinition:OperatingSystem' = 'Windows Server 2016 Datacenter (Desktop Experience)'
}

#The PostInstallationActivity is just creating some users
$postInstallActivity = @()
$postInstallActivity += Get-LabPostInstallationActivity -ScriptFileName 'New-ADLabAccounts 2.0.ps1' -DependencyFolder $labSources\PostInstallationActivities\PrepareFirstChildDomain
$postInstallActivity += Get-LabPostInstallationActivity -ScriptFileName PrepareRootDomain.ps1 -DependencyFolder $labSources\PostInstallationActivities\PrepareRootDomain
Add-LabMachineDefinition -Name DSCDC01 -Memory 1GB -Roles RootDC -IpAddress 192.168.111.10 -PostInstallationActivity $postInstallActivity

# SQL and PKI
Add-LabMachineDefinition -Name DSCCASQL01 -Memory 3GB -Roles CaRoot, SQLServer2017

# DSC Pull Server with SQL server backing, TFS Build Worker
$roles = @(
    Get-LabMachineRoleDefinition -Role DSCPullServer -Properties @{
        DoNotPushLocalModules = 'true'
        DatabaseEngine        = 'sql'
        SqlServer             = 'DSCCASQL01'
        DatabaseName          = 'DSC'
    }
    Get-LabMachineRoleDefinition -Role TfsBuildWorker -Properties @{ NumberOfBuildWorkers = '4' }
    Get-LabMachineRoleDefinition -Role WebServer
)
Add-LabMachineDefinition -Name DSCPULL01 -Memory 4GB -Roles $roles -IpAddress 192.168.111.60 -OperatingSystem 'Windows Server 2019 Datacenter (Desktop Experience)'

# Build Server
Add-LabMachineDefinition -Name DSCDO01 -Memory 4GB -Roles AzDevOps -IpAddress 192.168.111.70

#Hyper-V Host
$roles = @(
    Get-LabMachineRoleDefinition -Role TfsBuildWorker -Properties @{ NumberOfBuildWorkers = '4' }
    Get-LabMachineRoleDefinition -Role HyperV
)
Add-LabMachineDefinition -Name DSCHost01 -Memory 8GB -Roles $roles -IpAddress 192.168.111.80

# DSC target nodes - our legacy VMs with an existing configuration
Add-LabMachineDefinition -Name DSCFile01 -Memory 1GB -Roles FileServer -IpAddress 192.168.111.100
Add-LabMachineDefinition -Name DSCWeb01 -Memory 1GB -Roles WebServer -IpAddress 192.168.111.101

# Servers in Test
Add-LabMachineDefinition -Name DSCFile02 -Memory 1GB -Roles FileServer -IpAddress 192.168.111.110
Add-LabMachineDefinition -Name DSCWeb02 -Memory 1GB -Roles WebServer -IpAddress 192.168.111.111

# Servers in Prod
Add-LabMachineDefinition -Name DSCFile03 -Memory 1GB -Roles FileServer -IpAddress 192.168.111.120
Add-LabMachineDefinition -Name DSCWeb03 -Memory 1GB -Roles WebServer -IpAddress 192.168.111.121

Install-Lab

Enable-LabCertificateAutoenrollment -Computer -User
Install-LabWindowsFeature -ComputerName (Get-LabVM -Role DSCPullServer, FileServer, WebServer, AzDevOps) -FeatureName RSAT-AD-Tools
Install-LabSoftwarePackage -Path $labsources\SoftwarePackages\Notepad++.exe -CommandLine /S -ComputerName (Get-LabVM)

# in case you screw something up
Write-Host "1. - Creating Snapshot 'AfterInstall'" -ForegroundColor Magenta
Checkpoint-LabVM -All -SnapshotName AfterInstall
#endregion

Show-LabDeploymentSummary -Detailed