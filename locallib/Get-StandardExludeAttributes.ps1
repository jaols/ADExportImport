function Get-StandardExludeAttributes {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
        [switch]$Import,
        [switch]$Export
    )
    $result = @()

    if ($Import) {
        $result += ("Name",
        "CanonicalName",
        "ObjectGUID",
        "ou",
        "PropertyNames",        
        "dSCorePropagationData",
        "sAMAccountType",
        "objectClass",
        "objectCategory",
        "instanceType",
        "gPLink",
        "distinguishedName",
        "uSNCreated",
        "uSNChanged")
    }
    if ($Export) {
        #distinguishedName is used as object identifier in the export file
        $result += ("distinguishedName",
        "userCertificate",
        "badPasswordTime",        
        "logonCount",
        "lastLogon",
        "lastLogonTimestamp",
        "LastLogonDate",
        "LastBadPasswordAttempt",
        "PasswordLastSet",
        "pwdLastSet",
        "SID",
        "objectSid",        
        "msRTCSIP-Line",
        "CanonicalName",
        "ObjectGUID",
        "objectClass",
        "objectCategory",
        "instanceType",        
        "uSNCreated",
        "uSNChanged",
        "whenChanged",
        "whenCreated",
        "Created",
        "createTimeStamp",
        "Modified",
        "modifyTimeStamp",
        "PropertyCount",
        "ModifiedProperties",
        "RemovedProperties",
        "AddedProperties",
        "PropertyNames")
    }
    return $result
}