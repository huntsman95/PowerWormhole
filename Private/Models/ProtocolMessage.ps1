function New-WormholeProtocolMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Type,

        [Parameter()]
        [hashtable] $Fields = @{}
    )

    $message = @{
        type = $Type
    }

    foreach ($key in $Fields.Keys) {
        $message[$key] = $Fields[$key]
    }

    [pscustomobject]$message
}
