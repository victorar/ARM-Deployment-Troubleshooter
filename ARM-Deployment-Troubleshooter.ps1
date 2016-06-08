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

#Logon ($AadTenantId)
 
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
$faileddeployments = $deployments | where {$_.ProvisioningState -ne 'Succeeded'}
if ($faileddeployments.Count -ge 1)
{
    Write-Host -ForegroundColor Green 'Logging failed deploymnets'
    foreach ($deployment in $faileddeployments)
    {
        $name = $deployment.DeploymentName
        $logfile="$ResourceGroupName-$name.log"
        Remove-Item $logfile -Confirm -ErrorAction SilentlyContinue

        logheader "Deployment details for deployment $name" $logfile

        Write-Host -ForegroundColor Green Getting deploymjent informaion for deployment $deployment.DeploymentName
        if ($deployment.TemplateLink -ne $null)
        {
            logheader "Template Link Information" $logfile 
            $deployment.TemplateLinkString | Out-File -FilePath $logfile -Append
        } 
        logheader "Depployment Paramaters" $logfile 
        $deployment.ParametersString | Out-File -FilePath $logfile -Append
        if ($deployment.TemplateLink -ne $null)
        {
            logheader "Deployment Outputs" $logfile
            $deployment.OutputsString | Out-File -FilePath $logfile -Append
        } 
        $operations = Get-AzureRmResourceGroupDeploymentOperation -DeploymentName $deployment.DeploymentName -ResourceGroupName $ResourceGroupName
        Write-Host -ForegroundColor Green "Getting deploymnet operations for deploymnet" $deployment.DeploymentName
        logheader "Deployment Operations" $logfile 
        "{0,-40} {1,-60} {2,12}" -f "Resource Name","Resource Type", "Provisioning State" | Out-File -FilePath $logfile -Append
        foreach ($operation in $operations)
        {
             "{0,-40} {1,-60} {2,12}" -f $operation.Properties.TargetResource.ResourceName,$operation.Properties.TargetResource.ResourceType, $operation.Properties.ProvisioningState | Out-File -FilePath $logfile -Append
             if ($operation.Properties.ProvisioningState -ne 'Succeeded')
             {               
                $operation.Properties.StatusMessage.Error  | Out-File -FilePath $logfile -Append
             }
        }

        $resources = Get-AzureRmResource | where {$_.ResourceGroupName -eq $ResourceGroupName}
        Write-Host -ForegroundColor Green "Getting Additional information for any VM resources"
        foreach ($vmop in $operations | where {$_.Properties.TargetResource.ResourceType -eq 'Microsoft.Compute/virtualMachines'})
        {
            Write-Host -ForegroundColor Green "Getting details for vm" $vmstatus.Name 
            $vmstatus = Get-AzureRmVM -Status -ResourceGroupName $ResourceGroupName -Name $vmop.Properties.TargetResource.ResourceName 
            logheader ("VM status for VM" + $vmstatus.Name) $logfile
            $vmstatus.Statuses | ft -Property Level, Code, DisplayStatus | Out-File -FilePath $logfile -Append

            Write-Host -ForegroundColor Green "Getting VM Agent Status for VM" $vmstatus.Name
            logheader ("VM Agent status for VM" + $vmstatus.Name) $logfile
            $vmstatus.VMAgent.Statuses | ft -Property Level, Code, DisplayStatus | Out-File -FilePath $logfile -Append

            Write-Host -ForegroundColor Green "Getting Installed Agent Extension Handlers for VM" $vmstatus.Name
            logheader ("Installed Extension Handlers for VM" + $vmstatus.Name) $logfile
            $vmstatus.VMAgent.ExtensionHandlers | ft -Property Type, TypeHandlerVersion | Out-File -FilePath $logfile -Append

            Write-Host -ForegroundColor Green "Getting Installed Agent Extensions for VM" $vmstatus.Name
            logheader ("Installed Extensions for VM" + $vmstatus.Name) $logfile
            $vmstatus.Extensions | ft -Property Name, Type, TypeHandlerVersion | Out-File -FilePath $logfile -Append

            foreach ($extension in $vmstatus.Extensions)
            {
                Write-Host -ForegroundColor Green Logging Status for extension $extension.Name of type $extension.Type in VM $vmstatus.Name
                logheader ("Status for extension "+$extension.Name +" of type "+$extension.Type + " in VM"+ $vmstatus.Name)  $logfile
                $extension.Statuses | ft -Property Level, Code, DisplayStatus, message | Out-File -FilePath $logfile -Append

                Write-Host -ForegroundColor Green Logging Sub-Status for extension $extension.Name of type $extension.Type in VM $vmstatus.Name
                foreach ($substatus in $extension.Substatuses)
                {
                    logheader ("Sub-Status for extension "+$extension.Name +" of type "+$extension.Type + " in VM"+ $vmstatus.Name)  $logfile
                    $substatus | ft -Property Level, Code, DisplayStatus | Out-File -FilePath $logfile -Append
                    $substatus.Message | Out-File -FilePath $logfile -Append
                }
            }
        }
    }
}

