<#
.VERSION
1.0.5

.SYNOPSIS
Setup applications in a Service Fabric cluster Azure Active Directory tenant.

.PREREQUISITE
1. An Azure Active Directory tenant.
2. A Global Admin user within tenant.

.PARAMETER TenantId
ID of tenant hosting Service Fabric cluster.

.PARAMETER WebApplicationName
Name of web application representing Service Fabric cluster.

.PARAMETER WebApplicationUri
App ID URI of web application.

.PARAMETER WebApplicationReplyUrl
Reply URL of web application. Format: https://<Domain name of cluster>:<Service Fabric Http gateway port>

.PARAMETER NativeClientApplicationName
Name of native client application representing client.

.PARAMETER ClusterName
A friendly Service Fabric cluster name. Application settings generated from cluster name: WebApplicationName = ClusterName + "_Cluster", NativeClientApplicationName = ClusterName + "_Client"

.PARAMETER Location
Used to set metadata for specific region (for example: china, germany). Ignore it in global environment.

.PARAMETER AddResourceAccess
Used to add the cluster application's resource access to "Windows Azure Active Directory" application explicitly when AAD is not able to add automatically. This may happen when the user account does not have adequate permission under this subscription.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup tenant with default settings generated from a friendly cluster name.

.EXAMPLE
. Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -WebApplicationName 'SFWeb' -WebApplicationUri 'https://SFweb' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080' -NativeClientApplicationName 'SFnative'

Setup tenant with explicit application settings.

.EXAMPLE
. $ConfigObj = Scripts\SetupApplications.ps1 -TenantId '4f812c74-978b-4b0e-acf5-06ffca635c0e' -ClusterName 'MyCluster' -WebApplicationReplyUrl 'https://mycluster.westus.cloudapp.azure.com:19080'

Setup and save the setup result into a temporary variable to pass into SetupUser.ps1
#>

Param
(
    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $TenantId,

    [Parameter(ParameterSetName = 'Customize')]	
    [String]
    $WebApplicationName,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [String]
    $WebApplicationUri,

    [Parameter(ParameterSetName = 'Customize', Mandatory = $true)]
    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $WebApplicationReplyUrl,
	
    [Parameter(ParameterSetName = 'Customize')]
    [String]
    $NativeClientApplicationName,

    [Parameter(ParameterSetName = 'Prefix', Mandatory = $true)]
    [String]
    $ClusterName,

    [Parameter(ParameterSetName = 'Prefix')]
    [Parameter(ParameterSetName = 'Customize')]
    [ValidateSet('us', 'china')]
    [String]
    $Location,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $AddResourceAccess,

    [Parameter(ParameterSetName = 'Prefix')]
    [Parameter(ParameterSetName = 'Customize')]
    [ValidateSet('AzureADMyOrg', 'AzureADMultipleOrgs','AzureADandPersonalMicrosoftAccount','PersonalMicrosoftAccount')]
    [String]
    $signInAudience = 'AzureADMyOrg'
)

Write-Host 'TenantId = ' $TenantId

. "$PSScriptRoot\Common.ps1"

$graphAdResource = '00000002-0000-0000-c000-000000000000'
$graphResource = '00000003-0000-0000-c000-000000000000'
$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}" #api-version=1.5"
$ConfigObj = @{}
$ConfigObj.TenantId = $TenantId

$appRoles = @(
    @{
        allowedMemberTypes = @("User")
        description        = "ReadOnly roles have limited query access"
        displayName        = "ReadOnly"
        id                 = [guid]::NewGuid()
        isEnabled          = "true"
        value              = "User"
    },
    @{
        allowedMemberTypes = @("User")
        description        = "Admins can manage roles and perform all task actions"
        displayName        = "Admin"
        id                 = [guid]::NewGuid()
        isEnabled          = "true"
        value              = "Admin"
    }
)

$requiredResourceAccess = @(
    @{
        resourceAppId  = $graphResource #$graphAdResource
        resourceAccess = @(@{
                id   = "e1fe6dd8-ba31-4d61-89e7-88639da4683d" #"311a71cc-e848-46a1-bdf8-97ff7156d8e6"
                type = "Scope"
            })
    }
)

if (!$WebApplicationName) {
    $WebApplicationName = "ServiceFabricCluster"
}

if (!$WebApplicationUri) {
    $WebApplicationUri = "https://ServiceFabricCluster"
}

if (!$NativeClientApplicationName) {
    $NativeClientApplicationName = "ServiceFabricClusterNativeClient"
}

$oauth2PermissionScopes = @(
    @{
        id                      = [guid]::NewGuid()
        isEnabled               = $true
        type                    = "User"
        adminConsentDescription = "Allow the application to access $WebApplicationName on behalf of the signed-in user."
        adminConsentDisplayName = "Access $WebApplicationName"
        userConsentDescription  = "Allow the application to access $WebApplicationName on your behalf."
        userConsentDisplayName  = "Access $WebApplicationName"
        value                   = "user_impersonation"
    }
)

Write-Host 'creating web application' -ForegroundColor Magenta
$uri = [string]::Format($graphAPIFormat, "applications")
$appRegistration = @{
    appRoles       = $appRoles
    signInAudience = $signInAudience
}

