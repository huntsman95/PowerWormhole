BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\PowerWormhole.psd1'
    Import-Module $modulePath -Force
}

Describe 'Module import' {
    It 'exports expected public commands' {
        $commands = @(
            'New-WormholeCode',
            'Open-Wormhole',
            'Send-WormholeText',
            'Receive-WormholeText',
            'Send-WormholeFile',
            'Receive-WormholeFile'
        )

        foreach ($name in $commands) {
            (Get-Command -Name $name -ErrorAction Stop).Name | Should -Be $name
        }
    }
}

Describe 'New-WormholeCode' {
    It 'creates nameplate-prefixed code' {
        $code = New-WormholeCode -CodeLength 2 -Nameplate '42'
        $code | Should -Match '^42-[a-z]+-[a-z]+$'
    }
}

Describe 'Validation helpers' {
    It 'accepts ws relay URL' {
        InModuleScope PowerWormhole {
            Test-WormholeRelayUrl -RelayUrl 'ws://relay.magic-wormhole.io:4000/v1' | Should -BeTrue
        }
    }

    It 'rejects invalid relay URL' {
        InModuleScope PowerWormhole {
            Test-WormholeRelayUrl -RelayUrl 'http://example.org' | Should -BeFalse
        }
    }
}

Describe 'HKDF' {
    It 'returns requested output length' {
        InModuleScope PowerWormhole {
            $ikm = [System.Text.Encoding]::UTF8.GetBytes('powerwormhole-test-ikm')
            $out = Invoke-WormholeHkdfSha256 -InputKeyMaterial $ikm -Length 42
            $out.Length | Should -Be 42
        }
    }
}

Describe 'SPAKE2 compatibility' {
    It 'matches python-spake2 symmetric start vector for seed 1' {
        InModuleScope PowerWormhole {
            function Get-PrgBytes {
                param(
                    [byte[]] $Seed,
                    [int] $Length
                )

                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $out = [System.Collections.Generic.List[byte]]::new()
                    $counter = 0
                    while ($out.Count -lt $Length) {
                        $material = [System.Text.Encoding]::ASCII.GetBytes("prng-$counter-") + $Seed
                        $block = $sha.ComputeHash($material)
                        $out.AddRange($block)
                        $counter += 1
                    }

                    $result = [byte[]]::new($Length)
                    [Array]::Copy($out.ToArray(), 0, $result, 0, $Length)
                    $result
                }
                finally {
                    $sha.Dispose()
                }
            }

            $seed = [System.Text.Encoding]::ASCII.GetBytes('1')
            $random = Get-PrgBytes -Seed $seed -Length 64
            $ctx = Start-WormholeSpake2 -Code 'password' -AppId '' -RandomBytes $random
            (ConvertTo-WormholeHex -Bytes $ctx.Message) | Should -Be '5308f692d38c4034ad6e2e1054c469ca1dbe990bcaec4bbd3ad78c7d968eadd0b3'
        }
    }

    It 'derives same shared key for two peers' {
        InModuleScope PowerWormhole {
            function Get-PrgBytes {
                param(
                    [byte[]] $Seed,
                    [int] $Length
                )

                $sha = [System.Security.Cryptography.SHA256]::Create()
                try {
                    $out = [System.Collections.Generic.List[byte]]::new()
                    $counter = 0
                    while ($out.Count -lt $Length) {
                        $material = [System.Text.Encoding]::ASCII.GetBytes("prng-$counter-") + $Seed
                        $block = $sha.ComputeHash($material)
                        $out.AddRange($block)
                        $counter += 1
                    }

                    $result = [byte[]]::new($Length)
                    [Array]::Copy($out.ToArray(), 0, $result, 0, $Length)
                    $result
                }
                finally {
                    $sha.Dispose()
                }
            }

            $r1 = Get-PrgBytes -Seed ([System.Text.Encoding]::ASCII.GetBytes('1')) -Length 64
            $r2 = Get-PrgBytes -Seed ([System.Text.Encoding]::ASCII.GetBytes('2')) -Length 64
            $a = Start-WormholeSpake2 -Code 'password' -AppId 'appid' -RandomBytes $r1
            $b = Start-WormholeSpake2 -Code 'password' -AppId 'appid' -RandomBytes $r2
            $ka = Complete-WormholeSpake2 -Context $a -PeerMessage $b.Message
            $kb = Complete-WormholeSpake2 -Context $b -PeerMessage $a.Message
            (ConvertTo-WormholeHex -Bytes $ka.SharedKey) | Should -Be (ConvertTo-WormholeHex -Bytes $kb.SharedKey)
        }
    }
}

