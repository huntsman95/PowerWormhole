function New-PowerWormholeSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Code,

        [Parameter(Mandatory = $true)]
        [string] $Nameplate,

        [Parameter(Mandatory = $true)]
        [string] $RelayUrl,

        [Parameter(Mandatory = $true)]
        [string] $AppId,

        [Parameter(Mandatory = $true)]
        [string] $Side
    )

    [pscustomobject]@{
        PSTypeName = 'PowerWormhole.Session'
        Code = $Code
        Nameplate = $Nameplate
        RelayUrl = $RelayUrl
        AppId = $AppId
        Side = $Side
        MailboxId = $null
        Socket = $null
        Connected = $false
        Welcome = $null
        NextPhase = 0
        Mood = 'lonely'
        Created = [DateTimeOffset]::UtcNow
    }
}
