function ConvertFrom-GenericStrings {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
       [Parameter(ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName=$true)]
       [string]$InputObject,
       [System.Collections.Specialized.OrderedDictionary]$ReplaceStrings
    )
    $tag = '¤'

    foreach($key in $ReplaceStrings.Keys) {
        $InputObject=$InputObject -replace [System.Text.RegularExpressions.Regex]::Escape($tag + $key + $tag),$ReplaceStrings[$key]
    }

    return $InputObject
}