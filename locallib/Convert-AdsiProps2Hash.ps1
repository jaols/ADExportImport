function Convert-AdsiProps2Hash {
param(
       [Parameter(ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName=$true)]
       $AdsiProperties,
       [string[]]$ExportExcludeAttributes,
       [switch]$IncludeAccess
    )
    $propHash = @{}

    foreach($property in $AdsiProperties.PropertyNames) {
        if ($ExportExcludeAttributes -notcontains $property) {
            #Only process readable props
            if (![string]::IsNullOrEmpty($AdsiProperties.$property)) {
                $value=$AdsiProperties.$property
                if ($value.Count -gt 1) {                    
                    $propHash.Add("$property|Microsoft.ActiveDirectory.Management.ADPropertyValueCollection", $value)
                } else {
                    $type=$value[0].GetType()
                    switch ($property) 
                    {
                        "ntsecuritydescriptor" {
                            if ($IncludeAccess) { 
                                $adSec = [System.DirectoryServices.ActiveDirectorySecurity]::new()
                                $adSec.SetSecurityDescriptorBinaryForm($value[0])

                                #We only save owner and ACL (No Audit support at this time as this would need a call to Get-Acl -audit)                          
                                $security = @{}
                                #$security.Add("Owner",($adSec.Owner -replace "\\","\\"))
                                $security.Add("Owner",$adSec.Owner)
                                
                                #Only save non-inherited ACE:s
                                $security.Add("Access",$adSec.Access.Where({!$_.IsInherited}))
                                
                                $propHash.Add("$property|" + $adSec.GetType().FullName, $security)
                            }
                            break
                        }
                        "grouptype" {                            
                            if ($value[0] -eq 2) {
                                #Global distribution group
                                $propHash.Add("GroupCategory|ADGroupCategory",0)
                                $propHash.Add("GroupScope|ADGroupScope",1)
                            }
                            if ($value[0] -eq 4) {
                                #Domain local distribution group
                                $propHash.Add("GroupCategory|ADGroupCategory",0)
                                $propHash.Add("GroupScope|ADGroupScope",0)
                            }
                            if ($value[0] -eq 8) {
                                #	
                                #Universal distribution group
                                $propHash.Add("GroupCategory|ADGroupCategory",0)
                                $propHash.Add("GroupScope|ADGroupScope",2)
                            }
                            if ($value[0] -eq -2147483646) {
                                #Global security group
                                $propHash.Add("GroupCategory|ADGroupCategory",1)
                                $propHash.Add("GroupScope|ADGroupScope",1)
                            }
                            if ($value[0] -eq -2147483644) {
                                #Domain local security group
                                $propHash.Add("GroupCategory|ADGroupCategory",1)
                                $propHash.Add("GroupScope|ADGroupScope",0)
                            }
                            if ($value[0] -eq -2147483640) {
                                #Universal security group
                                $propHash.Add("GroupCategory|ADGroupCategory",1)
                                $propHash.Add("GroupScope|ADGroupScope",2)
                            }
                            $propHash.Add("$property|" + $type.Name, $value[0])
                        }
                        default {
                            $propHash.Add("$property|" + $type.Name, $value[0])
                            break
                        }
                    }                                               
                }
            }
        }
    }

    return $propHash
}