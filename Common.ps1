<#
.VERSION
1.0.4

.SYNOPSIS
Common script, do not call it directly.
#>

function main () {
    try {
        # Install latest AD client library
        # check for cloudshell https://shell.azure.com

        if (!(get-cloudInstance)) {
            $nuget = "nuget.exe"
            if (!(test-path $nuget)) {
                $nugetDownloadUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
                invoke-webRequest $nugetDownloadUrl -outFile $nuget
            }

            $env:path = $env:path.replace(";$pwd;", "") + ";$pwd;"
            $ADPackage = "Microsoft.IdentityModel.Clients.ActiveDirectory"
            & nuget.exe install $ADPackage > nuget.log

            # Target .NET Framework version of the DLL
            $FilePath = (Get-Item .\\Microsoft.IdentityModel.Clients.ActiveDirectory.[0-9].[0-9].[0-9]\\lib\\net[0-9][0-9]\\Microsoft.IdentityModel.Clients.ActiveDirectory.dll).FullName | Resolve-Path -Relative
            Add-Type -Path $FilePath
        }
    }
    catch {
        Write-Warning $_.Exception.Message
    }

    return get-RESTHeaders
}

function get-cloudInstance() {
    $isCloudInstance = $PSVersionTable.Platform -ieq 'unix' -and ($env:ACC_CLOUD)
    write-host "cloud instance: $isCloudInstance"
    return $isCloudInstance
}

function get-RESTHeaders() {
    # Use common client 
    $clientId = "1950a258-227b-4e31-a9cf-717495945fc2"
    $redirectUrl = "urn:ietf:wg:oauth:2.0:oob"
    
    if (get-cloudInstance) {
        $token = get-RESTHeadersCloud
    }
    elseif($psedition -ieq 'core') {
        $token = get-RESTHeadersMSAL
    }
    else{
        $token = get-RESTHeadersADAL
    }
    
    $authHeader = @{
        'Content-Type'  = 'application/json'
        'Authorization' = 'Bearer ' + $token
    }

    write-host "auth header: $($authHeader | convertto-json)"
    return $authHeader
}

function get-RESTHeadersADAL() {
    write-host "getting oauth token from ADAL"
    $authenticationContext = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext -ArgumentList $authString, $FALSE
    
    $PromptBehavior = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::RefreshSession
    $PlatformParameters = New-Object Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters -ArgumentList $PromptBehavior
    $accessToken = $authenticationContext.AcquireTokenAsync($resourceUrl, $clientId, $redirectUrl, $PlatformParameters).Result.AccessToken
    return $accessToken
}

function get-RESTHeadersCloud() { 
    # https://docs.microsoft.com/en-us/azure/cloud-shell/msi-authorization
    write-host "getting oauth token from cloud shell"
    write-host "
    $response = invoke-webRequest -method post ``
        -uri 'http://localhost:50342/oauth2/token' ``
        -body `"resource=$resourceUrl`" ``
        -header @{'metadata' = 'true' }
    "

    $response = invoke-webRequest -method post `
        -uri 'http://localhost:50342/oauth2/token' `
        -body "resource=$resourceUrl" `
        -header @{'metadata' = 'true' }

    write-host $response | convertto-json
    $token = ($response | convertfrom-json).access_token
    return $token
}

function get-RESTHeadersMSAL() {
    write-host "getting oauth token from MSAL"
    write-host "msal importing msal-logon script"
    . "$PSScriptRoot\azure-msal-logon.ps1"
    if (!$global:msal) {
        Write-error "error getting token."
    }

    write-host "msal requesting authorization"
    #$global:msal.Logon($resourceUrl, @("https://graph.microsoft.com//user_impersonation","https://graph.microsoft.com//Directory.Read","https://graph.microsoft.com//Directory.Write"))
    $global:msal.Logon($resourceUrl, @("https://graph.microsoft.com/user_impersonation",
        "https://graph.microsoft.com/application.read+write+all",
        "https://graph.microsoft.com/directory.read+write+all",        
        "https://graph.microsoft.com/accessasuser+all"))
    $msalResults = $global:msal.authenticationResult
    write-host "msal results $($msalResults | convertto-json)"
    return $msalResults
}

function CallGraphAPI($uri, $headers, $body, $method = "Post") {
    write-host "CallGraphAPI($uri, $($headers|convertto-json), $($body|convertto-json), $method = 'Post'"  -ForegroundColor Cyan
    $json = $body | ConvertTo-Json -Depth 4 -Compress
    $result = Invoke-RestMethod $uri -Method $method -Headers $headers -Body $json -ContentType "application/json"
    write-host ($result | convertto-json -depth 5) -ForegroundColor Magenta
    return $result
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
    
    "us" {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.microsoftonline.us/" + $TenantId
    }

    default {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.microsoftonline.com/" + $TenantId
    }
}

if ($ClusterName) {
    $WebApplicationName = $ClusterName + "_Cluster"
    #$WebApplicationUri = "https://$ClusterName"
    $NativeClientApplicationName = $ClusterName + "_Client"
}

main