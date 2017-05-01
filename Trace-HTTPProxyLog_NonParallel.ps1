function Trace-HTTPProxyLog
{
    [cmdletbinding()]
    #Push Test
    #Parameter Block
    param(
    [ValidateSet("EAS","AutoDiscover","EWS","OWA","ECP","OA","MAPI")][String]$Protocol,
    [string[]]$Server,
    [ValidateRange(1,1000)][int]$ResultSizePerServer,
    [DateTime]$Logstart,
    [DateTime]$LogEnd,
    [String]$UserFilter
    )

    #Set default parameters for those not specified and options

    if(!($Logstart))
    {
        $Logstart = (Get-Date).AddHours(-2)
    }
    if(!($LogEnd))
    {
        $LogEnd = (Get-Date)
    }
    if(!($ResultSizePerServer))
    {
        $ResultSizePerServer = 200
    }

    #Hash table for defining default logging locations


    #Sub Function to parse out logs into ArrayList
    Function ParseLog
    {
            
        param(
        $UserFilter,
        [string[]]$Server,
        $LogStart,
        $LogEnd,
        $Directory,
        $Protocol,
        $ResultsPerServer)
        
        $ServerResults = Invoke-Command -ComputerName $Server -ScriptBlock{
        #Determine Directory
        #Hash table mapping protocol to folder path
        $dirmap = @{
            "EAS"="Logging\HttpProxy\Eas";
            "AutoDiscover"="Logging\HttpProxy\Autodiscover";
            "ECP"="Logging\HttpProxy\Ecp";
            "EWS"="Logging\HttpProxy\EWS";
            "MAPI"="Logging\HttpProxy\Mapi";
            "OWA"="Logging\HttpProxy\Owa";
            "OA"="Logging\HttpProxy\RpcHttp"
            }       
        $installpath = $env:ExchangeInstallPath
        #Check for logging in default location based on install directory
        $directory = $installpath + $dirmap.$using:Protocol
        $dirtest = Test-Path $directory
        if($dirtest -eq $true)
        {
            Write-Verbose "Discover Directory $($directory) for Protocol $($protocol) on Server $($Server)"
        }
        else
        {
            Write-Error -Message "Unable to Determine Log Directory for Protocol $($Protocol) on Server $($Server)"
            continue
        }
        #Enumerate Logs to be Parsed
        $logs = Get-ChildItem *.Log -Path $Directory
        $logs = $logs | Where-Object {$_.LastWriteTime -ge $using:LogStart}
        $logs = $logs | Where-Object {$_.LastWriteTime -le $using:LogEnd}
        $logs = $logs | Sort-Object LastWriteTime -Descending
        #Start parsing logs
        $remoteresults = New-Object System.Collections.ArrayList
            foreach($l in $logs)
            {
                        try
                        {
                            $failed = $false
                            $reader = New-Object System.IO.StreamReader $l.FullName -ErrorAction Stop
                        }
                        catch
                        {
                            $failed = $true
                        }
                        If($failed -eq $true)
                        {
                            continue
                        }
                        #Read first line to create a header map hash table
                        $firstline = $reader.ReadLine()
                        $headermap = @{}
                        $headers = $firstline -split ","
                        foreach($h in $headers)
                        {
                        $headermap.Add($headers.IndexOf($h),$h)
                        }
                        #Determine the index value for our important properties (Only Auth User for now)
                        $authindex = ($headermap.GetEnumerator() | ?{$_.value -eq "AuthenticatedUser"}).Name
                        #Skip next 4 lines as they are commented
                        foreach ($n in 0..4)
                        {
                            [void]$reader.ReadLine()
                        }
                    
                        #StreamReader Technique - This is fast at going through each file - Decidining between this method, and simply using Import-CSV and PipeLine filter

                        #Create loop for each log directory. Limit total results per server to 200 by default
                        while ($reader.EndOfStream -ne $true -and $remoteresults.count -le ($using:ResultsPerServer -1))
                        {
                        #Filter each line as we read it. This adds processing time, but should keep objects small in memory
                        $line = $reader.ReadLine()
                        $linesplit = $line -split ","
                        #Build a PSObject for storing log fields as properties
                            if($linesplit[$($authindex)] -match $userfilter)
                            {
                                $resultout = New-Object PSObject
                                $index = 0
                                foreach($s in $linesplit)
                                {
                                    $resultout | Add-Member -MemberType NoteProperty -Name $headermap.$($index) -Value $s
                                    $index++
                                }
                                [void]$RemoteResults.Add($resultout)
                            }
                        }
                }
                return $remoteresults
            }
    return $ServerResults
    }

    #Execute code

    $logresults = ParseLog -UserFilter $UserFilter -Server $Server -LogStart $Logstart -LogEnd $LogEnd -Directory $Directory -ResultsPerServer $ResultSizePerServer -Protocol $Protocol
    return $logresults      
}



