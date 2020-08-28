
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
    Version:        2.0
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
  # Setup
  # All errors should be terminating errors
  $ErrorActionPreference = "Stop"
  # Script exectuion path for relative paths    
  $CurrentPath = $config = $null
  $CurrentPath = Split-Path -Parent $PSCommandPath
  # Define log files
  $date = Get-date -Format yyyy-MM-dd
  ## transcript
  $logfile = $CurrentPath + "\" + "logs" + "\" + $date + "_actions.log"
  Start-Transcript $logfile -Force
  ## errors
  $ErrorFile = $CurrentPath + "\" + "logs" + "\" + $date + "_error.log"
  $Error.clear()
  # Import various input files    
  ## configuration      
  $config = Import-Csv "$currentPath/config/config.csv"
  ## excetpions (VM-s to leave powered on)
  $vmstoleave = Get-Content "$currentPath/config/VMexceptions.txt"  
  # Connect to the VI server
  connect-viserver $config.VIserver
  # Set WebOperationTimeout to 1 hour to stop the script timing out and erroring
  Set-PowerCLIConfiguration -scope Session -WebOperationTimeoutSeconds 3600 -Confirm:$false
  # Define host list for Live (all available hosts not in the clustered datacenters) or test runs
  if ($Live) {
    $listofhosts = (get-datacenter | Where-Object { ($_.Name -ne "BNW") -and ($_.Name -ne "ALW") }  | Get-VMHost).Name  # the filter is to exclude the clusterized hosts; this is for standalone hosts only
  }
  else {
    $listofhosts = Get-Content  "$currentPath/config/hostlist.txt"
  }          
  # Functions (script will uses these to execute the process)
  $functions = (Get-ChildItem "$currentPath/functions").FullName
  foreach ($f in $functions) {
    Write-Host -ForegroundColor Cyan "Importing function $f"
    if ($f -match ".ps1") {
      . $f
    }
  }
}

process {
  # Process each host in the $listofhosts
  Foreach ($esxhost in $listofhosts) {
    # Create host object
    $currentesxhost = get-vmhost $esxhost 
    Write-Host “Processing $currentesxhost”
    Write-Host “====================================================================”
    do {

      # Collect current host complieance status
      $hostStartingComplianceState = $null
      $hostStartingComplianceState = (get-compliance -entity $esxhost)
      # If there is non-compliand baselines, first shut down all the VM-s of the host
      If ($hostStartingComplianceState.status -contains "NotCompliant") {     
        # Update - phase 1 - Attempt to shut down all the VM-s on the host first. Either using VMware tools for a graceful shutdown, or hard shutdown
        write-host "$esxhost has some remediation work to do, shutting down VMs and placing host into maintenance mode"
        $runningVMs = $null
        $runningVMs = ($currentesxhost | Get-VM | Where-Object { $_.PowerState -eq “PoweredOn” })
        Foreach ($vm in $runningVMs) {
          Shutdown-RunningVM -vm $vm -vmstoleave $vmstoleave
        }
        # Wait for the completion of the shutodwn of all the VM-s
        Wait-AllVMsDown -esxhost $esxhost -currentesxhost $currentesxhost
        # Now that all VM-s are down, we put the host into maintenace mode
        Start-HostMaintenance -esxhost $esxhost
      }
      # Update - phase 2 - Next, update all non-compliand baselines
      Foreach ($hostbasecomp in $hostStartingComplianceState) {    
        If ($hostbasecomp.status -eq "Compliant") {
          Write-Host "The host $esxhost is compliant for the "$hostbasecomp.Baseline.name" Baseline, skipping to next Baseline" 
          Write-Host “====================================================================”   
        }
        else {
          Update-HostBaseline -esxhost $esxhost -hostbasecomp $hostbasecomp
        }
      }
      # Repeat the above actions until all the compliance status is compliant
    } until ($hostStartingComplianceState.status -notcontains "NotCompliant")   
    
    # Update - phase 3 - Finally, when all baselines has been made compliant, take the server out of maintenance and restart VM-s on it
    Stop-HostMaintenance -esxhost $esxhost
    Start-AutostartVMs -currentesxhost  $currentesxhost    
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
  Disconnect-viserver -confirm:$false
  # End transcript logs
  Stop-Transcript    
}

