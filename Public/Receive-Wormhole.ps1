function Receive-Wormhole {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Code,

        [Parameter()]
        [ValidateScript({ Test-Path -Path $_ -PathType Container })]
        [string] $OutputDirectory = (Get-Location).Path,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [switch] $NoStatus
    )

    $session = $null
    try {
        Write-WormholeDebug -Component 'cmd-recv' -Message 'Receive-Wormhole invoked.' -Data @{ code = $Code; outputDirectory = $OutputDirectory; timeoutSeconds = $TimeoutSeconds; noStatus = [bool]$NoStatus }
        $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId

        $statusCallback = $null
        if (-not $NoStatus) {
            $statusCallback = {
                param($Message)
                Write-Host "[recv] $Message"
            }
        }

        $result = Invoke-WormholeReceiveProtocol -Session $session -OutputDirectory $OutputDirectory -TimeoutSeconds $TimeoutSeconds -StatusCallback $statusCallback
        if ($result.Type -eq 'file') {
            Write-Host "File saved to: $($result.FilePath)"
        }

        $result
    }
    finally {
        if ($null -ne $session) {
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
