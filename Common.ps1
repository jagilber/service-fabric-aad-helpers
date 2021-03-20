<#
.VERSION
1.0.4

.SYNOPSIS
Common script, do not call it directly.
#>

function logon-msal() {
    write-host "msal importing msal-logon script"
    . "$PSScriptRoot\msal-logon.ps1"
    if (!$global:msal) {
        Write-error "error getting token."
    }

    write-host "msal requesting authorization"
    #$global:msal.Logon($resourceUrl, @("https://graph.microsoft.com//user_impersonation","https://graph.microsoft.com//Directory.Read","https://graph.microsoft.com//Directory.Write"))
    $global:msal.Logon($resourceUrl, @("https://graph.microsoft.com//user_impersonation")) #,"https://graph.microsoft.com//Directory.Read","https://graph.microsoft.com//Directory.Write"))
    $msalResults = $global:msal.authenticationResult
    write-host "msal results $($msalResults | convertto-json)"
    return $msalResults
}

function GetRESTHeaders($msalResults) {
    $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
    $headers.Add("Authorization", "Bearer $($msalResults.accessToken)")
    return $headers
}

function CallGraphAPI($uri, $headers, $body, $method = "Post") {
    write-host "CallGraphAPI($uri, $($headers|convertto-json), $($body|convertto-json), $method = 'Post'"
    $json = $body | ConvertTo-Json -Depth 4 -Compress
    return (Invoke-RestMethod $uri -Method $method -Headers $headers -Body $json -ContentType "application/json")
}

function AssertNotNull($obj, $msg) {
    if ($obj -eq $null -or $obj.Length -eq 0) { 
        Write-Warning $msg
        Exit
    }
}

# Regional settings
switch ($Location) {
    "china" {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.partner.microsoftonline.cn/" + $TenantId
    }
    
    "germany" {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.microsoftonline.de/" + $TenantId   
    }

    default {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.microsoftonline.com/" + $TenantId
    }
}

$headers = GetRESTHeaders -msalResults (logon-msal)

if ($ClusterName) {
    $WebApplicationName = $ClusterName + "_Cluster"
    $WebApplicationUri = "https://$ClusterName"
    $NativeClientApplicationName = $ClusterName + "_Client"
}
