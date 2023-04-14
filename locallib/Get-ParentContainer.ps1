function Get-ParentContainer {
    param(
        [Parameter(ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName=$true)]
        [string]$distinguishedName
    )
    $distinguishedName -replace '^.+?,(DC|CN|OU.+)','$1'
}