Describe 'SecretBox compatibility' {
    It 'decrypts known wormhole test vector' {
        InModuleScope PowerWormhole {
            $key = ConvertFrom-WormholeHex -Hex 'ddc543ef8e4629a603d39dd0307a51bb1e7adb9cb259f6b085c91d0842a18679'
            $encrypted = ConvertFrom-WormholeHex -Hex '2d5e43eb465aa42e750f991e425bee485f06abad7e04af80fe318e39d0e4ce932d2b54b300c56d2cda55ee5f0488d63eb1d5f76f7919a49a'
            $plain = Unprotect-WormholeSecretBox -Key $key -Ciphertext $encrypted
            (ConvertTo-WormholeHex -Bytes $plain) | Should -Be 'edc089a518219ec1cee184e89d2d37af'
        }
    }

    It 'encrypts matching wormhole test vector with fixed nonce' {
        InModuleScope PowerWormhole {
            $key = ConvertFrom-WormholeHex -Hex 'ddc543ef8e4629a603d39dd0307a51bb1e7adb9cb259f6b085c91d0842a18679'
            $plain = ConvertFrom-WormholeHex -Hex 'edc089a518219ec1cee184e89d2d37af'
            $nonce = ConvertFrom-WormholeHex -Hex '2d5e43eb465aa42e750f991e425bee485f06abad7e04af80'
            $encrypted = Protect-WormholeSecretBox -Key $key -Plaintext $plain -Nonce $nonce
            (ConvertTo-WormholeHex -Bytes $encrypted) | Should -Be '2d5e43eb465aa42e750f991e425bee485f06abad7e04af80fe318e39d0e4ce932d2b54b300c56d2cda55ee5f0488d63eb1d5f76f7919a49a'
        }
    }
}

Describe 'File transfer: transit key derivation' {
    It 'Get-WormholeTransitKey returns 32 bytes' {
        InModuleScope PowerWormhole {
            $sharedKey = [byte[]]::new(32)
            $key = Get-WormholeTransitKey -SharedKey $sharedKey -AppId 'lothar.com/wormhole/text-or-file-xfer'
            $key.Length | Should -Be 32
        }
    }

    It 'Get-WormholeTransitKey is deterministic' {
        InModuleScope PowerWormhole {
            $sharedKey = [System.Text.Encoding]::UTF8.GetBytes('test-shared-key-padding-to-32byt')
            $k1 = Get-WormholeTransitKey -SharedKey $sharedKey -AppId 'test-app'
            $k2 = Get-WormholeTransitKey -SharedKey $sharedKey -AppId 'test-app'
            (ConvertTo-WormholeHex -Bytes $k1) | Should -Be (ConvertTo-WormholeHex -Bytes $k2)
        }
    }

    It 'Get-WormholeTransitRecordKey differs between sender and receiver' {
        InModuleScope PowerWormhole {
            $transitKey = [byte[]]::new(32)
            $senderKey   = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'sender'
            $receiverKey = Get-WormholeTransitRecordKey -TransitKey $transitKey -Direction 'receiver'
            $senderKey.Length   | Should -Be 32
            $receiverKey.Length | Should -Be 32
            (ConvertTo-WormholeHex -Bytes $senderKey) | Should -Not -Be (ConvertTo-WormholeHex -Bytes $receiverKey)
        }
    }
}

