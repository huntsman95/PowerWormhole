@{
    RootModule = 'PowerWormhole.psm1'
    RequiredAssemblies = @(
        'lib\System.Memory\System.Memory.dll',
        'lib\System.Runtime.CompilerServices.Unsafe\System.Runtime.CompilerServices.Unsafe.dll',
        'lib\NaCl.Net\NaCl.dll'
    )
    ModuleVersion = '0.1.0'
    GUID = 'c6ed795c-69ef-4147-9dc1-853d515d3514'
    Author = 'Hunter Klein'
    CompanyName = 'Skryptek, LLC'
    Copyright = '(c) Hunter Klein, Skryptek, LLC. All rights reserved.'
    Description = 'Pure PowerShell/.NET Magic Wormhole protocol module.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'New-WormholeCode',
        'Send-WormholeText',
        'Receive-WormholeText',
        'Send-WormholeFile',
        'Receive-WormholeFile'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('wormhole', 'magic-wormhole', 'transfer', 'crypto')
            ProjectUri = 'https://github.com/magic-wormhole/magic-wormhole'
            LicenseUri = 'https://opensource.org/license/mit'
            Prerelease = 'alpha1'
        }
    }
}
