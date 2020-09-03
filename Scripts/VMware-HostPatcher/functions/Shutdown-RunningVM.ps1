function Shutdown-RunningVM {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]$vm,
    [Parameter(Mandatory)]$vmsToLeave    
  )  

  Write-Host “====================================================================”
  Write-Host “Processing $vm”
  # ... except if the VM is on the exception list
  if ($vmsToLeave -contains $vm) {
    Write-Host “I am $vm – I will go down with the ship”
    # ...before the shutdown, ensure VMware tools available ...
  }
  else {
    Write-Host “Checking VMware Tools….”
    $vminfo = get-view -Id $vm.ID

    # ... if the VM had no VMware tools installed, do a hard power off
    if ($vminfo.config.Tools.ToolsVersion -eq 0) {
      Write-Host “$vm doesn’t have vmware tools installed, hard power this one”
      # Hard Power Off
      Stop-VM $vm -confirm:$false
      # ... but normally do a graceful shutdown of the VM
    }
    else {
      write-host “I will attempt to shutdown $vm”
      $vm | shutdown-VMGuest -Confirm:$false
    }

  }

}