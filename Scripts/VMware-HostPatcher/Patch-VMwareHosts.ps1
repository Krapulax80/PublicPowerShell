function Patch-VMwareHosts {
  <#
  .SYNOPSIS
    Patching VMware hosts 
  .DESCRIPTION

  .PARAMETER Menu
    
  .INPUTS
    The script needs to have this structure:
    - "config" folder in the same folder as the script
    - "config.csv", "hostlist.txt" and "VMexceptionlist.txt" in the config folder (these are excluded from GitHub)
  .OUTPUTS
 
  .NOTES
    Version:        0.1
    Author:         Fabrice Semti
    Creation Date:  26/08/2020
    Purpose/Change: Initial function development
  .EXAMPLE

    . "\\tsclient\C\Users\fabrice.semti\OneDrive - Westcoast Limited\Desktop\PublicPowerShell\Scripts\VMware-HostPatcher\Patch-VMwareHosts.ps1"

    Patch-VMwareHosts
 
#>    
    [CmdletBinding()]
    param (
          
    )
    
    begin {

        $ErrorActionPreference = "Stop"
        
        $CurrentPath = $config =  $null
        $CurrentPath = Split-Path -Parent $PSCommandPath

        # Import config file        
        $config = Import-Csv "$currentPath/config/config.csv"

        # List of hosts
        $listofhosts = Get-Content  "$currentPath/config/hostlist.txt"

        # List of VM-s to leave online
        $listofhosts = Get-Content  "$currentPath/config/VMexceptions.txt"   
        
        # Connect to the VI server
        connect-viserver $config.VIserver
          
    }
    
    process {

        # Process each host in the list
        Foreach ($esxhost in $listofhosts){

            $currentesxhost = get-vmhost $esxhost
            Write-Host “Processing $currentesxhost”
            Write-Host “====================================================================”

            Foreach ($hostbasecomp in (get-compliance -entity $esxhost)){

                # Check host complience ...
                If ($hostbasecomp.status -eq "Compliant"){
                Write-Host "The host $esxhost is compliant for the "$hostbasecomp.Baseline.name" Baseline, skipping to next Baseline"
                }
                #...if not compliant, attempt to remediate
                else{

                    Write-Host "The host $esxhost is not compliant for the "$hostbasecomp.Baseline.name" Baseline, attempting to remediate this baseline"

                    # Shut down all the VM-s on the host first ...
                    Foreach ($VM in ($currentesxhost | Get-VM | where { $_.PowerState -eq “PoweredOn” })){

                        Write-Host “====================================================================”
                        Write-Host “Processing $vm”

                        # ... except if the VM is on the exception list
                        if ($vmstoleave -contains $vm){

                        Write-Host “I am $vm – I will go down with the ship”

                        }
                        # ...before the shutdown, ensure VMware tools available ...
                        else{

                            Write-Host “Checking VMware Tools….”
                            $vminfo = get-view -Id $vm.ID

                            # ... if the VM had no VMware tools installed, do a hard power off
                            if ($vminfo.config.Tools.ToolsVersion -eq 0){
                                Write-Host “$vm doesn’t have vmware tools installed, hard power this one”
                                # Hard Power Off
                                Stop-VM $vm -confirm:$false
                            # ... but normally do a graceful shutdown of the VM
                            }else{
                                write-host “I will attempt to shutdown $vm”
                                # Power off gracefully
                                $vmshutdown = $vm | shutdown-VMGuest -Confirm:$false
                            }
                        }
                    }

                    # Put the host into maintenace mode ...
                    Write-Host "Placing $esxhost into maintenance mode"
                    Get-VMHost -Name $esxhost | set-vmhost -State Maintenance 
                    
                    # Wait for the VM shutdowns to complete.
                    Write-Host "Let's have a brew while the VMs shut down"
                    Start-sleep -seconds 60                    

                    # ... Remediate selected host for baseline ...
                    write-host "Deploying "$hostbasecomp.Baseline.name" Baseline"
                    get-baseline -name $hostbasecomp.Baseline.name | update-entity -entity $currentesxhost -confirm:$false

                    # ... Take the host out of maintenace mode ...
                    write-host "Removing host from Maintenance Mode"
                    Get-VMHost -Name $currentesxhost | set-vmhost -State Connected

                    # Restart the VM-s on the host ...
                    $startupvmlist = get-vmhost -name $currentesxhost | get-vm | Get-VMStartPolicy | Where-Object {$_.StartAction -eq "PowerOn"}
                    foreach ($vmtopoweron in $startupvmlist.VM) {
                        write-host "Powering on $vmtopoweron"
                        start-vm -VM $vmtopoweron
                    }

                    # ... and wait for the VM-s to come online
                    Write-Host "Let's wait 5 minutes before starting the next host to give enough time for VMs to boot up."
                    start-sleep -seconds 300
                }
            }
        }

    }
    
    end {
        disconnect-viserver -confirm:$false
    }
}
