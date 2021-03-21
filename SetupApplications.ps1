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
    [ValidateSet('china', 'germany')]
    [String]
    $Location,

    [Parameter(ParameterSetName = 'Customize')]
    [Parameter(ParameterSetName = 'Prefix')]
    [Switch]
    $AddResourceAccess
)

Write-Host 'TenantId = ' $TenantId

. "$PSScriptRoot\Common.ps1"

$graphAPIFormat = $resourceUrl + "/v1.0/" + $TenantId + "/{0}" #api-version=1.5"
$ConfigObj = @{}
$ConfigObj.TenantId = $TenantId
$userAppRoleId = [guid]::NewGuid()
$adminAppRoleId = [guid]::NewGuid()

$appRoles = @(@{
        allowedMemberTypes = @("User")
        description        = "ReadOnly roles have limited query access"
        displayName        = "ReadOnly"
        id                 = $userAppRoleId
        isEnabled          = "true"
        value              = "User"
    },
    @{
        allowedMemberTypes = @("User")
        description        = "Admins can manage roles and perform all task actions"
        displayName        = "Admin"
        id                 = $adminAppRoleId
        isEnabled          = "true"
        value              = "Admin"
    })

$requiredResourceAccess =
@(@{
        resourceAppId  = "00000002-0000-0000-c000-000000000000"
        resourceAccess = @(@{
                id   = "311a71cc-e848-46a1-bdf8-97ff7156d8e6"
                type = "Scope"
            })
    })

if (!$WebApplicationName) {
    $WebApplicationName = "ServiceFabricCluster"
}

if (!$WebApplicationUri) {
    $WebApplicationUri = "https://ServiceFabricCluster"
}

if (!$NativeClientApplicationName) {
    $NativeClientApplicationName = "ServiceFabricClusterNativeClient"
}

#Create Web Application
$uri = [string]::Format($graphAPIFormat, "applications")
$webApp = @{
    displayName    = $WebApplicationName
    identifierUris = @($WebApplicationUri)
    appRoles       = $appRoles
    web            = @{
        homePageUrl  = $WebApplicationReplyUrl #Not functionally needed. Set by default to avoid AAD portal UI displaying error
        redirectUris = @($WebApplicationReplyUrl)
    }
    publicClient   = @{redirectUris = @('http://localhost') }
}

if ($AddResourceAccess) {
    $webApp += @{requiredResourceAccess = $requiredResourceAccess }
}

$webApp = CallGraphAPI $uri $headers $webApp
AssertNotNull $webApp'Web Application Creation Failed'
$ConfigObj.WebAppId = $webApp.appId
Write-Host "Web Application Created:`r`n$($webApp| convertto-json -depth 99)" -ForegroundColor Green

# Check for an existing delegated permission with value "user_impersonation". Normally this is not created by default,
# but if it is, we need to update the Application object with a new one.
$user_impersonation_scope = $webApp.api.oauth2PermissionScopes | Where-Object { $_.value -eq "user_impersonation" }
if (-not $user_impersonation_scope) {
    Write-Host 'adding user_impersonation_scope'
    $patchApplicationUri = $graphAPIFormat -f ("applications/{0}" -f $webApp.Id)
    #$webApp.oauth2Permissions = @($webAppoauth2Permissions)
    $webApp.api.oauth2PermissionScopes = @(@{
            "id"                      = [guid]::NewGuid()
            "isEnabled"               = $true
            "type"                    = "User"
            "adminConsentDescription" = ("Allow the application to access {0} on behalf of the signed-in user." -f $WebApplicationName)
            "adminConsentDisplayName" = ("Access {0}" -f $WebApplicationName)
            "userConsentDescription"  = ("Allow the application to access {0} on your behalf." -f $WebApplicationName)
            "userConsentDisplayName"  = ("Access {0}" -f $WebApplicationName)
            "value"                   = "user_impersonation"
        })

    CallGraphAPI -uri $patchApplicationUri -method "Patch" -headers $headers -body @{ 
        "api" = $webApp.api
    }
}

#Service Principal
Write-Host 'adding servicePrincipal 1'
$uri = [string]::Format($graphAPIFormat, "servicePrincipals")
$servicePrincipalWebApp = @{
    accountEnabled            = "true"
    appId                     = $webApp.appId
    displayName               = $webApp.displayName
    appRoleAssignmentRequired = "true"
}
$servicePrincipalWebApp = CallGraphAPI $uri $headers $servicePrincipalWebApp
$ConfigObj.ServicePrincipalWebApp = $servicePrincipalWebApp.Id

# #Create Native Client Application
# Write-Host 'creating native client application'
# $uri = [string]::Format($graphAPIFormat, "applications")
# $nativeAppResourceAccess = $requiredResourceAccess +=
# @{
#     resourceAppId  = $webApp.appId
#     resourceAccess = @(@{
#             id   = $webApp.api.oauth2PermissionScopes[0].id
#             type = "Scope"
#         })
# }
# $nativeApp = @{
#     publicClient           = "true"
#     displayName            = $NativeClientApplicationName
#     replyUrls              = @("http://localhost") #@("urn:ietf:wg:oauth:2.0:oob")
#     requiredResourceAccess = $nativeAppResourceAccess
# }
# $nativeApp = CallGraphAPI $uri $headers $nativeApp
# AssertNotNull $nativeApp 'Native Client Application Creation Failed'
# Write-Host 'Native Client Application Created:' $nativeApp.appId
# $ConfigObj.NativeClientAppId = $nativeApp.appId

#Service Principal
# Write-Host 'adding servicePrincipal 2'
# $uri = [string]::Format($graphAPIFormat, "servicePrincipals")
# $servicePrincipalNativeApp = @{
#     accountEnabled = "true"
#     appId          = $nativeApp.appId
#     displayName    = $nativeApp.displayName
# }
# $servicePrincipalNativeApp = CallGraphAPI $uri $headers $servicePrincipalNativeApp
# $ConfigObj.ServicePrincipalNativeApp = $servicePrincipalNativeApp.Id

#OAuth2PermissionGrant

#AAD service principal
Write-Host 'adding aad servicePrincipal'
$uri = [string]::Format($graphAPIFormat, "servicePrincipals") + '&$filter=appId eq ''00000002-0000-0000-c000-000000000000'''
$AADServicePrincipalId = (Invoke-RestMethod $uri -Headers $headers).value.objectId

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

Write-Host 'creating arm template'
#ARM template
Write-Host
Write-Host '-----ARM template-----'
Write-Host '"azureActiveDirectory": {'
Write-Host ("  `"tenantId`":`"{0}`"," -f $ConfigObj.TenantId)
Write-Host ("  `"clusterApplication`":`"{0}`"," -f $ConfigObj.WebAppId)
Write-Host ("  `"clientApplication`":`"{0}`"" -f $ConfigObj.NativeClientAppId)
Write-Host "},"
