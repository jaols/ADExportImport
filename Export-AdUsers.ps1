 <#
.Synopsis
    Export users from current AD tree
.DESCRIPTION
    Export users to a target file. The file will be washed from local AD names.
.PARAMETER FileName
   	Filename to write result to.
.PARAMETER LDAPfilter
   	Limit objects to export
.PARAMETER ExportPaths
	List of distinguished names to export (normally part of json settings file)
.PARAMETER ExportUserProperties
	Attributes to include in export (normally part of json settings file)
.PARAMETER ExportExcludeAttributes
	Any extra attributes to exclude from export (normally part of json settings file)
.PARAMETER Replacements
	Extra replacements to use for generic content creation (normally part of json settings file)
.PARAMETER NoReplace
	Save in raw format
.PARAMETER IncludeAccess
	Include security settings for exported objects

.Notes
    Author: Jack Olsson 2023-04-12
    
    2024-04-02 Unified property function and ACL handling
#>
[CmdletBinding(SupportsShouldProcess = $False)]
param (
    [string]$FileName,
    [string]$LDAPfilter,
    [string[]]$ExportPaths,
    [string[]]$ExportUserProperties,
    [string[]]$ExportExcludeAttributes,
    [PSCustomObject]$Replacements,
    [switch]$NoReplace,
    [switch]$IncludeAccess
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
    $FileName=$scriptPath + "\" + $ReplaceStrings.CompanyName + ".Users." + (Get-Date).ToString("yyyy-MM-dd") + ".json"
}


#$ObjectList=[ordered]@{}
$ObjectList=[System.Text.StringBuilder]::new()
[void]$ObjectList.AppendLine("{")

if ($ExportPaths) {
    foreach($Path in $ExportPaths) {        
        $Path=ConvertFrom-GenericStrings -InputObject $Path -ReplaceStrings $ReplaceStrings 

        Msg "Export objects from $Path"
        
        Get-ADUser -SearchBase $Path -SearchScope Subtree -Properties $ExportUserProperties -LDAPFilter $LDAPfilter | ForEach-Object {            
            Write-Verbose ("Process " + $_.distinguishedName)
            $propHash = Convert-AdProps2Hash -AdObject $_ -ExportExcludeAttributes $ExportExcludeAttributes -IncludeAccess:$IncludeAccess

            [void]$ObjectList.Append('"')
            [void]$ObjectList.Append(($_.distinguishedName -replace "\\","\\"))
            [void]$ObjectList.Append('":')
            [void]$ObjectList.Append(($propHash | ConvertTo-Json -Depth 4 -Compress))
            [void]$ObjectList.AppendLine(',')
                        
            #Exit
        }
    }
}
#Remove last ','
[void]$ObjectList.Remove($ObjectList.Length-3,1)
[void]$ObjectList.AppendLine("}")

Msg "Save data to $FileName"
if ($NoReplace) {
    $ObjectList.ToString() | Out-File $FileName
} else {   
    $ObjectList.ToString() | ConvertTo-GenericStrings -ReplaceStrings $ReplaceStrings -EscapeJson | Out-File $FileName
}



Msg "End Execution"