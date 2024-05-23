﻿function ConvertFrom-GenericStrings {
    [CmdletBinding(SupportsShouldProcess = $False)]
    param(
       [Parameter(ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName=$true)]
       [string]$InputObject,
       [System.Collections.Specialized.OrderedDictionary]$ReplaceStrings,
       [Switch]$EscapeJson
    )
    $tag = '¤'

    foreach($key in $ReplaceStrings.Keys) {
        if ($EscapeJson -and $ReplaceStrings[$key].ToString().Contains('\')) {
            $InputObject=$InputObject -replace [System.Text.RegularExpressions.Regex]::Escape($tag + $key + $tag + "\"),$ReplaceStrings[$key]
        } else {
            $InputObject=$InputObject -replace [System.Text.RegularExpressions.Regex]::Escape($tag + $key + $tag),$ReplaceStrings[$key]
        }
    }
    
    return $InputObject
}