function Update-HostBaseline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]$esxhost ,
        [Parameter(Mandatory)]$hostbasecomp
    )  

    Write-Host "The host $esxhost is not compliant for the "$hostbasecomp.Baseline.name" Baseline, attempting to remediate this baseline!"
    Write-Host “====================================================================” 

    # ... Remediate selected host for baseline ...
    write-host "Deploying "$hostbasecomp.Baseline.name" Baseline"
    Get-baseline -name $hostbasecomp.Baseline.name | update-entity -entity $currentesxhost -confirm:$false   
}