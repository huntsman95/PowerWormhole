$script:PowerWormholeWordlist = @(
    'acid','agent','amber','apple','arrow','atlas','baker','basic','beach','beacon','beetle','biscuit',
    'blazer','bonnet','bravo','cactus','canary','captain','carpet','cedar','clover','comet','copper','cricket',
    'dancer','delta','doctor','dragon','ember','falcon','forest','fossil','galaxy','garden','glider','harbor',
    'hazel','helium','hunter','island','jasmine','jupiter','kitten','lemon','lilac','magnet','maple','meteor',
    'nectar','nickel','oasis','olive','onyx','opal','orbit','panda','pepper','planet','pluto','prairie',
    'quartz','quiet','radar','raven','rocket','sable','saffron','shadow','signal','silver','spruce','sunset',
    'thunder','tiger','topaz','tulip','ultra','velvet','violet','walnut','willow','winter','wizard','zephyr'
)

function Get-WormholeRandomWord {
    [CmdletBinding()]
    param()

    $random = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $bytes = [byte[]]::new(4)
        $random.GetBytes($bytes)
        $value = [System.BitConverter]::ToUInt32($bytes, 0)
        $index = [int] ($value % [uint32]$script:PowerWormholeWordlist.Count)
        $script:PowerWormholeWordlist[$index]
    }
    finally {
        $random.Dispose()
    }
}
