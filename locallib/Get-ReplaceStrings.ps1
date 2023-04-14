function Get-ReplaceStrings {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
        [PSCustomObject]$Replacements
    )

    #We need an ordered replace strings!
    $result = [ordered]@{}

    $domain = Get-ADDomain -Current LoggedOnUser
    $result.Add("DNSroot",$domain.DNSroot)
    $result.Add("DomainSID",$domain.DomainSID)

    if ([string]::isNullOrEmpty($result["DomainLDAP"])) {
        #$rootDSE = [adsi]"LDAP://rootDSE"    
        #$result["DomainLDAP"]=$rootDSE.defaultNamingContext
        $result["DomainLDAP"]=$domain.distinguishedName
    }
    
    if ([string]::isNullOrEmpty($result["Domain"])) {
        #Add backslash to domain name
        $result["Domain"]=$domain.NetBIOSName + "\"
    }
    
    if ([string]::isNullOrEmpty($result["CompanyName"])) {
        $result["CompanyName"]=$domain.Name
    }

    foreach( $property in $Replacements.psobject.properties.name )
    {
        $result[$property] = $Replacements.$property
    }
    
    return $result
}