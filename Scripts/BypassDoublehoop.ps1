<#
.Synopsis
   Function to overcome the "double-hop" with a tempoary CredSSP delegation

.DESCRIPTION
    The script is to address the "infamous" double hop (https://docs.microsoft.com/en-us/powershell/scripting/learn/remoting/ps-remoting-second-hop?view=powershell-7) problem.
    As the link contains the description and pottential solutions, read it, if you need details.

    What I try to achieve here is to make the solution into a reusable solution. It also addresses a local problem I have (where our domain admin accounts does not have proxy access) 
    which might not be neccesary for everyone, therefore this is only turned on using a switch.
    The script makes possible to connect from serverA to serverB and execute a command on serverB targeting serverC, by creating a temporary CredSSP client/server relationship between
    serverA and ServerB allowing ServerB to pass credential from serverA to ServerC (thus making the command execution possible)
    To cater maximum security (or as much as possible with CredSSP):
    - the CredSSP delegation is removed from both client and server(s) at the end of the process
    - the CredSSP delegation is only betweeen ServerA and the server(s) listed in the $ComputerNames parameter
    F.S.

.EXAMPLE
    ## Using with account that does not have proxy address directly to the target servers

    $credential = (Get-Credential)
    $computers = @('BNWTESTRDWEB001.westcoast.co.uk','BNWTESTRDSH001.westcoast.co.uk','BNWTESTRDSH002.westcoast.co.uk')
    $computers | Bypass-Doublehoop -credential $credential -bypassProxy -command "Get-ChildItem -Path '\\BNWTESTRDCB001.contoso.com\c$'"
   

#>

function Bypass-Doublehoop {
    <#
    This function is designated to bypass the double hoop to one or more server
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]
        $ComputerNames, # server(s) where we want to execute command(s) 
        [Parameter(Mandatory = $false)]
        [switch]
        $bypassProxy, # (this is specific to my environment, where the admin accounts has no proxy access; normally this does not needed - FS)
        [Parameter(Mandatory = $false)]
        [pscredential]
        $credential, # either provide credentials before the script run, or the script will ask for it
        [Parameter(Mandatory)]
        [string]
        $command # the command that you wish to execute     
    )
    
    begin {
        
        # Set up the environment
        $EAP = $ErrorActionPreference
        $ErrorActionPreference = 'Stop'

        # Ensure we have a credential
        if (!($credential))
        {
        $credential = (Get-Credential)
        }
        
        # Verify the server is not set to use CredSSP
        Write-host "[Host: $(Hostname):]"
        #Get-WSManCredSSP
        
    }
    
    process {

        foreach ($c in $ComputerNames)
        {
        Write-Host # lazy line break
        Write-Host "Executing command on $c : " -ForegroundColor Black -BackgroundColor Cyan

        # Allow server to be the CLIENT for each remote servers for CredSSP
        [void](Enable-WSManCredSSP -Role Client -DelegateComputer $c -Force)

        # Allow the remote server(s) to be SERVER for CredSSP
            if ($bypassProxy.IsPresent){
            $pso = New-PSSessionOption -ProxyAccessType NoProxyServer
            [void](Invoke-Command -Credential $credential -SessionOption $pso -ComputerName $c -Scriptblock {Enable-WSManCredSSP -Role Server -Force})
            }
            else{
            [void](Invoke-Command -Credential $credential -ComputerName $c -Scriptblock {Enable-WSManCredSSP -Role Server -Force})
            }

        # Send the command to the server
            if ($bypassProxy.IsPresent){
            $pso = New-PSSessionOption -ProxyAccessType NoProxyServer
            Invoke-Command -SessionOption $pso -ComputerName $c  -Scriptblock {Invoke-Expression $using:command} -Authentication Credssp -Credential $credential
            }
            else{
            Invoke-Command -ComputerName $c -Scriptblock {Invoke-Expression $using:command} -Authentication Credssp -Credential $credential
            }

        # Remove the CredSSP roles from the remote machines
            if ($bypassProxy.IsPresent){
            $pso = New-PSSessionOption -ProxyAccessType NoProxyServer
            Invoke-Command -Credential $credential -SessionOption $pso -ComputerName $c  -Scriptblock {Disable-WSManCredSSP -Role Server}
            }
            else{
            Invoke-Command -Credential $credential -ComputerName $c  -Scriptblock {Disable-WSManCredSSP -Role Server}
            }            
        

        }
        
    }
    
    end {

    # Remove the client role on the host
    Disable-WSManCredSSP -Role Client

    # Set back EAP
    $ErrorActionPreference = $EAP
        
    }
}

