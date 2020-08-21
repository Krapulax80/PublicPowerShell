<#
Function to create a report (visual and .csv) on the OS-es of the target domain's computer objects.

#EXAMPLE:

#Test the current domain and generate the report file into the "C:\Temp folder"

Get-ADOSReport -reportfolder "C:\Temp" 

#Same as above, only with checking a different (trusted) domain

Get-ADOSReport -reportfolder "C:\Temp" -domain "fabrikam.com"

#>
function Get-ADOSReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $domain = $env:USERDNSDOMAIN,

        [Parameter(Mandatory = $false)]
        [pscredential] $credential = (Get-Credential),

        [Parameter(Mandatory = $false)]
        [string] $reportfolder = ([Environment]::GetFolderPath("Desktop"))
        
    )
    
    begin {
        $ErrorActionPreference = "Stop"
        Import-Module ActiveDirectory

        $DomainController = (Get-ADForest -Identity $domain -Credential $credential |  Select-Object -ExpandProperty RootDomain |  Get-ADDomain |  Select-Object -Property PDCEmulator).PDCEmulator
        $DomainUnderscore = $domain -replace "\.", "_"
        $csv = $reportfolder + "\" + $DomainUnderscore + "_ADOSReport.csv"
    }
    
    process {
        $ComputerReport = Get-ADComputer -Filter * -Property * -Server $DomainController -Credential $credential | Select-Object Name, OperatingSystem, OperatingSystemServicePack, OperatingSystemVersion
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "List of [$domain] domain's computers as follows:"
        $ComputerReport | Group-Object OperatingSystem
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "[Detailed report saved as $csv]"
        $ComputerReport | Export-Csv $csv -NoTypeInformation -Encoding UTF8 -Force
        
    }
    
    end {
        $ComputerReport = $null
    }
}

<#
Function to create a report (visual and .csv) of the inactive users of a domain (or an OU of a domain)

.PARAMETERS
 $domain - the domain to work on; if blank, this is the current domain
 $credentials - domain credentials used
 $reportfolder - the folder to save the output CSV; if blank, this is the current user's decktop
 $daysinactive - inactivity days needed to be included in the script
 $OU - if you want to target a certain OU, enter the distinguished name here; else it will search the whole domain

 .EXAMPLES

 # Target specific OU

 Get-ADUserInactivityReport -OU "OU=USERS,OU=London,DC=fabrikam,DC=co,DC=uk"

 # Target a full domain

 Get-ADUserInactivityReport -domain "contoso.com"

#>

function Get-ADUserInactivityReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $domain = $env:USERDNSDOMAIN,

        [Parameter(Mandatory = $false)]
        [pscredential] $credential = (Get-Credential),

        [Parameter(Mandatory=$false)]
        [string] $reportfolder = ([Environment]::GetFolderPath("Desktop")),

        [Parameter(Mandatory = $false)]
        [string] $daysinactive = 90,
        
        [Parameter(Mandatory = $false)]
        [string] $OU
        
    )
            
    begin {
        $ErrorActionPreference = "Stop"
        Import-Module ActiveDirectory

        $DomainController = (Get-ADForest -Identity $domain -Credential $credential |  Select-Object -ExpandProperty RootDomain |  Get-ADDomain |  Select-Object -Property PDCEmulator).PDCEmulator
        $DomainUnderscore = $domain -replace "\.", "_"
        $csv = $reportfolder + "\" + $DomainUnderscore + "_ADUserInactivityReport.csv"   
        $time = (Get-Date).Adddays(- ($DaysInactive))     
    }
    
    process {

        # Collect inactive users
        if ($OU){
            $InactiveUserReport = Get-ADUser -searchbase $OU -Filter { LastLogonTimeStamp -LT $time -and Enabled -EQ $true } -Properties LastLogonTimeStamp -Server $DomainController -Credential $credential
        } else {
            $InactiveUserReport = Get-ADUser -Filter { LastLogonTimeStamp -LT $time -and Enabled -EQ $true } -Properties LastLogonTimeStamp -Server $DomainController -Credential $credential
        }
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "List of [$domain] domain's inactive users (last logon within the last $daysinactive days):"
        $InactiveUserReport | Select-Object Name, Enabled, UserPrincipalName, @{ Name = "LogonTimeStamp"; Expression = { [datetime]::FromFileTime($_.lastLogonTimestamp).ToString('yyyy-MM-dd_HH:mm:ss') }}  | sort Name | ft -Autosize

        # Send inactive users to CSV
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "[Detailed report saved as $csv]"
        $InactiveUserReport | Select-Object Name,@{ Name = "LogonTimeStamp"; Expression = { [datetime]::FromFileTime($_.lastLogonTimestamp).ToString('yyyy-MM-dd_HH:mm:ss') } } | Export-Csv $csv -NoTypeInformation -Force
        
    }
    
    end {
        $InactiveUserReport = $null
    }
}

<#
Function to create a report (visual and .csv) of the users of the domain, who's password already expired

