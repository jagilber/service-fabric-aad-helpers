﻿<#
.VERSION
1.0.4

.SYNOPSIS
Common script, do not call it directly.
#>

function main () {
    if ($headers) {
        return
    }

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

function assert-notNull($obj, $msg) {
    if ($obj -eq $null -or $obj.Length -eq 0) { 
        Write-Warning $msg
        exit
    }
}

function call-graphApi($uri, $headers, $body, $method = "Post") {
    try {
        $error.clear()
        $json = $body | ConvertTo-Json -Depth 99 -Compress
        write-host "Invoke-RestMethod $uri -Method $method -Headers $($headers | convertto-json) -Body $($body | convertto-json -depth 99)"
        return (Invoke-RestMethod $uri -Method $method -Headers $headers -Body $json)
    }
    catch {
        write-warning "call-graphApi exception:`r`n$($_.Exception.Message)`r`n$($error | out-string)"
        return $null
    }
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
    else {
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
    $authenticationContext = [Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext]::new($authString, $false)
    $promptBehavior = [Microsoft.IdentityModel.Clients.ActiveDirectory.PromptBehavior]::RefreshSession
    $platformParameters = [Microsoft.IdentityModel.Clients.ActiveDirectory.PlatformParameters]::new($promptBehavior)

    $accessToken = $authenticationContext.AcquireTokenAsync($resourceUrl, $clientId, $redirectUrl, $platformParameters).Result.AccessToken
    return $accessToken
}

function get-RESTHeadersCloud() { 
    # https://docs.microsoft.com/en-us/azure/cloud-shell/msi-authorization
    $response = invoke-webRequest -method post `
        -uri 'http://localhost:50342/oauth2/token' `
        -body "resource=$resourceUrl" `
        -header @{'metadata' = 'true' }

    write-host $response | convertto-json
    $token = ($response | convertfrom-json).access_token
    return $token
}

# Regional settings
switch ($Location) {
    "china" {
        $resourceUrl = "https://graph.chinacloudapi.cn"
        $authString = "https://login.partner.microsoftonline.cn/" + $TenantId
    }
    
    "us" {
        $resourceUrl = "https://graph.windows.net"
        $authString = "https://login.microsoftonline.us/" + $TenantId
    }

    default {
        $resourceUrl = "https://graph.microsoft.com"
        $authString = "https://login.microsoftonline.com/" + $TenantId
    }
}

$headers = main

if ($ClusterName) {
    $WebApplicationName = $ClusterName + "_Cluster"
    #$WebApplicationUri = "https://$ClusterName"
    $NativeClientApplicationName = $ClusterName + "_Client"
}
