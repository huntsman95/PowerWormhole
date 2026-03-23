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
