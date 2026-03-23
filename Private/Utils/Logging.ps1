function Write-WormholeDebug {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Component,

        [Parameter(Mandatory = $true)]
        [string] $Message,

        [Parameter()]
        [pscustomobject] $Session,

        [Parameter()]
        [hashtable] $Data
    )

    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    $contextParts = @()

    if ($null -ne $Session) {
        if ($null -ne $Session.Side -and -not [string]::IsNullOrWhiteSpace([string]$Session.Side)) {
            $contextParts += "side=$($Session.Side)"
        }

        if ($null -ne $Session.Nameplate -and -not [string]::IsNullOrWhiteSpace([string]$Session.Nameplate)) {
            $contextParts += "nameplate=$($Session.Nameplate)"
        }

        if ($null -ne $Session.MailboxId -and -not [string]::IsNullOrWhiteSpace([string]$Session.MailboxId)) {
            $contextParts += "mailbox=$($Session.MailboxId)"
        }
    }

    $contextText = ''
    if ($contextParts.Count -gt 0) {
        $contextText = ' [' + ($contextParts -join ',') + ']'
    }

    $dataText = ''
    if ($null -ne $Data -and $Data.Count -gt 0) {
        try {
            $json = ConvertTo-Json -InputObject $Data -Depth 10 -Compress
            $dataText = " data=$json"
        }
        catch {
            $dataText = ' data=<unserializable>'
        }
    }

    Write-Verbose "[$timestamp][PowerWormhole][$Component]$contextText $Message$dataText"
}
