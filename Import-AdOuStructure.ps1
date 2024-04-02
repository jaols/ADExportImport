 <#
.Synopsis
    Import OU structure from current AD tree
.DESCRIPTION
    Export OU structure to 
.PARAMETER aa
   	First mandatory string argument.
.PARAMETER arg2
   	Second optional string argument.
.PARAMETER flag
	Switch parameter check with if ($flag:IsPresent) {}
.Notes
    Author: Jack Olsson
    Changes:
    2024-04-02 Unified property function and ACL handling
#>
[CmdletBinding(SupportsShouldProcess = $True)]
param (    
    [string]$ImportFile,    
    [string[]]$ImportExcludeAttributes,
    [PSCustomObject]$Replacements,
    [switch]$SetProperties
)

#region local functions 

#Load default arguemts for this script.
#Command prompt arguments will override file settings
function Get-LocalDefaultVariables {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
        [parameter(Position=0,mandatory=$true)]
        $CallerInvocation,
        [switch]$defineNew,
        [switch]$overWriteExisting
    )
    foreach($settingsFile in (Get-SettingsFiles $CallerInvocation ".json")) {        
        if (Test-Path $settingsFile) {        
            Write-Verbose "Reading file: [$settingsFile]"
            $DefaultParamters = Get-Content -Path $settingsFile -Encoding UTF8 | ConvertFrom-Json
            ForEach($prop in $DefaultParamters | Get-Member -MemberType NoteProperty) {        
                
                if (($prop.Name).IndexOf(':') -eq -1) {
                    $key=$prop.Name
                    $var = Get-Variable $key -ErrorAction SilentlyContinue
                    $value = $DefaultParamters.($prop.Name)                    
                    if (!$var) {
                        if ($defineNew) {
                            Write-Verbose "New Var: $key" 
                            if ($value.GetType().Name -eq "String" -and $value.SubString(0,1) -eq '(') {
                                $var = New-Variable -Name  $key -Value (Invoke-Expression $Value) -Scope 1
                            } else {
                                $var = New-Variable -Name  $key -Value $value -Scope 1
                            }
                        }
                    } else {

                        #We only overwrite non-set values if not forced
                        if (!($var.Value) -or $overWriteExisting)
                        {
                            try {                
                                Write-Verbose "Var: $key" 
                                if ($value.GetType().Name -eq "String" -and $value.SubString(0,1) -eq '(') {
                                    $var.Value = Invoke-Expression $value
                                } else {
                                    $var.Value = $value
                                }
                            } Catch {
                                $ex = $PSItem
                                $ex.ErrorDetails = "Err adding $key from $settingsFile. " + $PSItem.Exception.Message
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
    Import-Module PSJumpStart -Force -MinimumVersion 1.2.6
#}

Import-Module ActiveDirectory

#Get Local variable default values from external DFP-files
Get-LocalDefaultVariables($MyInvocation)

#Get global deafult settings when calling modules
$PSDefaultParameterValues = Get-GlobalDefaultsFromJsonFiles $MyInvocation -Verbose:$VerbosePreference

#endregion

Msg "Start Execution"

Write-Verbose "Read data from $ImportFile"

$nameProperty="Name|String"
$ReplaceStrings=Get-ReplaceStrings $Replacements
$ImportExcludeAttributes+=Get-StandardExludeAttributes -Import

$ObjectList=Get-Content -Path $ImportFile -Raw | ConvertFrom-GenericStrings -ReplaceStrings $ReplaceStrings  | ConvertFrom-Json 

foreach($objectItem in $ObjectList.psobject.properties.name) {
    Write-Verbose "Process $objectItem"
    $objectProperties=$ObjectList.$objectItem
    
    $targetObject = $null
    try {
        $targetObject = Get-ADObject -Identity $objectItem -ErrorAction SilentlyContinue
    } catch {}    
    
    if (!$targetObject) {
        $parentOu = $objectItem | Get-ParentContainer

        if ($PSCmdlet.ShouldProcess($parentOu,"Create object " + $objectProperties.$nameProperty)) {
            Msg "Create $objectItem"
            try {
                #Create a virgin oobject
                New-ADOrganizationalUnit -Name $objectProperties.$nameProperty -Path $parentOu
                $targetObject=$objectItem
            } catch {
                Msg ("Failed to create [" + $objectProperties.$nameProperty + "] in $parentOu. $PSItem") -Type ERROR
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
                            Try {
                                #Set property one-by-one at this stage
                                Set-ADOrganizationalUnit -Identity $targetObject -Replace @{$propertyName=$value}
                            } Catch {
                                Msg "Failed to set [$property]. $PSItem" -Type WARNING
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