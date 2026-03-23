# PowerWormhole

A pure PowerShell/.NET implementation of the [Magic Wormhole](https://magic-wormhole.readthedocs.io/) protocol for secure file and text transfer over the internet.

**Author:** Hunter Klein (Skryptek, LLC)  
**License:** MIT  
**PowerShell Version:** 5.1+  

## Overview

PowerWormhole enables you to securely send files and text messages to another person using a simple, shared code. No setup required—just run a command, share the generated code, and your recipient receives the data securely with end-to-end encryption.

### Key Features

- **End-to-End Encryption**: Uses SPAKE2 key exchange + NaCl SecretBox (XSalsa20-Poly1305)
- **Text & File Transfer**: Unified cmdlets automatically detect transfer type
- **Code-Based Pairing**: Simple passphrase-based session establishment—no usernames or passwords
- **Pure PowerShell**: No external CLI dependencies; built entirely in PowerShell and .NET
- **Strict Mode Compliant**: Runs under `Set-StrictMode -Version Latest`
- **Comprehensive Test Coverage**: Pester 5.7.1+ test suite with thorough validation

## Quick Start

### Installation

1. Clone or download the repository:
   ```powershell
   git clone https://github.com/huntsman95/PowerWormhole.git
   cd PowerWormhole
   ```

2. Import the module:
   ```powershell
   Import-Module .\PowerWormhole.psd1
   ```

### Usage Examples

#### Generate a Wormhole Code

```powershell
# Generate a new code
New-WormholeCode -CodeLength 2
# Output: 42-red-apple
```

#### Send Text

```powershell
# Send a text message (auto-generates code and prints to console)
Send-Wormhole -Text "Hello, World!"

# Send text with an existing code
Send-Wormhole -Text "Hello, World!" -Code "42-red-apple"
```

#### Send a File

```powershell
# Send a file (auto-generates code)
Send-Wormhole -FilePath "C:\path\to\document.pdf"

# Send with an existing code
Send-Wormhole -FilePath "C:\path\to\document.pdf" -Code "42-red-apple" -TimeoutSeconds 300
```

#### Receive Text or File

```powershell
# Receive (auto-detects type: text or file)
Receive-Wormhole -Code "42-red-apple"

# Receive with options
Receive-Wormhole -Code "42-red-apple" -OutputDirectory "C:\Downloads" -TimeoutSeconds 120
```

## Public API

### New-WormholeCode

Generates a new Magic Wormhole code (nameplate + two random words).

```powershell
New-WormholeCode [-CodeLength <int>] [-Nameplate <string>]
```

**Parameters:**
- `-CodeLength` (default: 2): Number of random words to append to nameplate
- `-Nameplate` (default: random): Numeric prefix or custom string

**Output:** String in format `{nameplate}-{word1}-{word2}`

### Send-Wormhole

Sends text or a file securely over an encrypted wormhole.

```powershell
# Text Parameter Set
Send-Wormhole -Text <string> [-Code <string>] [-TimeoutSeconds <int>]

# File Parameter Set
Send-Wormhole -FilePath <string> [-Code <string>] [-TimeoutSeconds <int>]
```

**Parameters:**
- `-Text` (Text parameter set): Message to send
- `-FilePath` (File parameter set): Path to file to send
- `-Code` (optional): Wormhole code; if omitted, code is auto-generated and printed to console
- `-TimeoutSeconds` (default: 300): Timeout for establishing connection

**Output:** PSObject with properties:
- `Type` - 'text' or 'file'
- `Code` - The wormhole code used
- `Text` or `FilePath` - Transferred data
- `TextLength` or `FileSize` - Size in bytes
- `FileName` - (file transfer only)

### Receive-Wormhole

Receives text or file over a wormhole, auto-detecting the transfer type.

```powershell
Receive-Wormhole -Code <string> [-OutputDirectory <string>] [-TimeoutSeconds <int>] [-NoStatus]
```

**Parameters:**
- `-Code`: Wormhole code to connect to
- `-OutputDirectory` (default: current directory): Directory to save received files
- `-TimeoutSeconds` (default: 300): Timeout for receiving data
- `-NoStatus`: Suppress status messages

**Output:** PSObject with properties:
- `Type` - 'text' or 'file'
- `Text` or `FilePath` - Received data
- `FileName` - (file transfer only)
- `FileSize` - Size in bytes (file transfer only)

## How It Works

### Protocol Overview

PowerWormhole implements the Magic Wormhole protocol:

1. **Code Generation**: Creating a code allocates a _nameplate_ from the relay and returns a human-readable code
2. **Key Exchange**: Both sides exchange SPAKE2 messages using their shared code
3. **Session Opening**: Encrypted handshake opens a symmetric session
4. **Offer/Answer**: Sender offers (text or file), receiver accepts
5. **Transfer**: Data transferred over encrypted mailbox (text) or transit relay (files)

### Architecture

```
┌─────────────────────────────────────────┐
│       Public Cmdlets                    │
│  ┌──────────────────────────────────┐   │
│  │ Send-Wormhole / Receive-Wormhole │   │
│  │ New-WormholeCode                 │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│    Protocol Handlers (Private/)         │
│  ┌──────────────────────────────────┐   │
│  │ WormholeClientProtocol.ps1       │   │
│  │ (SPAKE2, encryption, offer/ack)  │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ MailboxClient.ps1                │   │
│  │ (Relay communication)            │   │
│  └──────────────────────────────────┘   │
│  ┌──────────────────────────────────┐   │
│  │ TransitClient.ps1                │   │
│  │ (File transfer over TCP)         │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│      Cryptographic Primitives           │
│  ┌──────────────────────────────────┐   │
│  │ NaCl.Net DLL or Native .NET API  │   │
│  │ (SecretBox, SPAKE2, etc.)        │   │
│  └──────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

### Cryptography

- **SPAKE2**: Secure pre-authenticated key exchange (protected from password-guessing attacks)
- **SecretBox**: XSalsa20 stream cipher + Poly1305 MAC (authenticated encryption)
- **Hash**: SHA256-based key derivation (HKDF-SHA256)
- **Randomness**: Cryptographically secure random number generation via `System.Security.Cryptography.RandomNumberGenerator`

**Implementation**: Uses NaCl.Net library (`lib/NaCl.Net/NaCl.dll`) for hardened, battle-tested cryptographic primitives.

## Building & Testing

### Dependencies

**Runtime:**
- PowerShell 5.1 or later
- .NET Framework 4.7.2+ or .NET Core 3.1+
- NuGet dependencies (included in `lib/`):
  - `NaCl.Net` (secure cryptography)
  - `System.Memory` (performance utilities)
  - `System.Runtime.CompilerServices.Unsafe` (interop support)

**Development & Testing:**
- **Pester** 5.7.1 or later (test framework)
- **InvokeBuild** 5.10.1 or later (build automation)

### Quick Build & Test

```powershell
# Navigate to project root
cd PowerWormhole

# Run tests
Invoke-Pester -Path .\tests -Detailed

# Build with InvokeBuild (if installed)
Invoke-Build
```

### Detailed Documentation

See [docs/BUILDING.md](docs/BUILDING.md) for comprehensive build instructions.  
See [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) for detailed dependency information.

## Project Structure

```
PowerWormhole/
├── PowerWormhole.psd1          # Module manifest
├── PowerWormhole.psm1          # Module initialization
├── README.md                   # This file
├── docs/
│   └── BUILDING.md             # Build instructions
├── lib/
│   ├── NaCl.Net/               # Cryptographic library
│   ├── System.Memory/          # .NET utility library
│   └── System.Runtime.CompilerServices.Unsafe/
├── Public/
│   ├── New-WormholeCode.ps1
│   ├── Send-Wormhole.ps1
│   └── Receive-Wormhole.ps1
├── Private/
│   ├── Crypto/                 # Cryptographic implementations
│   ├── Models/                 # Data models (session state, messages)
│   ├── Protocol/               # Protocol handlers
│   ├── Transport/              # WebSocket & network transport
│   └── Utils/                  # Utilities (logging, validation, hex encoding)
└── tests/
    └── PowerWormhole.Tests.ps1 # Pester test suite
```

## Features

### ✅ Implemented

- [x] SPAKE2 key exchange
- [x] NaCl SecretBox encryption
- [x] Unified send/receive cmdlets with auto-type detection
- [x] Text message transfer
- [x] File transfer with progress
- [x] WebSocket-based mailbox relay communication
- [x] TCP-based transit relay for file streaming
- [x] Dual crypto backend (NaCl.Net + native .NET)
- [x] Comprehensive Pester test suite
- [x] Error handling and logging

## Testing

The module includes a comprehensive test suite covering:

- **Crypto Validation**: SPAKE2 vectors, SecretBox encryption round-trips, key derivation
- **Protocol**: Mailbox communication, transit relay negotiation, offer/answer exchange
- **Integration**: End-to-end text and file transfers with both crypto backends
- **Parameter Sets**: Unified cmdlet parameter validation
- **Export Validation**: Verify only public API is exposed

Run tests with:

```powershell
# All tests with detailed output
Invoke-Pester -Path .\tests -Detailed

# Specific test group
Invoke-Pester -Path .\tests -Container (New-PesterContainer -Path .\tests -Data @{ Backend = 'Native' })

# Filter by description pattern
Invoke-Pester -Path .\tests -Filter @{ ExactMatch = $true; Expression = 'SPAKE2' }
```

## Troubleshooting

### Issue: "Cannot find NaCl.dll"

**Solution:** The NaCl.Net DLL must be present in `lib/NaCl.Net/NaCl.dll`. Ensure the module is properly cloned with all subdirectories then run Invoke-Build.

```powershell
# Verify NaCl.Net library is present
Test-Path .\lib\NaCl.Net\NaCl.dll
```

### Issue: Timeout connecting to relay

**Common causes:**
- Network connectivity issues
- Relay server unreachable (check magic-wormhole relay availability)
- Firewall blocking WebSocket (port 4000)

**Solution:** Increase timeout or check relay:

```powershell
# Longer timeout
Send-Wormhole -Text "Hello" -TimeoutSeconds 600

# Check relay connectivity (requires curl/Invoke-WebRequest)
Invoke-WebRequest -Uri "https://relay.magic-wormhole.io/v1" -Method GET
```

### Issue: "Strict mode" violation errors

**Solution:** Ensure the module is imported correctly:

```powershell
# Full reload
Remove-Module PowerWormhole -ErrorAction SilentlyContinue
Import-Module .\PowerWormhole.psd1 -Force
```

## Contributing

Contributions are welcome! Please ensure:

1. All Pester tests pass (`Invoke-Pester -Path .\tests`)
2. Code follows PowerShell style guide (PascalCase cmdlet names, proper error handling)
3. New features include unit tests
4. Code runs under `Set-StrictMode -Version Latest`
5. Avoid external CLI dependencies where possible

## License

MIT License—see LICENSE file for details.

## References

- [Magic Wormhole Protocol](https://magic-wormhole.readthedocs.io/)
- [SPAKE2 (RFC 8235)](https://tools.ietf.org/html/rfc8235)
- [NaCl Cryptography](https://nacl.cr.yp.to/)
- [PowerShell Best Practices](https://github.com/PoshCode/PowerShellPracticeAndStyle)

## Support

For issues, questions, or feature requests, open an issue on the [GitHub repository](https://github.com/huntsman95/PowerWormhole).
