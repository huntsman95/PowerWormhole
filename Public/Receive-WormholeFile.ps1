function Receive-WormholeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Code,

        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string] $OutputDirectory = (Get-Location).Path,

        [Parameter()]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId
    )

    $session = $null
    try {
        $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId
        $savedPath = Invoke-WormholeFileReceiveProtocol -Session $session -OutputDirectory $OutputDirectory -TimeoutSeconds $TimeoutSeconds -StatusCallback { param($message) Write-Verbose $message }
        Write-Host "File saved to: $savedPath"
        $savedPath
    }
    finally {
        if ($null -ne $session) {
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
