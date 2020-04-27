<#
.SYNOPSIS
    Minimalistic Continuous Delivery
.DESCRIPTION
    Continuous Delivery Pipeline Stages
    Connect to remote
    Check if version updated
    Download Files
    Stop services
    Backup DB
    Deploy DB (DACPAC)
    Start Sercives
    Run Automated Tests
.EXAMPLE
    Compare-Baseline 
.NOTES
    File Name    : MinimalisticCD.ps1
    Author       : Lee Tamplin
    Created Date : 17/02/2020
    To do        :    
#>
param ($TranferOnly) # Paramter to only tranfer feedback files
Import-Module SqlServer # Microsoft Database tools

# Settings
$OperationsId      = "123456" # Operations Organisations ID
$services          = "lfsvc","spooler" # Comma seperated list of services required to be stopped before update and started after
$dbBackupDir       = "C:\DBBackup\" # Path for SQL Backups
$dbBackupFileName  = "1.bac" # Backup name
$dbServer          = "(local)" # Database Server name
$dbName            = "MockDB2"# Database Name
$drop              = "C:\Release\" # Directory for temporary files
$applicationFolder = "C:\Src1\" # Path to Application Directory
$applicationName   = "src\MockApplication.exe" # Application name
$dacpacSubFolder   = "\drop\DacPac\" # Path to dac file 
$dacpacName        = "MockDB.dacpac" # Dac File Name
$dacpacPath        = (Join-Path -Path $drop -ChildPath $dacpacSubFolder) + $dacpacName # Location of downloaded DACPAC 
$dbBackupLocation  = ($dbBackupDir) + $dbBackupFileName # DB backup location - overwritten on each run
$sqlPackageExePath = "C:\Program Files\Microsoft SQL Server\150\DAC\bin\sqlpackage.exe" # Path to sqlpackage.exe
$userName          = "" # DB username (blank use trusted connection)
$password          = "" # DB password (blank use trusted connection)
$logFileDir        = "C:\temp\log\" # Path to Pipeline logs
$AppErrorDir       = "C:\Src1\TransferFiles\Errors\" # Path to Application Errors
$AppFeedBackDir    = "C:\Src1\TransferFiles\FeedBack\" # Path to In-App FeedBackFiles
$LogFileName       = "Log$ClientID $(get-date -f yyyyMMddHHmmss).csv"


<#
.SYNOPSIS
    Setup prior to run
.DESCRIPTION
    used to setup environment prior to run
.OUTPUTS
    None
.EXAMPLE
    
