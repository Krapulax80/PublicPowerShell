function Start-AutostartVMs {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]$currentesxhost   
  )  

  # Restart the VM-s on the host ...
  $startupvmlist = get-vmhost -name $currentesxhost | get-vm | Get-VMStartPolicy | Where-Object { $_.StartAction -eq "PowerOn" }
  write-host "Let's process all the auto-startup VMs on the host"
  foreach ($vmToPowerOn in $startupvmlist.VM) {
    $vmToPowerOninfo = get-view -Id $vmToPowerOn.ID
    # Lets check if it has vmtools, if not we continue to the next VM otherwise we will wait until vmtools are running before moving on  
    If ($vmToPowerOninfo.config.Tools.ToolsVersion -eq 0) {
      write-host "Powering on $vmToPowerOn, since it doesn't have vmtools I will wait 30 seconds then continue with the next VM"
      start-vm -VM $vmToPowerOn
      start-sleep -seconds 30
    }
    else {
      start-vm -VM $vmToPowerOn
      do {
        Write-Host "Waiting for $vmToPowerOn to power up and please wait ... [try: $x]" -ForegroundColor Yellow
        # Get the power state
        $powerstate = $toolstate = $null
        $toolstate = (get-vm $vmToPowerOn).Guest.ExtensionData.ToolsRunningStatus
        $powerstate = (Get-Vm $vmToPowerOn).PowerState
        Start-Sleep -Seconds 5
      } until (($powerstate -eq "PoweredOn") -and ($toolstate -eq "guestToolsRunning"))
      write-host "$vmToPowerOn has now got VMware tools running, let's give it 30 seconds before continuing"
      start-sleep -Seconds 30
    }
  }
    
}