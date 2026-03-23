- Never user New-Object where possible and instead prefer the type accelerator syntax. For example, instead of writing `New-Object System.Collections.ArrayList`, write `[System.Collections.ArrayList]::new()`.

- Prefer native .NET methods over compiling C# code with Add-Type where possible.

- This powershell module needs to be compatible with PowerShell 5.1, so avoid using features that are only available in PowerShell 7 or later. For example, do not use the `using` statement for importing modules, and instead use `Import-Module`.

- Avoid using external dependencies where possible, and instead prefer using built-in PowerShell cmdlets and .NET classes.

- All guids must be generated using the `New-Guid` cmdlet to ensure they are unique and properly formatted.

- The name of this module is `PowerWormhole`

- The author of this module is `Hunter Klein` of `Skryptek, LLC`

- The module should be designed to be easily extendable in the future, with a clear and consistent structure for adding new features and functionality.

- All testing should be done with pester version 5 or later, and should cover all major functionality of the module to ensure reliability and stability.