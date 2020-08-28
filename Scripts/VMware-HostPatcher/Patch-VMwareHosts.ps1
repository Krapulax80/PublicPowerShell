
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

    . "\\tsclient\C\Users\fabrice.semti\OneDrive - Westcoast Limited\Desktop\PublicPowerShell\Scripts\VMware-HostPatcher\Patch-VMwareHosts.ps1"

    Patch-VMwareHosts

    or

    Patch-VMwareHosts -Live:$True

    # if "-Live" is  not set, the script will use the contents of the hostlist.txt file; this is for test purposes
 
#>    
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)][switch]$Live          
    )
    
    begin {



        $ErrorActionPreference = "Stop"
        
        $CurrentPath = $config =  $null
        $CurrentPath = Split-Path -Parent $PSCommandPath

        # Logs
        $date = Get-date -Format yyyy-MM-dd
        $logfile = $CurrentPath + "\" + "logs" + "\" + $date + "_actions.log"
        Start-Transcript $logfile -Force

        $date = Get-date -Format yyyy-MM-dd
        $logfile = $CurrentPath + "\" + "logs" + "\" + $date + "_error.log"
        $Error.clear()
        
        # Import config file        
        $config = Import-Csv "$currentPath/config/config.csv"

        # List of VM-s to leave online
        $vmstoleave = Get-Content "$currentPath/config/VMexceptions.txt"  
        
        # Connect to the VI server
        connect-viserver $config.VIserver
        
        # Set WebOperationTimeout to 1 hour to stop the script timing out and erroring
        Set-PowerCLIConfiguration -scope Session -WebOperationTimeoutSeconds 3600 -Confirm:$false

        # Host list
          if ($Live){
            $listofhosts = (get-datacenter | Where-Object {($_.Name -ne "BNW") -and ($_.Name -ne "ALW")}  | Get-VMHost).Name  # the filter is to exclude the clusterized hosts; this is for standalone hosts only
          }else {
            $listofhosts = Get-Content  "$currentPath/config/hostlist.txt"
          }          
          
    }
    
    process {

      # Process each host in the list
      Foreach ($esxhost in $listofhosts){

        $currentesxhost = get-vmhost $esxhost
        Write-Host “Processing $currentesxhost”
        Write-Host “====================================================================”

        $currentCompliance = (get-compliance -entity $esxhost)

      #region I. - Shutdowns
        If ($currentCompliance.status -contains "NotCompliant"){
          
          write-host "$esxhost has some remediation work to do, shutting down VMs and placing host into maintenance mode"

          # Shut down all the VM-s on the host first ...
          Foreach ($VM in ($currentesxhost | Get-VM | where { $_.PowerState -eq “PoweredOn” })){

            Write-Host “====================================================================”
            Write-Host “Processing $vm”

            # ... except if the VM is on the exception list
            if ($vmstoleave -contains $vm){

              Write-Host “I am $vm – I will go down with the ship”
          
            # ...before the shutdown, ensure VMware tools available ...
            } else {

              Write-Host “Checking VMware Tools….”
              $vminfo = get-view -Id $vm.ID

              # ... if the VM had no VMware tools installed, do a hard power off
              if ($vminfo.config.Tools.ToolsVersion -eq 0){
                                
                Write-Host “$vm doesn’t have vmware tools installed, hard power this one”
                # Hard Power Off
                Stop-VM $vm -confirm:$false

              # ... but normally do a graceful shutdown of the VM
              } else {
                
                write-host “I will attempt to shutdown $vm”

                $vmshutdown = $vm | shutdown-VMGuest -Confirm:$false

              }

            }

          }

          # Now we wait for the VM shutdown to finish
          $vmState = $null
          do {
          
            $vmState = ($currentesxhost| Get-vm).PowerState
            Write-Host "Waiting for $esxhost VM-s to all PoweredOff ... [try: $x]" -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            $x++

          } until ($vmState -notcontains "PoweredOn")
          Write-Host "... All VM-s are PoweredOff on $esxhost. Continuing." -ForegroundColor Green

          # Now that all VM-s are down, we put the host into maintenace mode ...
          Write-Host "Placing $esxhost into maintenance mode"
          Get-VMHost -Name $esxhost | set-vmhost -State Maintenance 

          $vmHostState = $null
          $x = 1
          do {
            $vmHostState = (Get-vmhost -name $esxhost).state
            Write-Host "Waiting for $esxhost going to maintenance, plese wait ... [try: $x]" -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            $x++
          } until ($vmHostState -match "Maintenance")
          Write-Host "... $esxhost is in maintenace, continuing" -ForegroundColor Green
                      
            # Giving the host extra 30 seconds to get to maintenance
            Write-Host "Giving the host another 30 seconds to complete maintenance mode"
            Start-sleep -seconds 30  
        }
      #endregion I. - Shutdowns

      #region II. - Host Updates
         
        Foreach ($hostbasecomp in (get-compliance -entity $esxhost)){
        $currenthostbaseComp = (get-compliance -entity $esxhost)
          # Check host compliance ...
          If ($currenthostbasecomp.status -eq "Compliant"){

           Write-Host "The host $esxhost is compliant for the "$hostbasecomp.Baseline.name" Baseline, skipping to next Baseline"
          
            #...if not compliant, attempt to remediate
          } else {

            Write-Host "The host $esxhost is not compliant for the "$hostbasecomp.Baseline.name" Baseline, attempting to remediate this baseline"

            # ... Remediate selected host for baseline ...
            write-host "Deploying "$hostbasecomp.Baseline.name" Baseline"
            Get-baseline -name $hostbasecomp.Baseline.name | update-entity -entity $currentesxhost -confirm:$false}
      #endregion II. - Host Updates  

      #region III. - Restarts

            # ... Take the host out of maintenace mode ...
            write-host "Removing host from Maintenance Mode"
            Get-VMHost -Name $currentesxhost | set-vmhost -State Connected

            # Restart the VM-s on the host ...
            $startupvmlist = get-vmhost -name $currentesxhost | get-vm | Get-VMStartPolicy | Where-Object {$_.StartAction -eq "PowerOn"}
            write-host "Let's process all the auto-startup VMs on the host"
            foreach ($vmtopoweron in $startupvmlist.VM) {
              $vmtopoweroninfo = get-view -Id $vmtopoweron.ID
            # Lets check if it has vmtools, if not we continue to the next VM otherwise we will wait until vmtools are running before moving on  
              If ($vmtopoweroninfo.config.Tools.ToolsVersion -eq 0){
              write-host "Powering on $vmtopoweron, since it doesn't have vmtools I will wait 30 seconds then continue with the next VM"
              start-vm -VM $vmtopoweron
              start-sleep -seconds 30
              }else
              { start-vm -VM $vmtopoweron
              do {
                Write-Host "Waiting for $vmtopoweron to power up and please wait ... [try: $x]" -ForegroundColor Yellow
             # Get the power state
                $powerstate = $toolstate = $null
                $toolstate = (get-vm $vmtopoweron).Guest.ExtensionData.ToolsRunningStatus
                $powerstate = (Get-Vm $vmtopoweron).PowerState
                Start-Sleep -Seconds 5

              } until (($powerstate -eq "PoweredOn") -and ($toolstate -eq "guestToolsRunning"))
              write-host "$vmtopoweron has now got VMware tools running, let's give it 30 seconds before continuing"
              start-sleep -Seconds 30
              
                # ... and wait for the VM-s to come online (now obsolete since we are waiting for vmtools to be running
                # Write-Host "Let's wait 5 minutes before starting the next host to give enough time for VMs to boot up."
                # start-sleep -seconds 300
            }

      #endregion III. - Restarts

          

        }

      }
    
  }
  }
    end {

        # Log errors
        if ($Error) { 
        "[WARN] ERRORS FOUND DURING SCRIPT RUN" | Out-File $ErrorFile -Force
        $Error | Out-File $ErrorFile -Append 
        }
        else { 
        "[INFO] NO ERRORS DURING SCRIPT RUN" | Out-File $ErrorFile 
        } 

        # Disconnect VI-server session
        disconnect-viserver -confirm:$false

        # End transcript logs
        Stop-Transcript
        
    }

