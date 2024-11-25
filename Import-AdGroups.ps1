 <#
.Synopsis
    Import users from file
.DESCRIPTION
    Import users
.PARAMETER ImportFile
   	File to read from
.PARAMETER ImportExcludeAttributes
   	Ad properties to exclude from import 
.PARAMETER SetProperties
	Use to set property values
.Notes
    Author: Jack Olsson    
    2024-04-02 Unified property function and ACL handling
    2024-11-25 Upgrade to PSJumpstart 2.0.0
#>
[CmdletBinding(SupportsShouldProcess = $True)]
param (    
    [string]$ImportFile,    
    [string[]]$ImportExcludeAttributes,    
    [PSCustomObject]$Replacements,
    [switch]$SetProperties
)

#region local functions 
function Get-LocalDefaultVariables {
    <#
   .Synopsis
       Load default arguemts for this PS-file.
   .DESCRIPTION
       Get setting files according to load order and set variables.
       Command prompt arguments will override any file settings.
   .PARAMETER defineNew
       Add ALL variables found in all setting files. This will get full configuration from all json files
   .PARAMETER overWriteExisting
       Turns the table for variable handling making file content override command line arguments.
   #>
   [CmdletBinding(SupportsShouldProcess = $False)]
   param(
       [switch]$defineNew,
       [switch]$overWriteExisting
   )
   foreach($settingsFile in (Get-SettingsFiles  ".json")) {        
       if (Test-Path $settingsFile) {        
           Write-Verbose "$($MyInvocation.Mycommand) reading: [$settingsFile]"
           $DefaultParamters = Get-Content -Path $settingsFile -Encoding UTF8 | ConvertFrom-Json | Set-ValuesFromExpressions
           ForEach($property in $DefaultParamters.psobject.properties.name) {
               #Exclude PSDefaultParameterValues ("functionName:Variable":"Value")
               if (($property).IndexOf(':') -eq -1) {
                   $var = Get-Variable $property -ErrorAction SilentlyContinue
                   $value = $DefaultParamters.$property
                   if (!$var) {
                       if ($defineNew) {
                           Write-Verbose "New Var: $property"
                           $var = New-Variable -Name  $property -Value $value -Scope 1
                       }
                   } else {
                       #We only overwrite non-set values if not forced
                       if (!($var.Value) -or $overWriteExisting)
                       {
                           try {                
                               Write-Verbose "Var: $property" 
                               $var.Value = $value
                           } Catch {
                               $ex = $PSItem
                               $ex.ErrorDetails = "Err adding $property from $settingsFile. " + $PSItem.Exception.Message
                               throw $ex
                           }
                       }
                   }
               }
           }
       } else {
           Write-Verbose "File not found: [$settingsFile]"
       }
   }
}
#endregion

#region Init
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
#Always load module
#if (-not (Get-Module PSJumpStart)) {
    Import-Module PSJumpStart -Force -MinimumVersion 2.0.0
#}

Import-Module ActiveDirectory

#Get Local variable default values from external JSON-files
Get-LocalDefaultVariables

#Get global deafult settings when calling modules
$PSDefaultParameterValues = Get-GlobalDefaultsFromJsonFiles $MyInvocation -Verbose:$VerbosePreference

#endregion

Msg "Start Execution"
Write-Verbose "Read data from $ImportFile"

$nameProperty="Name|String"
$ReplaceStrings=Get-ReplaceStrings $Replacements
$ImportExcludeAttributes+=Get-StandardExludeAttributes -Import

$ObjectList=Get-Content -Path $ImportFile -Raw | ConvertFrom-GenericStrings -ReplaceStrings $ReplaceStrings  #| ConvertFrom-Json 
$ObjectList=$ObjectList | ConvertFrom-Json 

