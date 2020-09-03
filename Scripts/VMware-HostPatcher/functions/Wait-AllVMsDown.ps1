function Wait-AllVMsDown {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]$esxhost ,
    [Parameter(Mandatory)]$currentesxhost
  )  
    
  $vmState = $null
  $x = 1
  do {
    $vmState = ($currentesxhost | Get-vm).PowerState
    Write-Host "Waiting for $esxhost VM-s to all PoweredOff ... [try: $x]" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $x++
  } until ($vmState -notcontains "PoweredOn")
  Write-Host "... All VM-s are PoweredOff on $esxhost. Continuing." -ForegroundColor Green
}