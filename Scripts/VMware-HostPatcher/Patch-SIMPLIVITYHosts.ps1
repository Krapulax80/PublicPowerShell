function Patch-SIMPLIVITYHosts {
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
      Author:         Mike Ward & Fabrice Semti
      Creation Date:  26/08/2020
      Purpose/Change: Initial function development
    .EXAMPLE
  
      . "\\tsclient\C\Users\fabrice.semti\OneDrive - Westcoast Limited\Desktop\PublicPowerShell\Scripts\VMware-HostPatcher\Patch-SIMPLIVITYHosts.ps1"
  
      Patch-SIMPLIVITYHosts
   
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
  
        #   # List of hosts
        #   $listofhosts = Get-Content  "$currentPath/config/hostlist.txt"
  
        #   # List of VM-s to leave online
        #   $listofhosts = Get-Content  "$currentPath/config/VMexceptions.txt"   
          
          # Connect to the VI server
          connect-viserver $config.VIserver

          # Cluster list
          $clusterlist  = Get-Content "$currentPath/config/clusters.txt" 
            
      }
      
      process {
        
        #Let's process each cluster at a time
        write-host "Let's start to remediate our Simplivity clusters"
        Foreach ($clustername in $clusterlist){

            #Get list of hosts in specified cluster
            $clusterhosts=get-cluster -name $clustername |Get-VMHost
            $clusterhostcount = $clusterhosts.count
            write-host "I have $clusterhostcount hosts in the $clustername cluster to work with"

            # Loop through each host
            Foreach ($currentclusterhost in $clusterhosts){

                # Let's check compliance for first host in cluster
                write-host "Checking host: $currentclusterhost"
                Foreach ($currentclusterhostcomp in (get-compliance -entity $currentclusterhost)){

                    #If host is compliant for a baseline let's output this
                    write-host "Let's check the host $currentclusterhost, is it compliant for all baselines?"
                    If ($currentclusterhostcomp.status -eq "Compliant"){
                    Write-Host "The host $currentclusterhost is compliant for the "$currentclusterhostcomp.Baseline.Name" Baseline, checking the next one"
                    }
                    #For baselines not compliant on the host let's start remediation
                    else{

                        Write-Host "The host $currentclusterhost is not compliant for the "$currentclusterhostcomp.Baseline.name" Baseline, attempting to remediate this baseline"

                        #First we need to disable HA in the cluster
                        write-host "Disabling HA on the $clustername cluster, this will let us remediate the host"
                        set-cluster -cluster $clustername -HAEnabled:$false -Confirm:$false | out-null

                        #Let's find and shut down the OVC safely from the current host
                        get-vmhost -Name $currentclusterhost.name | Get-VM | where-object { $_.Name -like "OmniStack*"} | Shutdown-VMGuest -Confirm:$false
                        Write-Host "Let's find and shut down the OVC safely from the current host"
                        write-host "Waiting 2 minutes for OVC to cleanly shut down"
                        start-sleep -seconds 120

                        # Put the host into maintenance mode then wait 30 seconds
                        write-host "Put the host into maintenance mode then wait 30 seconds"
                        Get-VMHost -Name $currentclusterhost | set-vmhost -State Maintenance | out-null
                        start-sleep -seconds 30

                        # Check baselines and update
                        write-host "Let's fetch all baseines for $currentclusterhost, then we will apply them to the host"
                        get-baseline -name $currenthostbaseline.baseline.name | update-entity -entity $currentclusterhost -confirm:$false

                        #Bring the host back online now it's remediated
                        write-host "Removing $currentclusterhost from Maintenance Mode"
                        Get-VMHost -Name $currentclusterhost | set-vmhost -State Connected | out-null

                        #Now let's power up the OVC for this host
                        write-host "Powering up the OVC for the host"
                        get-vmhost -Name $currentclusterhost.name | Get-VM | where-object { $_.Name -like "OmniStack*"} | Start-VM
                        Write-Host "Let's wait 5 minutes before starting the next host to give enough time for the OVC to boot up and sync custer storage."
                        start-sleep -seconds 300

                        write-host "$currentclusterhost has been remediated"
                    }
                }
            }

            write-host "Re-enabling HA on the $clustername cluster"
            set-cluster -cluster $clustername -HAEnabled:$true -Confirm:$false
        }
        
      }
      
      end {
        disconnect-viserver -confirm:$false
      }
  }
  