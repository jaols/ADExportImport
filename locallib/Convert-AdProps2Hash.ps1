function Convert-Adprops2Hash {
param(
       [Parameter(ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName=$true)]
       $AdObject,
       [string[]]$ExportExcludeAttributes,
       [switch]$IncludeAccess
    )
    $propHash = @{}

    foreach($property in $AdObject.psobject.properties.name) {
        if ($ExportExcludeAttributes -notcontains $property) {
            #Only process readable props
            if (![string]::IsNullOrEmpty($AdObject.$property)) {
                $value=$AdObject.$property
                $type = $value.Gettype()
                switch ($type.Name) 
                {
                    "ActiveDirectorySecurity" {
                        if ($IncludeAccess) {
                            #We only save owner and ACL (No Audit support at this time as this would need a call to Get-Acl -audit)                          
                            $security = @{}
                            $security.Add("Owner",($value.Owner -replace "\\","\\\\"))
                            
                            #Only save non-inherited ACE:s
                            $security.Add("Access",$value.Access.Where({!$_.IsInherited}))
                            
                            $propHash.Add("$property|" + $type.FullName, $security)
                        }
                        break;
                    }
                    "ADPropertyValueCollection" {
                        $propHash.Add("$property|" + $type.FullName, $value)
                    }
                    default {
                        $propHash.Add("$property|" + $type.Name, $value)
                        break
                    }                            
                }
            }
        }
    }

    return $propHash
}