if ($AddResourceAccess) {
    $appRegistration += @{requiredResourceAccess = $requiredResourceAccess }
}

$webApp = [hashtable]::new($appRegistration)
$webApp += @{
    displayName    = $WebApplicationName
    identifierUris = @($WebApplicationUri)
    web            = @{
        homePageUrl           = $WebApplicationReplyUrl #Not functionally needed. Set by default to avoid AAD portal UI displaying error
        redirectUris          = @($WebApplicationReplyUrl)
        implicitGrantSettings = @{
            enableAccessTokenIssuance = $false
            enableIdTokenIssuance     = $true
        }
    }
}

$webApp = CallGraphAPI $uri $headers $webApp
AssertNotNull $webApp'Web Application Creation Failed'
$ConfigObj.WebAppId = $webApp.appId
Write-Host "Web Application Created:`r`n$($webApp| convertto-json -depth 99)" -ForegroundColor Green

Write-Host 'adding user_impersonation_scope' -ForegroundColor Magenta
$patchApplicationUri = $graphAPIFormat -f ("applications/{0}" -f $webApp.Id)
$webApp.api.oauth2PermissionScopes = $oauth2PermissionScopes

CallGraphAPI -uri $patchApplicationUri -method "Patch" -headers $headers -body @{ 
    api = $webApp.api
}

#Service Principal
Write-Host 'adding servicePrincipal web app' -ForegroundColor Magenta
$uri = [string]::Format($graphAPIFormat, "servicePrincipals")
$servicePrincipalWebApp = @{
    accountEnabled            = "true"
    appId                     = $webApp.appId
    displayName               = $webApp.displayName
    appRoleAssignmentRequired = "true"
}
$servicePrincipalWebApp = CallGraphAPI $uri $headers $servicePrincipalWebApp
$ConfigObj.ServicePrincipalWebApp = $servicePrincipalWebApp.Id

#Create Native Client Application
Write-Host 'creating native client application' -ForegroundColor Magenta
$uri = [string]::Format($graphAPIFormat, "applications")

$nativeApp = [hashtable]::new($appRegistration)
$nativeApp += @{
    displayName  = $NativeClientApplicationName
    publicClient = @{redirectUris = @('http://localhost') }
}

$nativeApp = CallGraphAPI $uri $headers $nativeApp
AssertNotNull $nativeApp 'Native Client Application Creation Failed'
Write-Host 'Native Client Application Created:' $nativeApp.appId
$ConfigObj.NativeClientAppId = $nativeApp.appId

Write-Host 'adding user_impersonation_scope' -ForegroundColor Magenta
$patchApplicationUri = $graphAPIFormat -f ("applications/{0}" -f $nativeApp.Id)
$nativeApp.api.oauth2PermissionScopes = $oauth2PermissionScopes
CallGraphAPI -uri $patchApplicationUri -method "Patch" -headers $headers -body @{ 
    api = $nativeApp.api
}

#Service Principal
Write-Host 'adding servicePrincipal native app' -ForegroundColor Magenta
$uri = [string]::Format($graphAPIFormat, "servicePrincipals")
$servicePrincipalNativeApp = @{
    accountEnabled = $true
    appId          = $nativeApp.appId
    displayName    = $nativeApp.displayName
}
$servicePrincipalNativeApp = CallGraphAPI $uri $headers $servicePrincipalNativeApp
$ConfigObj.ServicePrincipalNativeApp = $servicePrincipalNativeApp.Id

#OAuth2PermissionGrant

#AAD service principal
Write-Host 'adding aad servicePrincipal' -ForegroundColor Magenta
$uri = [string]::Format($graphAPIFormat, "servicePrincipals") + "?`$filter=appId eq '$graphResource'"
write-host "$uri" -ForegroundColor Cyan
$AADServicePrincipalId = (Invoke-RestMethod $uri -Headers $headers).value.appId
write-host "aadServicePrincipalId $($AADServicePrincipalId|out-string)"

$uri = [string]::Format($graphAPIFormat, "oauth2PermissionGrants")
$oauth2PermissionGrants = @{
    clientId    = $servicePrincipalNativeApp.Id
    consentType = "AllPrincipals"
    resourceId  = $AADServicePrincipalId
    scope       = "User.Read"
    startTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    expiryTime  = (Get-Date).AddYears(1800).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
}
CallGraphAPI $uri $headers $oauth2PermissionGrants | Out-Null

$oauth2PermissionGrants = @{
    clientId    = $servicePrincipalNativeApp.Id
    consentType = "AllPrincipals"
    resourceId  = $servicePrincipalWebApp.Id
    scope       = "user_impersonation"
    startTime   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
    expiryTime  = (Get-Date).AddYears(1800).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffffff")
}
CallGraphAPI $uri $headers $oauth2PermissionGrants | Out-Null

$ConfigObj

Write-Host 'creating arm template' -ForegroundColor Magenta
Write-Host '-----ARM template-----' -ForegroundColor Yellow
$armTemplate = @{
    azureActiveDirectory = @{
        tenantId           = $configobj.TenantId
        clusterApplication = $configobj.WebAppId
        clientApplication  = $configobj.NativeClientAppId
    }
}
Write-Host ($armTemplate | convertto-json -depth 5) -ForegroundColor White
