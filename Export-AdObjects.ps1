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

.Notes
    Author: Jack Olsson 2023-08-02

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
    [switch]$NoReplace
)


Begin {
#Begin operations are run one time for pipeline processing

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
    if (-not (Get-Module PSJumpStart)) {
        Import-Module PSJumpStart -Force -MinimumVersion 1.2.0
    }
    
    #Get Local variable default values from external DFP-files
    Get-LocalDefaultVariables($MyInvocation)
    
    #Get global deafult settings when calling modules
    $PSDefaultParameterValues = Get-GlobalDefaultsFromJsonFiles $MyInvocation -Verbose:$VerbosePreference
    
    #endregion

    Msg "Start Execution"
    $ReplaceStrings=Get-ReplaceStrings $Replacements
    $ExportExcludeAttributes+=Get-StandardExludeAttributes -Export
    if ([string]::IsNullOrEmpty($FileName)) {
        $FileName=$scriptPath + "\" + $ReplaceStrings.CompanyName + ".ADobjects." + (Get-Date).ToString("yyyy-MM-dd") + ".json"
    }

    $ObjectList=[ordered]@{}
}


Process {
    #Process operations are run for each object in pipeline processing    
    $propHash = @{}
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
        foreach($property in $AdObject.psobject.properties.name) {
            if ($ExportExcludeAttributes -notcontains $property) {
                #Only process readable props
                if (![string]::IsNullOrEmpty($AdObject.$property)) {
                    $value=$AdObject.$property
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
        $ObjectList.ToString() | ConvertTo-GenericStrings -ReplaceStrings $ReplaceStrings | Out-File $FileName
    } else {
        $ObjectList.ToString() | Out-File $FileName
    }
    
    Msg "End Execution"
}