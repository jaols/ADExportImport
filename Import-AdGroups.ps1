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
                New-ADGroup -Name $objectProperties.$nameProperty -Path $parentOu -GroupScope $objectProperties."GroupScope|ADGroupScope" -GroupCategory $objectProperties."GroupCategory|ADGroupCategory"
                $targetObject=$objectItem
            } catch {
                if ($PSItem.Exception.ErrorCode -eq 1318) {
                   $targetObject = Get-ADGroup -Identity $objectProperties.$nameProperty -ErrorAction SilentlyContinue
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
                            #TODO: Fix support for this
                            #Only process new entries
                            Break
                        }
                        Default {                            
                            #Cleanup member list according to existing objects
                            if ($propertyName -eq "member") {                                
                                #for (<Init>; <Condition>; <Repeat>)
                                Write-Verbose ("Members to set: " + $value.Count)
                                for ($n = $value.Count-1; $n -gt -1; $n--) {
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
                            }

                            Try {
                                #Set property one-by-one at this stage
                                Set-ADGroup -Identity $targetObject -Add @{$propertyName=$value}
                            } Catch {
                                Msg "Failed to set [$propertyName]. $PSItem" -Type WARNING
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