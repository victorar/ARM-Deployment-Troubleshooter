[CmdletBinding()]
Param(
    [String]
    [Parameter(Mandatory = $true)]
    $AadTenantId,

    [String]
    [Parameter(Mandatory = $true)]
    $ResourceGroupName
)

Import-Module AzureRM.Resources

function Logon($aad)
{
    Add-AzureRmEnvironment -Name 'Azure Stack' `
        -ActiveDirectoryEndpoint ("https://login.windows.net/$aad/") `
        -ActiveDirectoryServiceEndpointResourceId "https://azurestack.local-api/"`
        -ResourceManagerEndpoint ("https://api.azurestack.local/") `
        -GalleryEndpoint ("https://gallery.azurestack.local/") `
        -GraphEndpoint "https://graph.windows.net/" | Out-Null   

    Login-AzureRmAccount -EnvironmentName 'Azure Stack' | Out-Null
}

function logheader ($heading, $filepath)
{
    Write-Output $('=' * ($heading.length)) | Out-File -FilePath $filepath -Append
    Write-Output $heading | Out-File -FilePath $filepath -Append
    Write-Output $('=' * ($heading.length)) | Out-File -FilePath $filepath -Append
}

Logon ($AadTenantId)
 
$resourceGroup = Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
if ($resourceGroup -eq $null)
{
    Write-Host -ForegroundColor Red "Resource Group $ResourceGroupName not found"
    Exit
}
Write-Host -ForegroundColor Green "Resource Group $ResourceGroupName found OK"

$deployments = Get-AzureRmResourceGroupDeployment -ResourceGroupName $ResourceGroupName
Write-Host -ForegroundColor Green "Found" $deployments.Count "deployments in resource group $resourceGroupName"

$deployments | ft -Property DeploymentName,ProvisioningState,Mode,Timestamp 
$faileddeployments = $deployments #| where {$_.ProvisioningState -ne 'Succeeded'}
if ($faileddeployments.Count -ge 1)
{
    Write-Host -ForegroundColor Green 'Logging failed deploymnets'
    foreach ($deployment in $faileddeployments)
    {
        #set up a log file
        $name = $deployment.DeploymentName
        $logfile="$ResourceGroupName-$name.log"
        Remove-Item $logfile -Confirm -ErrorAction SilentlyContinue

        #write a header
        logheader "Deployment details for deployment $name" $logfile

        #Template link if available - not available if deployed via portal
        Write-Host -ForegroundColor Green Getting deploymjent informaion for deployment $deployment.DeploymentName
        if ($deployment.TemplateLink -ne $null)
        {
            logheader "Template Link Information" $logfile 
            $deployment.TemplateLink | ConvertTo-Json | Out-File -FilePath $logfile -Append
        } 

        #Deploymnet parameters
        logheader "Depployment Paramaters" $logfile 
        $deployment.Parameters | ConvertTo-Json | Out-File -FilePath $logfile -Append
        
        #Deployment out puts if any
        if ($deployment.Outputs -ne $null)
        {
            logheader "Deployment Outputs" $logfile
            $deployment.OutputsString | Out-File -FilePath $logfile -Append
        } 

        #deployment operations
        $operations = Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $deployment.DeploymentName -ResourceGroupName $ResourceGroupName
        Write-Host -ForegroundColor Green "Getting deploymnet operations for deploymnet" $deployment.DeploymentName
        logheader "Deployment Operations" $logfile 
        $operations | ConvertTo-Json | Out-File -FilePath $logfile -Append

        #All resources in the group
        Write-Host -ForegroundColor Green "Getting Additional information all resources in $ResourceGroupName"
        logheader "Resources in group $ResourceGroupName" $logfile
        $resources = Get-AzureRmResource | where {$_.ResourceGroupName -eq $ResourceGroupName}
        foreach ($resource in $resources)
        {
            $resource |Out-File -FilePath $logfile -Append
            Get-AzureRmResource -ResourceId $resource.ResourceId | convertto-json | Out-File -FilePath $logfile -Append
        }

        #Additional information for VMs and Extensions
        Write-Host -ForegroundColor Green "Getting Additional information for any VM resources"
        foreach ($vmop in $operations | where {$_.Properties.TargetResource.ResourceType -eq 'Microsoft.Compute/virtualMachines'})
        {
            Write-Host -ForegroundColor Green "Getting details for vm" $vmstatus.Name 
            $vmstatus = Get-AzureRmVM -Status -ResourceGroupName $ResourceGroupName -Name $vmop.Properties.TargetResource.ResourceName 
            logheader ("VM status for VM" + $vmstatus.Name) $logfile
            $vmstatus.StatusText| Out-File -FilePath $logfile -Append

            Write-Host -ForegroundColor Green "Getting VM Agent Status for VM" $vmstatus.Name
            logheader ("VM Agent status for VM" + $vmstatus.Name) $logfile
            $vmstatus.VMAgentText | Out-File -FilePath $logfile -Append

            Write-Host -ForegroundColor Green "Getting Installed Agent Extensions for VM" $vmstatus.Name
            logheader ("Installed Extensions for VM" + $vmstatus.Name) $logfile
            $vmstatus.ExtensionsText | Out-File -FilePath $logfile -Append
        }
    }
}

