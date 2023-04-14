<#
    .SYNOPSIS
        Set command prompt environment for test and development
    .DESCRIPTION
        Load PSJumpStart module AND create all variables as global ones.
        
#>
Import-Module PSJumpStart -Force -MinimumVersion 1.2.5

#region local functions
function Get-LocalDefaultVariables {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
        [parameter(Position = 0, mandatory = $true)]
        $CallerInvocation,
        [switch]$defineNew,
        [switch]$overWriteExisting
    )
    foreach ($settingsFile in (Get-SettingsFiles $CallerInvocation ".json")) {        
        if (Test-Path $settingsFile) {        
            Write-Verbose "Reading file: [$settingsFile]"
            $DefaultParamters = Get-Content -Path $settingsFile -Encoding UTF8 | ConvertFrom-Json
            ForEach ($prop in $DefaultParamters | Get-Member -MemberType NoteProperty) {        
                
                if (($prop.Name).IndexOf(':') -eq -1) {
                    $key = $prop.Name
                    $var = Get-Variable $key -ErrorAction SilentlyContinue$PS
                    $value = $DefaultParamters.($prop.Name)                    
                    if (!$var) {
                        if ($defineNew) {
                            Write-Verbose "New Var: $key" 
                            if ($value.GetType().Name -eq "String" -and $value.SubString(0, 1) -eq '(') {
                                $var = New-Variable -Name  $key -Value (Invoke-Expression $Value) -Option AllScope -Scope Global
                            }
                            else {
                                $var = New-Variable -Name  $key -Value $value -Option AllScope -Scope Global
                            }
                        }
                    }
                    else {

                        #We only overwrite non-set values if not forced
                        if (!($var.Value) -or $overWriteExisting) {
                            try {                
                                Write-Verbose "Var: $key" 
                                if ($value.GetType().Name -eq "String" -and $value.SubString(0, 1) -eq '(') {
                                    $var.Value = Invoke-Expression $value
                                }
                                else {
                                    $var.Value = $value
                                }
                            }
                            Catch {
                                $ex = $PSItem
                                $ex.ErrorDetails = "Err adding $key from $settingsFile. " + $PSItem.Exception.Message
                                throw $ex
                            }
                        }
                    }
                }
            }
        }
    }
}

#endregion

Get-LocalDefaultVariables -CallerInvocation $MyInvocation -defineNew -Verbose

"Run from command promt: "
'$PSDefaultParameterValues = Get-GlobalDefaultsFromJsonFiles $MyInvocation'



