 <#
.Synopsis
    Export OU structure from current AD tree
.DESCRIPTION
    Export OU structure to a target file. The file will be washed from local AD names.
.PARAMETER FileName
   	Filename to write result to.
.PARAMETER LDAPfilter
   	Limit objects to export
.PARAMETER ExportPaths
	List of distinguished names to export (normally part of json settings file)
.PARAMETER ExportOuProperties
	Attributes to include in export (normally part of json settings file)
.PARAMETER ExportExcludeAttributes
	Any extra attributes to exclude from export (normally part of json settings file)
.PARAMETER Replacements
	Extra replacements to use for generic content creation (normally part of json settings file)
.Notes
    Author: Jack Olsson 2023-04-06
    
#>
[CmdletBinding(SupportsShouldProcess = $False)]
param (
    [string]$FileName,
    [string]$LDAPfilter,
    [string[]]$ExportPaths,
    [string[]]$ExportOuProperties,
    [string[]]$ExportExcludeAttributes,
    [PSCustomObject]$Replacements,
    [switch]$NoReplace
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

if ([string]::IsNullOrEmpty($LDAPfilter)) {
    $LDAPfilter="(name=*)"
}

$ReplaceStrings=Get-ReplaceStrings $Replacements

$ExportExcludeAttributes+=Get-StandardExludeAttributes -Export

if ([string]::IsNullOrEmpty($FileName)) {
    $FileName=$scriptPath + "\" + $ReplaceStrings.CompanyName + ".OU." + (Get-Date).ToString("yyyy-MM-dd") + ".json"
}


$ObjectList=[ordered]@{}

if ($ExportPaths) {
    foreach($Path in $ExportPaths) {        
        $Path=ConvertFrom-GenericStrings -InputObject $Path -ReplaceStrings $ReplaceStrings 

        Msg "Export objects from $Path"
        
        Get-ADOrganizationalUnit -SearchBase $Path -SearchScope Subtree -Properties $ExportOuProperties -LDAPFilter $LDAPfilter | ForEach-Object {
            $propHash = @{}
            Write-Verbose ("Process " + $_.distinguishedName)
            foreach($property in $_.psobject.properties.name) {
                if ($ExportExcludeAttributes -notcontains $property) {
                    #Only process readable props
                    if (![string]::IsNullOrEmpty($_.$property)) {
                        $value=$_.$property
                        $type = $value.Gettype()
                        switch ($type.Name) 
                        {
                            "ActiveDirectorySecurity" {
                                #TODO: Improved support! Only add direct set ACE:s
                                #$propHash.Add("$property|" + $type.FullName, $value)
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
            $ObjectList.Add($_.distinguishedName,$propHash)
        }
    }
}

Msg "Save data to $FileName"
$ObjectList | ConvertTo-Json -Depth 5 -Compress | ConvertTo-GenericStrings -ReplaceStrings $ReplaceStrings  | Out-File $FileName


Msg "End Execution"