foreach($objectItem in $ObjectList.psobject.properties.name) {
    Write-Verbose "Process $objectItem"
    $objectProperties=$ObjectList.$objectItem
    
    $targetObject = $null
    try {
        $targetObject = Get-ADObject -Identity $objectItem -Properties nTSecurityDescriptor -ErrorAction SilentlyContinue
    } catch {}    
    
    if (!$targetObject) {
        $parentOu = $objectItem | Get-ParentContainer

        if ($PSCmdlet.ShouldProcess($parentOu,"Create object " + $objectProperties.$nameProperty)) {
            Msg "Create $objectItem"
            try {
                #Create a virgin oobject
                New-ADGroup -Name $objectProperties.$nameProperty -Path $parentOu -GroupScope $objectProperties."GroupScope|ADGroupScope" -GroupCategory $objectProperties."GroupCategory|ADGroupCategory"
                $targetObject=$objectItem
            } catch {
                if ($PSItem.Exception.ErrorCode -eq 1318) {
                   $targetObject = Get-ADGroup -Identity $objectProperties.$nameProperty -Properties nTSecurityDescriptor -ErrorAction SilentlyContinue
                } else {
                    Msg ("Failed to create [" + $objectProperties.$nameProperty + "] in $parentOu. $PSItem") -Type ERROR
                    continue
                }

            }
        }
    }

    #Set parameters 
    if ($SetProperties) {
        Msg "Set properties for $targetObject"
        foreach($property in $objectProperties.psobject.properties.name) {
            $propertyName = $property.Split('|')[0]
            $typeName = $property.Split('|')[1]
            if ($ImportExcludeAttributes -notcontains $propertyName) {
                #Only process readable props
                if ($objectProperties.$property) {
                    $value = $objectProperties.$property -as ($typeName -as [type])
                    Write-Verbose "Set $property"
                    switch ($typeName) {
                        "System.DirectoryServices.ActiveDirectorySecurity" {
                            $value = $objectProperties.$property
                            $secDescriptor = $targetObject.$propertyName

                            if ($value.Owner.IndexOf(':') -gt 0) {
                               $ownerSid=[System.Security.Principal.SecurityIdentifier]$value.Owner.Split(':')[1] 
                               $secDescriptor.SetOwner($ownerSid)
                            } else {
                                $acc=[System.Security.Principal.NTAccount]$value.Owner
                                try {
                                    $ownerSid=$acc.Translate([System.Security.Principal.SecurityIdentifier])                                                            
                                    $secDescriptor.SetOwner($ownerSid)
                                } catch {
                                    Msg "Failed to set Owner [$($value.Owner)]. $PSItem" -Type WARNING   
                                }

                            }
                            
                            foreach($ace in $value.Access) {
                                    try {
                                        $sid=[System.Security.Principal.SecurityIdentifier]$ace.IdentityReference.Value
                                        
                                    } catch {
                                        $acc=[System.Security.Principal.NTAccount]$ace.IdentityReference.Value
                                        $sid=$acc.Translate([System.Security.Principal.SecurityIdentifier])
                                    }

                                    $rule = $secDescriptor.AccessRuleFactory(
                                        [System.Security.Principal.IdentityReference]$sid, 
                                        [int]$ace.ActiveDirectoryRights,
                                        [bool]$false,
                                        [System.Security.AccessControl.InheritanceFlags]$ace.InheritanceFlags,
                                        [System.Security.AccessControl.PropagationFlags]$ace.PropagationFlags,
                                        [System.Security.AccessControl.AccessControlType]$ace.AccessControlType
                                    )

                                    $secDescriptor.AddAccessRule($rule)
                            }

                            Set-ACL -Path "AD:$($targetObject.DistinguishedName)" $secDescriptor
                            
                            Break
                        }
                        Default {                            
                            #Cleanup member list according to existing objects
                            if ($propertyName -eq "member") {                                
                                #for (<Init>; <Condition>; <Repeat>)
                                Write-Verbose ("Members to set: " + $value.Count)
                                for ($n = $value.Count-1; $n -gt -1; $n--) {
                                    #Check if principal exists (member must exist in the correct OU)
                                    $principal = $null
                                    try {
                                        $principal = Get-ADObject -Identity $value[$n] -Properties Name
                                    } catch {}

                                    if (!$principal) {
                                        $value.RemoveAt($n)
                                    }
                                }
                                Write-Verbose ("Existing members: " + $value.Count)
                                if ($value.Count -eq 1) {
                                    $value = [string]$value[0]
                                }

                                Try {                                    
                                    Set-ADGroup -Identity $targetObject -Add @{$propertyName=[array]$value}
                                } Catch {
                                    Msg "Failed to set member list. $PSItem" -Type WARNING
                                }

                            } else {

                                Try {
                                    #Set property one-by-one at this stage
                                    Set-ADGroup -Identity $targetObject -Add @{$propertyName=$value}
                                } Catch {
                                    Msg "Failed to set [$propertyName]. $PSItem" -Type WARNING
                                }
                            }
                            Break
                        }
                    }
                }
            }
        }
    }
}

Msg "End Execution"