function Send-WormholeText {
    [CmdletBinding(DefaultParameterSetName = 'ByText')]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text,

        [Parameter()]
        [string] $Code,

        [Parameter()]
        [string] $RelayUrl = $script:PowerWormholeDefaults.RelayUrl,

        [Parameter()]
        [string] $AppId = $script:PowerWormholeDefaults.AppId,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int] $TimeoutSeconds = 300,

        [Parameter()]
        [switch] $NoStatus,

        [Parameter()]
        [switch] $PassThru
    )

    $session = $null
    try {
        Write-WormholeDebug -Component 'cmd-send' -Message 'Send-WormholeText invoked.' -Data @{ hasCode = (-not [string]::IsNullOrWhiteSpace($Code)); textLength = $Text.Length; timeoutSeconds = $TimeoutSeconds; noStatus = [bool]$NoStatus }
        if ([string]::IsNullOrWhiteSpace($Code)) {
            $session = Open-Wormhole -AllocateCode -RelayUrl $RelayUrl -AppId $AppId
            Write-Host "Wormhole code is: $($session.Code)"
            if (-not $NoStatus) {
                Write-Host 'Share this code with the receiver, then wait for them to run Receive-WormholeText.'
            }
        }
        else {
            $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId
        }

        Write-WormholeDebug -Component 'cmd-send' -Message 'Open-Wormhole returned session.' -Session $session

        $statusCallback = $null
        if (-not $NoStatus) {
            $statusCallback = {
                param($Message)
                Write-Host "[send] $Message"
            }
        }

        Invoke-WormholeTextSendProtocol -Session $session -Text $Text -TimeoutSeconds $TimeoutSeconds -StatusCallback $statusCallback
        Write-WormholeDebug -Component 'cmd-send' -Message 'Send-WormholeText protocol finished.' -Session $session

        if ($PassThru) {
            $session
        }
    }
    finally {
        if ($null -ne $session) {
            Write-WormholeDebug -Component 'cmd-send' -Message 'Closing mailbox from Send-WormholeText.' -Session $session
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