#>
function setup-env {
    Process {
        try {
            If(!(test-path $dbBackupDir)) {
                New-Item -ItemType directory -Path $dbBackupDir
            }
            If(!(test-path $logFileDir)) {
                New-Item -ItemType directory -Path $logFileDir
            }
            If(!(test-path $applicationFolder)) {
                New-Item -ItemType directory -Path $applicationFolder
            }
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true | out-null
    }      
}


<#
.SYNOPSIS
    Logs delivery results and timings
.DESCRIPTION
    Used to log the results of each stage
.OUTPUTS
    None
.EXAMPLE
    
#>
function Log-Result {
    param (
        [Parameter (position=0)][string] $logTextLine,
        [Parameter (position=1)][datetime] $Start,
        [Parameter (position=2)][string] $Status       
    )
    
    Process {
        try {
            $now = Get-Date
            $duration = ((NEW-TIMESPAN –Start $Start –End $Now).TotalSeconds).ToString("#.#")            
            $NewLine = "{0},{1},{2}" -f $duration,$logTextLine,$Status
            $NewLine | add-content -path ($logFileDir + $LogFileName)
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true | out-null
    }      
}


<#
.SYNOPSIS
    Updates time out
.DESCRIPTION
    used to update time-out variables
.OUTPUTS
    updated timeout integer
.EXAMPLE
    $timeout = (Time-Out $timeout) 
#>
function Time-Out {
    param ($timeOutSec)
    
    Process {
        Start-Sleep -Seconds 1
        $timeOutSec ++ 
        return $timeOutSec
    }      
}


<#
.SYNOPSIS
    SSH Connection to remote delivery server
.DESCRIPTION
    used to check current version and download new versions
.OUTPUTS
    path to source file if modification available
.EXAMPLE
    
#>
function Connect-DeliveryServer {
    Process {
        try {
            $session = new-pssession -Hostname 192.168.1.10 -Port 22 -UserName ContinuousDelivery # Connect to Continuous Delivery Server
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true, $session
    }      
}


<#
.SYNOPSIS
    Check Continuous Delivery Server for modified version
.DESCRIPTION
    used to check current version
.OUTPUTS
    path to source file if modification available
.EXAMPLE
    
#>
function CheckVersion-DeliveryServer {
    param (
        [Parameter (position=0)][object] $session        
    )
    Process {
        try {
            if (Test-Path (Join-Path $applicationFolder $applicationName)) { 
                $currentVersion =  ((Get-Item (Join-Path $applicationFolder $applicationName)).VersionInfo.ProductVersion) # Get current application version                           
            }
            else {$currentVersion = ""}
            # The following command runs a scriptblock on the remote Delivery Server not locally
            # Get Path to new version if available (returns "" if not required) 
            $source = invoke-command $session -scriptblock {Check-Release -OperationsId $using:OperationsId -AppVersion $using:currentVersion} 
            # End remote script           
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true, $source
    }      
}


<#
.SYNOPSIS
    Disconnect |SSH session
.DESCRIPTION
    Disconnect existing session
.OUTPUTS
    None
.EXAMPLE
    
#>
function Close-DeliveryServer {
    param (
        [Parameter (position=0)] $session        
    )

    Process {
        try {
            Remove-PSSession -Session $session # Close session
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true, $source, $session
    }      
}


<#
.SYNOPSIS
    Transfers Files from CD Server
.DESCRIPTION
    Download files from the supplied session and path
.OUTPUTS
    path to source file if modification available
.EXAMPLE
    
#>
function Download-Artefact {
    param (
        [parameter (position=0)][string] $source,
        [parameter (position=1)] $session
        )

    Process {
        try {
            Copy-Item -FromSession $session $source -Destination $drop -Recurse -Force # Download version files            
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true, $source
    }      
}


<#
.SYNOPSIS
    Transfers Log File To Server
.DESCRIPTION
    Upload log file from the supplied session and path
.OUTPUTS
    Result boolean
.EXAMPLE
    
#>
function Upload-File {
    param (
        [parameter (position=0)][string] $source,
        [parameter (position=1)] $session  
        )
        
    Process {
        try {
            if ((Get-ChildItem $source).Count -gt 0) {            
                Copy-Item -Path "$($source)*" -Destination "C:\FeedBackFiles\" -ToSession $session  -Recurse -Force # Upload Log File           
                Get-ChildItem -Path "$($source)*" | Remove-Item -Force
                }
            }
            catch {
            Write-Error $_
            return $false
        }
        return $true, $source
    }      
}


<#
.SYNOPSIS
    Stops Services
.DESCRIPTION
    Stops all services listed in the $services setting
.OUTPUTS
    Boolean Returns true if all services stopped
.EXAMPLE
    C:\PS> Stop-Services "lfsvc","gupdate"
#>
function Stop-Services {
    param ($services)
    
    Process {
        try {
            foreach ($service in $services) {
                If ((Get-Service $Service).Status -eq "Running") { 
                    Write-Host "Stopping Service: $service"
                    Stop-Service $Service
                    Do {                
                        $timeout = (Time-Out $timeout)                
                    }  
                    Until (((Get-Service $Service).Status -eq "Stopped") -or ($timeout -eq 5))
                }        
            }
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


<#
.SYNOPSIS
    Copy Files
.DESCRIPTION
    Copy files from the drop to destination
.OUTPUTS
    Boolean Returns true if files copied
.EXAMPLE
    C:\PS> Copy-Source
#>
function Copy-Source {
    Process {
        try {
            Copy-Item -Path "$($drop)*" -Destination $applicationFolder -Recurse -Force     
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


<#
.SYNOPSIS
    Starts Services
.DESCRIPTION
    Starts all services listed in the $services setting
.OUTPUTS
    Boolean Returns true if all services started
.EXAMPLE
    C:\PS> Start-Services "lfsvc,gupdate"
#>
function Start-Services {
    param ($services)
    
    Process {
        try {
            foreach ($service in $services) {                
                If ((Get-Service $Service).Status -ne "Running") { 
                    Write-Host "Starting Service: $service"
                    Start-Service $Service
                    Do {                
                        $timeout = (Time-Out $timeout)                
                    }  
                    Until (((Get-Service $Service).Status -eq "Running") -or ($timeout -eq 5))
                }        
            }
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


<#
.SYNOPSIS
    Backup DB
.DESCRIPTION
    Backs up a DB if it exists
.OUTPUTS
    Boolean Returns true if DBBacked up
.EXAMPLE
    C:\PS> Backup-SQLDB -dbServer ServerName -dbName DatabaseName -dbBackupLocation Directory
#>
function Backup-SQLDB {
    param (
        [Parameter (position=0)][string] $dbServer,
        [Parameter (position=1)][string] $dbName,
        [Parameter (position=2)][string] $dbBackupLocation
    )
    
    Process {    
        try {
            $srv = new-object microsoft.sqlserver.management.smo.server        
            if ($null -ne $srv.Databases[$dbName]) {
                Write-Host "Backup DB: $dbName"
                Backup-SqlDatabase `
                    -ServerInstance $dbServer `
                    -Database $dbName `
                    -BackupFile $dbBackupLocation
            }
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


<#
.SYNOPSIS
    Deploy DACPAC
.DESCRIPTION
    Publishes a DACPAC - Creates DB if doesn't exist
.OUTPUTS
    Boolean Returns true if DACPAC published
.EXAMPLE
    C:\PS> Start-Services "lfsvc,gupdate"
#>
function Publish-DACPAC {
    param (
        [Parameter ()][string] $sqlPackageExePath,
        [Parameter ()][string] $dacpacPath,
        [Parameter ()][string] $dbServer,
        [Parameter ()][string] $dbName,
        [Parameter ()][string] $userName,
        [Parameter ()][string] $password
    )
    
    Process {    
        try {            
            if ($userName -ne "") {
                &"$sqlPackageExePath" `
                    /Action:Publish `
                    /SourceFile:"$dacpacPath" `
                    /TargetServerName:$dbServer `
                    /TargetDatabaseName:$dbName `
                    /TargetUser:$userName `
                    /TargetPassword:$password | Write-Host
            } 
            else {                
                &"$sqlPackageExePath" `
                    /Action:Publish `
                    /SourceFile:"$dacpacPath" `
                    /TargetServerName:$dbServer `
                    /TargetDatabaseName:$dbName | Write-Host
            }            
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


<#
.SYNOPSIS
    Run Tests
.DESCRIPTION
    Run Application Tests
.OUTPUTS
    Boolean Returns true if tests pass
.EXAMPLE
    C:\PS> Start-Services "lfsvc,gupdate"
#>
function Test-Application {
    Process {    
        try {            
            $result = & "C:\src1\src\tests\testpass.ps1" 
            if ($result -eq $false) {
                return $false
            }                 
        }
        catch {
            Write-Error $_
            return $false
        }
        return $true
    }
}


function Run-PipeLine {
    [CmdletBinding()]
    param ()

    begin {              
    }

    process { 
        # Intialise Job
        $start = get-date
        if ((setup-env) -eq $false) {
            Log-Result "Initialise Job" $start "failed"
            break
        } 

        $return = Connect-DeliveryServer
        $session = $return[1]
        
        if (($return[0]) -eq $false) {
            Log-Result "Initialise Job" $start "failed"
            break
        }
                
        # Check for new version
        $return = CheckVersion-DeliveryServer $session
        $PathToNewVersion = $return[1]
        if (($return[0]) -eq $false) {
            Log-Result "Initialise Job" $start "failed"
            break
        }
                
                
        if (($PathToNewVersion) -eq "") {
            Log-Result "Initialise Job" $start "no new version"
            Write-Host "Version already current"   
            break
        }
        Write-Host "Version Change"         
        Log-Result "Initialise Job" $start "succeeded" 

        # Download Artefact
        $start = get-date
        if ((Download-Artefact $PathToNewVersion $session) -eq $false) {
            Log-Result "Download Artefact" $start "failed"
            break
        }        
        Log-Result "Download Artefact" $start "succeeded"
        
        
        # Stop Services
        $start = get-date
        if ((Stop-Services  $services) -eq $false) {
            Log-Result "Stop Services" $start "failed"
            break
        }
        Log-Result "Stop Services" $start "succeeded"


        # Backup DB
        $start = get-date
        if ((Backup-SQLDB -dbServer $dbServer -dbName $dbName -dbBackupLocation $dbBackupLocation) -eq $false) {
            Log-Result "Backup DB" $start "failed"
            break
        }
        Log-Result "Backup DB" $start "succeeded"


        # Copy Files
        $start = get-date
        if ((Copy-Source) -eq $false) {
            Log-Result "Copy Source" $start "failed"
            break
        }
        Log-Result "Copy Source" $start "succeeded"
                       

        # Deploy DACPAC
        $start = get-date
        if ((Publish-DACPAC $sqlPackageExePath $dacpacPath $dbServer $dbName $username $password)  -eq $false) {
            Log-Result "Deploy DacPac" $start "failed"
            break
        }
        Log-Result "Deploy DacPac" $start "succeeded"

        # Start Services
        $start = get-date
        if ((Start-Services $services) -eq $false) {
            Log-Result "Start Services" $start "failed"
            break
        }
        Log-Result "Start Services" $start "succeeded"

        # Run Tests
        $start = get-date
        if ((Test-Application) -eq $false) {
            Log-Result "Tests" $start "failed"
            break
        }
        Log-Result "Tests" $start "succeeded" | Out-Null    
        
        # Upload Log File to Cd Server
        Upload-File ($logFileDir + $LogFileName) $session  | Out-Null 
        
        # Upload Application Error Files to CD Server 
        Upload-File ($AppErrorDir) $session  | Out-Null
        
        # Upload In-App Feed-back Files to CD Server
        Upload-File ($AppFeedBackDir) $session  | Out-Null 
        
        # Close Connection
        Close-DeliveryServer $session | Out-Null          
    }
    
    end {       
    }   
}


# Check which functionality to include
if ($TranferOnly -eq $true) {
    $return = Connect-DeliveryServer
        
    $session = $return[1]
    if (($return[0]) -eq $false) {
        Log-Result "Initialise Job" $start "failed"
        break
    }           
    

    # Upload Log File to CD Server
    Upload-File ($logFileDir) $session | Out-Null
    
    # Upload Application Error Files to CD Server
    Upload-File ($AppErrorDir) $session  | Out-Null
    
    # Upload In-App Feed-back Files to CD Server
    Upload-File ($AppFeedBackDir) $session  | Out-Null 
        
    # Close Connection
    Close-DeliveryServer $session       
        
    }
else {
    Run-PipeLine
}