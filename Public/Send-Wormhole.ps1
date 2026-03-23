function Send-Wormhole {
    [CmdletBinding(DefaultParameterSetName = 'Text')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Text')]
        [string] $Text,

        [Parameter(Mandatory = $true, ParameterSetName = 'File')]
        [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
        [string] $FilePath,

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
        [switch] $NoStatus
    )

    $session = $null
    try {
        Write-WormholeDebug -Component 'cmd-send' -Message 'Send-Wormhole invoked.' -Data @{ parameterSet = $PSCmdlet.ParameterSetName; hasCode = (-not [string]::IsNullOrWhiteSpace($Code)); timeoutSeconds = $TimeoutSeconds; noStatus = [bool]$NoStatus }

        if ([string]::IsNullOrWhiteSpace($Code)) {
            $session = Open-Wormhole -AllocateCode -RelayUrl $RelayUrl -AppId $AppId
            Write-Host "Wormhole code is: $($session.Code)"
            if (-not $NoStatus) {
                Write-Host 'Share this code with the receiver.'
            }
        }
        else {
            $session = Open-Wormhole -Code $Code -RelayUrl $RelayUrl -AppId $AppId
        }

        $statusCallback = $null
        if (-not $NoStatus) {
            $statusCallback = {
                param($Message)
                Write-Host "[send] $Message"
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'Text') {
            Invoke-WormholeTextSendProtocol -Session $session -Text $Text -TimeoutSeconds $TimeoutSeconds -StatusCallback $statusCallback
            return [pscustomobject]@{
                Type = 'text'
                Code = $session.Code
                Text = $Text
                TextLength = $Text.Length
                FilePath = $null
                FileName = $null
                FileSize = $null
            }
        }

        $fileItem = Get-Item -LiteralPath $FilePath
        Invoke-WormholeFileSendProtocol -Session $session -Path $FilePath -TimeoutSeconds $TimeoutSeconds -StatusCallback $statusCallback
        [pscustomobject]@{
            Type = 'file'
            Code = $session.Code
            Text = $null
            TextLength = $null
            FilePath = $fileItem.FullName
            FileName = $fileItem.Name
            FileSize = $fileItem.Length
        }
    }
    finally {
        if ($null -ne $session) {
            Close-WormholeMailbox -Session $session -Mood 'happy'
        }
    }
}
