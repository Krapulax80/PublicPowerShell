function Start-HostMaintenance {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]$esxhost
  )  

  Write-Host "Placing $esxhost into maintenance mode"
  Get-VMHost -Name $esxhost | set-vmhost -State Maintenance 

  $vmHostState = $null
  $x = 1
  do {
    $vmHostState = (Get-vmhost -name $esxhost).ConnectionState
    Write-Host "Waiting for $esxhost going to maintenance, plese wait ... [try: $x]" -ForegroundColor Yellow
    Start-Sleep -Seconds 5
    $x++
  } until ($vmHostState -match "Maintenance")
  Write-Host "... $esxhost is in maintenace, continuing" -ForegroundColor Green           
  # Giving the host extra 30 seconds to get to maintenance
  Write-Host "Giving the host another 30 seconds to complete maintenance mode"
  Start-sleep -seconds 30
}