Describe 'File transfer: transit record nonce' {
    It 'returns a 24-byte nonce' {
        InModuleScope PowerWormhole {
            $nonce = New-WormholeTransitRecordNonce -SeqNum 0
            $nonce.Length | Should -Be 24
        }
    }

    It 'first 20 bytes are zero' {
        InModuleScope PowerWormhole {
            $nonce = New-WormholeTransitRecordNonce -SeqNum 7
            $nonce[0..19] | Should -Be ([byte[]]::new(20))
        }
    }

    It 'encodes sequence number big-endian in bytes 20-23' {
        InModuleScope PowerWormhole {
            $nonce = New-WormholeTransitRecordNonce -SeqNum 1
            $nonce[20] | Should -Be 0
            $nonce[21] | Should -Be 0
            $nonce[22] | Should -Be 0
            $nonce[23] | Should -Be 1
        }
    }

    It 'encodes large sequence number correctly' {
        InModuleScope PowerWormhole {
            # seqNum = 0x01020304
            $nonce = New-WormholeTransitRecordNonce -SeqNum 0x01020304
            $nonce[20] | Should -Be 0x01
            $nonce[21] | Should -Be 0x02
            $nonce[22] | Should -Be 0x03
            $nonce[23] | Should -Be 0x04
        }
    }
}

Describe 'File transfer: transit info builder' {
    It 'Build-WormholeTransitInfo includes relay-v1 ability' {
        InModuleScope PowerWormhole {
            $info = Build-WormholeTransitInfo -TransitRelay 'tcp:transit.magic-wormhole.io:4001'
            $abilities = $info['abilities-v1']
            $abilities | Where-Object { $_.type -eq 'relay-v1' } | Should -Not -BeNullOrEmpty
        }
    }

    It 'Build-WormholeTransitInfo includes relay hostname and port' {
        InModuleScope PowerWormhole {
            $info = Build-WormholeTransitInfo -TransitRelay 'tcp:transit.magic-wormhole.io:4001'
            $relayHint = $info['hints-v1'] | Where-Object { $_.type -eq 'relay-v1' }
            $relayHint | Should -Not -BeNullOrEmpty
            $endpoint = $relayHint.hints[0]
            $endpoint.hostname | Should -Be 'transit.magic-wormhole.io'
            $endpoint.port     | Should -Be 4001
        }
    }
}

Describe 'File transfer: record encrypt/decrypt round-trip' {
    It 'transit record survives encrypt + decrypt with matching nonce' {
        InModuleScope PowerWormhole {
            $key = ConvertFrom-WormholeHex -Hex 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
            $plain = [System.Text.Encoding]::UTF8.GetBytes('hello transit record')

            $seqNum = [uint32]42
            $nonce  = New-WormholeTransitRecordNonce -SeqNum $seqNum
            $boxed  = Protect-WormholeSecretBox -Key $key -Plaintext $plain -Nonce $nonce

            # Strip prepended nonce to get wire format, then re-attach
            $cipherRecord = [byte[]]::new($boxed.Length - 24)
            [Array]::Copy($boxed, 24, $cipherRecord, 0, $cipherRecord.Length)

            $fullCipher = [byte[]]::new(24 + $cipherRecord.Length)
            [Array]::Copy($nonce, 0, $fullCipher, 0, 24)
            [Array]::Copy($cipherRecord, 0, $fullCipher, 24, $cipherRecord.Length)

            $decrypted = Unprotect-WormholeSecretBox -Key $key -Ciphertext $fullCipher
            [System.Text.Encoding]::UTF8.GetString($decrypted) | Should -Be 'hello transit record'
        }
    }
}

Describe 'Send-WormholeFile and Receive-WormholeFile parameters' {
    It 'Send-WormholeFile accepts TimeoutSeconds parameter' {
        $cmd = Get-Command -Name Send-WormholeFile
        $cmd.Parameters.ContainsKey('TimeoutSeconds') | Should -BeTrue
    }

    It 'Receive-WormholeFile accepts TimeoutSeconds parameter' {
        $cmd = Get-Command -Name Receive-WormholeFile
        $cmd.Parameters.ContainsKey('TimeoutSeconds') | Should -BeTrue
    }

    It 'Receive-WormholeFile has OutputDirectory defaulting to current location' {
        $cmd = Get-Command -Name Receive-WormholeFile
        $cmd.Parameters.ContainsKey('OutputDirectory') | Should -BeTrue
    }
}
