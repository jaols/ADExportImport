  <#
.Synopsis
    Export AD-object from current AD tree
.DESCRIPTION
    Export AdObject to a target file. The file will be washed from local AD names.
.PARAMETER FileName
   	Filename to write result to.
.PARAMETER ExportUserProperties
	Attributes to include in export (normally part of json settings file)
.PARAMETER ExportGroupProperties
	Attributes to include in export (normally part of json settings file)
.PARAMETER ExportOUProperties
	Attributes to include in export (normally part of json settings file)
.PARAMETER ExportExcludeAttributes
	Any extra attributes to exclude from export (normally part of json settings file)
.PARAMETER Replacements
	Extra replacements to use for generic content creation (normally part of json settings file)
.PARAMETER Noreplace
	Skip all replacements. Generate file in raw format.
.PARAMETER IncludeAccess
	Include security settings for exported objects

.Notes
    Author: Jack Olsson 2023-08-02
    2023-08-11 - Bug corrections
    2024-04-02 Unified property function and ACL handling
    2024-11-25 Upgrade to PSJumpstart 2.0.0

.Example
    Get-AdUser -LDAPfilter "(cn=Jack*)" | Export-AdObjects.ps1 -Verbose

    Get all the Jacks in Active Directory

.Example
    Get-AdGroup -LDAPfilter "(name=APPL*)" | Export-AdObjects.ps1 -FileName "ApplicationGroups.json"

    Export all application groups to the ApplicationGroups.json file

.Example
    Get-ADGroup -LDAPFilter "(name=APPL*)" -Properties member | Select-Object -ExpandProperty member | Get-AdUser | .\Export-AdObjects.ps1 -FileName "ApplicationUsers.json"

    Export all members of application groups to the ApplicationUsers.json file
#>
[CmdletBinding(SupportsShouldProcess = $False)]
param (
    [Parameter(Mandatory = $true,
               ValuefromPipeline=$True)]               
    $AdObject,
    [string]$FileName,
    [string[]]$ExportUserProperties,
    [string[]]$ExportGroupProperties,
    [string[]]$ExportOuProperties,
    [string[]]$ExportExcludeAttributes,
    [PSCustomObject]$Replacements,
    [switch]$NoReplace,
    [switch]$IncludeAccess
)


Begin {
#Begin operations are run one time for pipeline processing

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
    if (-not (Get-Module PSJumpStart)) {
        Import-Module PSJumpStart -Force -MinimumVersion 2.0.0
    }
    
    #Get Local variable default values from external JSON-files
    Get-LocalDefaultVariables
    
    #Get global deafult settings when calling modules
    $PSDefaultParameterValues = Get-GlobalDefaultsFromJsonFiles $MyInvocation -Verbose:$VerbosePreference
    
    #endregion

    Msg "Start Execution"
    $ReplaceStrings=Get-ReplaceStrings $Replacements
    $ExportExcludeAttributes+=Get-StandardExludeAttributes -Export
    if ([string]::IsNullOrEmpty($FileName)) {
        $FileName=$scriptPath + "\" + $ReplaceStrings.CompanyName + ".ADobjects." + (Get-Date).ToString("yyyy-MM-dd") + ".json"
    }

    $ObjectList=[System.Text.StringBuilder]::new()
    [void]$ObjectList.AppendLine("{")
}


Process {
    #Process operations are run for each object in pipeline processing        
    Write-Verbose ("Process " + $AdObject + " [" + $AdObject.GetType().Name + "]")

    #Re-bind to object to get correct set of properties?
    switch ($AdObject.GetType().Name) 
    {
        "ADGroup" {
            $AdObject = Get-ADGroup -Identity $AdObject -Properties $ExportGroupProperties
            $FileName = $FileName -replace "ADobjects","ADGroups"
            break;
        }
        "ADOrganizationalUnit" {
            $AdObject = Get-ADOrganizationalUnit -Identity $AdObject -Properties $ExportOuProperties
            $FileName = $FileName -replace "ADobjects","ADUsers"
            break;
        }
        "ADUser" {
            $AdObject = Get-ADUser -Identity $AdObject -Properties $ExportUserProperties
            $FileName = $FileName -replace "ADobjects","OU"
            break;
        }
        Default {
            throw "Unsupported Active Directory object type [" + $AdObject.GetType().Name +"] in pipeline. Use Get-Help -Examples to get some tips."
            break;
        }
    }
    if (![string]::IsNullOrEmpty($AdObject.distinguishedName)) {
        $propHash = Convert-AdProps2Hash -AdObject $AdObject -ExportExcludeAttributes $ExportExcludeAttributes -IncludeAccess:$IncludeAccess

        [void]$ObjectList.Append('"')
        [void]$ObjectList.Append(($_.distinguishedName -replace "\\","\\"))
        [void]$ObjectList.Append('":')
        [void]$ObjectList.Append(($propHash | ConvertTo-Json -Depth 4 -Compress))
        [void]$ObjectList.AppendLine(',')
    }

}

End {
#End operations are run once in pipeline processing

    #Remove last ','
    [void]$ObjectList.Remove($ObjectList.Length-3,1)
    [void]$ObjectList.AppendLine("}")

    Write-Verbose ("Save " + $ObjectList.Count + " objects")
    Msg "Save data to $FileName"
    if ($NoReplace) {
        $ObjectList.ToString() | Out-File $FileName
    } else {
        $ObjectList.ToString() | ConvertTo-GenericStrings -ReplaceStrings $ReplaceStrings | Out-File $FileName        
    }
    
    Msg "End Execution"
}