function ConvertTo-GenericStrings {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
       [Parameter(ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName=$true)]
       [string]$InputObject,
       [System.Collections.Specialized.OrderedDictionary]$ReplaceStrings
    )
    $tag = '�'

    foreach($key in $ReplaceStrings.Keys) {
        $InputObject=$InputObject -replace [System.Text.RegularExpressions.Regex]::Escape($ReplaceStrings[$key]),($tag + $key + $tag)
    }

    return $InputObject
}