# Building PowerWormhole

This document describes how to build, test, and develop the PowerWormhole module.

## Table of Contents

- [Quick Start](#quick-start)
- [Prerequisites](#prerequisites)
- [Development Setup](#development-setup)
- [Testing](#testing)
- [Build Process](#build-process)
- [Troubleshooting](#troubleshooting)

## Quick Start

```powershell
# Clone the repository
git clone https://github.com/huntsman95/PowerWormhole.git
cd PowerWormhole

# Install test dependencies
Install-Module -Name Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck

# Run tests
Invoke-Pester -Path .\tests -Detailed

# Import module for interactive testing
Import-Module .\PowerWormhole.psd1 -Force
```

## Prerequisites

### Core Requirements

- **PowerShell**: 5.1 or later (Windows PowerShell or PowerShell 7+)
- **.NET Framework**: 4.7.2+ or .NET Core 3.1+ (required for cryptographic libraries)

### Testing

- **Pester**: 5.7.1 or later (required for test execution)
  - Must be version 5.7.1 specifically for CI and formatted output
  - Install: `Install-Module -Name Pester -RequiredVersion 5.7.1 -Force`

### Build Automation (Optional)

- **InvokeBuild**: 5.10.1 or later (for automated build tasks)
  - Install: `Install-Module -Name InvokeBuild -MinimumVersion 5.10.1 -Force`

## Development Setup

### 1. Clone Repository

```powershell
git clone https://github.com/huntsman95/PowerWormhole.git
cd PowerWormhole
```

### 2. Install Dependencies

```powershell
# Install Pester 5.7.1 or later
Install-Module -Name Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck

# (Optional) Install InvokeBuild for automated builds
Install-Module -Name InvokeBuild -MinimumVersion 5.10.1 -Force -SkipPublisherCheck
```

### 3. Verify Setup

```powershell
# Check Pester version
Get-Module -Name Pester -ListAvailable | Select-Object Name, Version

# Verify module can be imported
Test-Path .\PowerWormhole.psd1
Import-Module .\PowerWormhole.psd1
Get-Command -Module PowerWormhole
```

**Expected output**: Three public cmdlets
- `New-WormholeCode`
- `Send-Wormhole`
- `Receive-Wormhole`

## Testing

### Run All Tests

```powershell
# Detailed output (recommended for development)
Invoke-Pester -Path .\tests -Detailed

# Simple output
Invoke-Pester -Path .\tests

# CI output format (XML results)
Invoke-Pester -Path .\tests -CI -Output Detailed
```

### Test Stats

- **Total Tests**: 25
- **Test Groups**: 
  - Module import validation (3 tests)
  - Crypto compatibility (8 tests)
  - Protocol behavior (7 tests)
  - Integration scenarios (7 tests)

### Test Coverage

The test suite validates:

✅ **Module Export**
- Correct public cmdlets exported
- No internal implementation functions exposed
- No legacy cmdlets in public API

✅ **Cryptography**
- SPAKE2 key exchange with known vectors
- SecretBox encryption round-trips
- Key derivation (HKDF-SHA256)
- Transit record encryption/decryption

✅ **Protocol**
- Mailbox communication (WebSocket JSON RPC)
- Version negotiation
- Offer/answer exchange
- Proper payload structure

✅ **Integration**
- Text message send/receive
- File transfer send/receive
- Parameter set validation
- Error handling

### Run Specific Tests

```powershell
# Filter by test name
Invoke-Pester -Path .\tests -Filter @{ Name = "*SPAKE2*" }

# Run single test file
Invoke-Pester -Path .\tests\PowerWormhole.Tests.ps1

# Show skipped tests
Invoke-Pester -Path .\tests -IncludeSkipped
```

### Test Troubleshooting

**Issue**: Tests hang or timeout
```powershell
# Increase timeout and run with verbose output
$PesterConfig = @{
    Path = '.\tests'
    Output = 'Detailed'
    TimeLimit = [timespan]::FromSeconds(300)
}
Invoke-Pester @PesterConfig
```

**Issue**: Pester version mismatch
```powershell
# Remove old Pester and reinstall specific version
Remove-Module Pester -Force -ErrorAction SilentlyContinue
Uninstall-Module Pester -AllVersions -Force -ErrorAction SilentlyContinue
Install-Module -Name Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck
```

**Issue**: Tests fail with "Cannot find NaCl"
```powershell
# Verify NaCl.Net DLL exists
Test-Path .\lib\NaCl.Net\NaCl.dll

# Re-clone if missing
git clone --recurse-submodules https://github.com/huntsman95/PowerWormhole.git
```

## Build Process

### Using InvokeBuild

If you have InvokeBuild 5.10.1+ installed:

```powershell
# List available build tasks
Invoke-Build -List

# Run default task (build + test)
Invoke-Build

# Run specific task
Invoke-Build -Task Test
Invoke-Build -Task Package
```

### Manual Build Steps

1. **Validate Syntax**
   ```powershell
   # Check for PowerShell syntax errors
   $files = Get-ChildItem -Recurse -Include *.ps1 -Path .\Public, .\Private
   foreach ($file in $files) {
       $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $file.FullName), [ref]$null)
       Write-Host "✓ $($file.Name)"
   }
   ```

2. **Run Tests**
   ```powershell
   Invoke-Pester -Path .\tests -CI -Output Detailed
   ```

3. **Verify Module Import**
   ```powershell
   Remove-Module PowerWormhole -ErrorAction SilentlyContinue
   Import-Module .\PowerWormhole.psd1 -Force
   
   # List exported functions
   Get-Command -Module PowerWormhole
   ```

4. **Generate Documentation** (optional)
   ```powershell
   # Generate cmdlet help as markdown
   Get-Help Send-Wormhole -Full | Out-File .\docs\Send-Wormhole.md
   Get-Help Receive-Wormhole -Full | Out-File .\docs\Receive-Wormhole.md
   Get-Help New-WormholeCode -Full | Out-File .\docs\New-WormholeCode.md
   ```

### Publishing to PowerShell Gallery

```powershell
# Authenticate with PowerShell Gallery
$ApiKey = Read-Host -AsSecureString -Prompt "PowerShell Gallery API Key"

# Publish module (requires API key)
Publish-Module -Path . -NuGetApiKey $(ConvertFrom-SecureString -SecureString $ApiKey -AsPlainText) `
               -NuGetPackageSource https://www.powershellgallery.com/

# Verify publication (wait ~5-10 minutes for indexing)
Find-Module -Name PowerWormhole
```

## Project Structure

```
PowerWormhole/
├── PowerWormhole.psd1         # Module manifest
├── PowerWormhole.psm1         # Module init & exports
├── build.ps1                  # (Optional) Build script for InvokeBuild
│
├── Public/                    # Public API
│   ├── New-WormholeCode.ps1
│   ├── Send-Wormhole.ps1
│   └── Receive-Wormhole.ps1
│
├── Private/                   # Internal implementation
│   ├── Crypto/                # Cryptographic helpers
│   ├── Models/                # Data structures
│   ├── Protocol/              # Protocol handlers
│   ├── Transport/             # Network layer
│   └── Utils/                 # Utilities
│
├── lib/                       # External libraries
│   ├── NaCl.Net/              # Cryptography (.dll)
│   ├── System.Memory/         # .NET utilities
│   └── System.Runtime.CompilerServices.Unsafe/
│
├── tests/                     # Pester tests
│   └── PowerWormhole.Tests.ps1
│
├── docs/                      # Documentation
│   ├── BUILDING.md            # This file
│   ├── DEPENDENCIES.md        # Dependency details
│   └── PROTOCOL.md            # (Future) Protocol spec
│
└── README.md                  # Main documentation
```

## Development Workflow

### Adding a New Feature

1. **Create a new function in `Private/` or `Public/`**
   ```powershell
   # New file: Private/Utils/MyHelper.ps1
   function MyHelper {
       param(
           [Parameter(Mandatory=$true)]
           [string]$InputData
       )
       
       # Implementation here
   }
   ```

2. **If public API, add export to `PowerWormhole.psm1`**
   ```powershell
   # Add to FunctionsToExport array in psm1
   ```

3. **Add tests to `tests/PowerWormhole.Tests.ps1`**
   ```powershell
   Describe "MyHelper function" {
       It "does something correctly" {
           MyHelper -InputData "test" | Should -Be "expected"
       }
   }
   ```

4. **Run and validate tests**
   ```powershell
   Invoke-Pester -Path .\tests -Filter @{ Name = "*MyHelper*" }
   ```

### Code Style Guidelines

- **Naming**: Use PascalCase for functions and parameters
- **Parameters**: Always include detailed comments for `-Param`
- **Error Handling**: Use `Write-Error` for terminating errors; validate input with `Validate*` attributes
- **Strict Mode**: All code must run under `Set-StrictMode -Version Latest`
- **Comments**: Document complex logic; link to protocol specifications where relevant
- **Modules**: Use `Import-Module` syntax (PowerShell 5.1 compatible); avoid `using` statements

Example:
```powershell
function New-MyObject {
    [CmdletBinding()]
    param(
        # Description of this parameter
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$InputString,
        
        # Another parameter
        [Parameter()]
        [int]$Timeout = 30
    )
    
    Set-StrictMode -Version Latest
    
    # Implementation
    return [PSObject]@{
        Result = $InputString
    }
}
```

## CI/CD Integration

### GitHub Actions

If using GitHub Actions, ensure:
- Runner OS: Windows (for .NET Framework compatibility)
- PowerShell: 5.1+ or pwsh >= 7.0
- Dependencies installed before test run

Example workflow:
```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Pester
        run: |
          Install-Module -Name Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck
      - name: Run Tests
        run: |
          Import-Module Pester -RequiredVersion 5.7.1 -Force
          Invoke-Pester -Path .\tests -CI -Output Detailed
```

### Azure Pipelines

Similar setup with PowerShell task pointing to test script:
```yaml
- task: PowerShell@2
  inputs:
    targetType: 'inline'
    script: |
      Install-Module -Name Pester -RequiredVersion 5.7.1 -Force -SkipPublisherCheck
      Invoke-Pester -Path ./tests -CI -Output Detailed
```

## Troubleshooting

### "Module cannot be found" error

```powershell
# Ensure you're in the PowerWormhole directory
Get-Location
cd PowerWormhole

# Import with absolute path
Import-Module (Resolve-Path .\PowerWormhole.psd1).Path -Force

# Verify import
Get-Module PowerWormhole
```

### "Required assembly not found" error

```powershell
# Verify all required DLLs exist
Test-Path .\lib\NaCl.Net\NaCl.dll
Test-Path .\lib\System.Memory\System.Memory.dll
Test-Path .\lib\System.Runtime.CompilerServices.Unsafe\System.Runtime.CompilerServices.Unsafe.dll

# Re-clone if any missing
git clone --recurse-submodules https://github.com/huntsman95/PowerWormhole.git
```

### Strict Mode Violations

```powershell
# Enable strict mode to catch issues early
Set-StrictMode -Version Latest

# Test a function
New-WormholeCode

# Check for any property access errors
```

### Tests timeout during relay communication

- Increase timeout: `Invoke-Pester -Path .\tests -TimeLimit ([timespan]::FromSeconds(600))`
- Check relay server availability: `Invoke-WebRequest -Uri "https://relay.magic-wormhole.io/v1"`
- Verify firewall allows WebSocket (port 4000)

## Resources

- [Magic Wormhole Docs](https://magic-wormhole.readthedocs.io/)
- [Pester Testing Framework](https://pester.dev/)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)
- [InvokeBuild](https://github.com/nightroman/Invoke-Build)