.PARAMETERS
 $domain - the domain to work on; if blank, this is the current domain
 $credentials - domain credentials used
 $reportfolder - the folder to save the output CSV; if blank, this is the current user's decktop
 $OU - if you want to target a certain OU, enter the distinguished name here; else it will search the whole domain

 .EXAMPLES

 # Target specific OU

 Get-ADUserExpiredPasswordReport -OU "OU=USERS,OU=London,DC=fabrikam,DC=co,DC=uk"

 # Target a full domain

 Get-ADUserExpiredPasswordReport -domain "contoso.com" 

#>
function Get-ADUserExpiredPasswordReport {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $domain = $env:USERDNSDOMAIN,

        [Parameter(Mandatory = $false)]
        [pscredential] $credential = (Get-Credential),

        [Parameter(Mandatory=$false)]
        [string] $reportfolder = ([Environment]::GetFolderPath("Desktop")),
        
        [Parameter(Mandatory = $false)]
        [string] $OU
        
    )
            
    begin {
        $ErrorActionPreference = "Stop"
        Import-Module ActiveDirectory

        $maxPasswordAge = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days
        $settingdate = (Get-Date).AddDays(-$maxPasswordAge)
        $DomainController = (Get-ADForest -Identity $domain -Credential $credential |  Select-Object -ExpandProperty RootDomain |  Get-ADDomain |  Select-Object -Property PDCEmulator).PDCEmulator
        $DomainUnderscore = $domain -replace "\.", "_"
        $csv = $reportfolder + "\" + $DomainUnderscore + "_ADUserExpiredPassword.csv"   
    }
    
    process {
        if ($OU){
            $ExpiredPasswordReport = Get-ADUser -searchbase $OU -Filter { Enabled -EQ $True -and PasswordNeverExpires -EQ $False } –Properties * -Server $DomainController -Credential $credential | Where-Object {($_.PasswordLastSet -le $settingdate) } 
        } else {
            $ExpiredPasswordReport = Get-ADUser -Filter { Enabled -EQ $True -and PasswordNeverExpires -EQ $False } –Properties * -Server $DomainController -Credential $credential | Where-Object {($_.PasswordLastSet -le $settingdate) } 
        }
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "List of [$domain] domain's users with expired password (password last set at least [$maxPasswordAge] days ago):"
        $ExpiredPasswordReport | Select-Object Name,PasswordLastSet,@{ n = "ExpiryDate"; e = { $_.PasswordLastSet.Adddays($maxPasswordAge) } }  | sort Name | ft -Autosize

        # Send inactive users to CSV
        Write-Host -ForegroundColor Black -BackgroundColor Cyan "[Detailed report saved as $csv]"
        $ExpiredPasswordReport | Select-Object Name,PasswordLastSet,@{ n = "ExpiryDate"; e = { $_.PasswordLastSet.Adddays($maxPasswordAge) } }  | Export-Csv $csv -NoTypeInformation -Force
        
    }
    
    end {
        $ExpiredPasswordReport = $null
    }
}

<#
Function to quickly collect FSMO roles for the admin (add "-domain" to search other then the current domain)
#>

function Get-ADFSMORoles {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string] $domain = $env:USERDNSDOMAIN,

        [Parameter(Mandatory = $false)]
        [pscredential] $credential = (Get-Credential)
        
    )
    
    begin {
        $DomainController = (Get-ADForest -Identity $domain -Credential $credential |  Select-Object -ExpandProperty RootDomain |  Get-ADDomain |  Select-Object -Property PDCEmulator).PDCEmulator
    }
    
    process {
        $SchemaMaster = (Get-ADForest -Server $DomainController -Credential $credential  ).SchemaMaster
        $DomainNamingMaster = (Get-ADForest -Server $DomainController -Credential $credential  ).DomainNamingMaster
        $PDCEmulator =  (Get-ADDomain -Server $DomainController -Credential $credential  ).PDCEmulator
        $RIDMaster = (Get-ADDomain -Server $DomainController -Credential $credential  ).RIDMaster
        $InfrastructureMaster = (Get-ADDomain -Server $DomainController -Credential $credential  ).InfrastructureMaster

        Write-Host # lazy line break
        Write-Host "We have collected the details of $domain :" -ForegroundColor Black -BackgroundColor Cyan
        Write-Host "FOREST:                        $((Get-ADForest -Server $DomainController -Credential $credential).Name)"
        Write-Host "DOMAIN:                        $((Get-ADDomain -Server $DomainController -Credential $credential).Name)"
        Write-Host "Schema Master DC:              $SchemaMaster"
        Write-Host "Domain Naming Master DC:       $DomainNamingMaster"
        Write-Host "PDC Emulator DC:               $PDCEmulator"
        Write-Host "RID Master DC:                 $RIDMaster"
        Write-Host "Infrastructure Master DC:      $InfrastructureMaster"
 
    }
    
    end {
        
    }
}
