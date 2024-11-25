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
    2024-11-25 Upgrade to PSJumpstart 2.0.0
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