# PowerWormhole Implementation Plan

## Goal
Build a pure PowerShell/.NET implementation of the Magic Wormhole protocol that interoperates with Python `magic-wormhole` clients.

- Module name: `PowerWormhole`
- Author: `Hunter Klein` (`Skryptek, LLC`)
- Runtime target: Windows PowerShell 5.1+ compatibility
- Default rendezvous (mailbox) URL: `ws://relay.magic-wormhole.io:4000/v1`

---

## Scope and Compatibility Targets

### Primary compatibility targets (must-have)
1. Mailbox server protocol compatibility (WebSocket JSON frames, bind/claim/open/add/close flow).
2. Client-to-client protocol compatibility (PAKE exchange, encrypted `version`, ordered numeric phases).
3. Text transfer compatibility (`wormhole send --text` ↔ `PowerWormhole` receive, and vice versa).
4. File transfer compatibility through transit hints and relay fallback.

### Secondary targets (later)
1. Directory transfer parity.
2. UX parity with code completion/listing behavior where practical.
3. Optional advanced protocol features (journal/dilation) after baseline parity.

### Explicit non-goals for initial release
- Re-implementing mailbox or transit servers.
- PowerShell 7-only language features.
- External native dependencies when .NET built-ins are sufficient.

### Text Message Transfer Compatibility (explicit)
PowerWormhole v1 must fully support short text message transfer over wormhole without Transit, compatible with Python CLI behavior.

Required behaviors:
1. Interoperate with `wormhole send --text` as sender or receiver.
2. Use mailbox-mediated encrypted numeric phases for app payload delivery.
3. Preserve in-order delivery semantics for numeric phases.
4. Return clear wrong-code failure behavior consistent with wormhole “scary”/wrong-password outcomes.
5. Complete successfully without requiring file-transfer protocol or transit relay setup.

---

## Design Principles
1. **Interop-first**: wire-level compatibility over API elegance for v1.
2. **Layered architecture**: transport, protocol, crypto, app API, cmdlets.
3. **Deterministic state machine**: strict protocol phases and transitions.
4. **Extensible module layout**: clear internal boundaries for future features.
5. **Minimal dependencies**: rely on built-in PowerShell/.NET primitives.

---

## Proposed Module Structure

```text
PowerWormhole/
  PowerWormhole.psd1
  PowerWormhole.psm1
  Public/
    New-WormholeCode.ps1
    Open-Wormhole.ps1
    Send-WormholeText.ps1
    Receive-WormholeText.ps1
    Send-WormholeFile.ps1
    Receive-WormholeFile.ps1
  Private/
    Protocol/
      MailboxClient.ps1
      WormholeClientProtocol.ps1
      FileTransferProtocol.ps1
      TransitClient.ps1
    Crypto/
      Spake2Adapter.ps1
      Hkdf.ps1
      SecretBoxAdapter.ps1
      KeyDerivation.ps1
    Transport/
      WebSocketTransport.ps1
      TcpTransport.ps1
      RetryPolicy.ps1
    Models/
      ProtocolMessage.ps1
      ConnectionHints.ps1
      WormholeState.ps1
    Utils/
      Json.ps1
      Hex.ps1
      Wordlist.ps1
      Validation.ps1
  docs/
    IMPLEMENTATION_PLAN.md
```

> Note: file names are planned targets, not yet implemented.

---

## Protocol Work Breakdown

## Phase 0 — Foundation and Test Harness
- Initialize module manifest and import structure.
- Create logging hooks and trace toggles for protocol debugging.
- Build integration harness that can run Python `wormhole` as a peer for interop tests.
- Add protocol capture tests for mailbox message ordering, dedup handling, and reconnect behavior.

**Exit criteria**
- Module loads in Windows PowerShell 5.1.
- Test harness can launch interop scenarios against Python client.

## Phase 1 — Mailbox Protocol Core
Implement client-to-server mailbox interactions over WebSocket:
- `bind` (with appid + side)
- `allocate` / `claim` / `release`
- `open` / `add` / `close`
- `ping` / `pong`
- `welcome`, `ack`, `message`, `error` processing

Technical requirements:
- UTF-8 JSON serialized into binary WebSocket frames.
- Ignore unknown server keys/types where protocol expects forward compatibility.
- Reconnect with exponential backoff and state resumption.
- Configurable relay URL with default:
  - `ws://relay.magic-wormhole.io:4000/v1`

**Exit criteria**
- Can establish mailbox and exchange raw phases with a Python peer.

## Phase 2 — Client-to-Client Crypto and Phase Engine
Implement wormhole-side protocol:
- PAKE phase (`pake`) message exchange.
- Shared key derivation.
- Verifier generation/exposure.
- Encrypted `version` message support.
- Numeric phase ordering and in-order delivery.
- Mood/error transitions (`lonely`, `happy`, `scary`, `errory`) mapped to PowerShell errors/events.

Technical requirements:
- HKDF-SHA256 phase/side scoped key derivation per protocol expectations.
- Authenticated encryption compatible with Python implementation behavior.
- Strict handling of decryption failures as wrong-password/scary close.

**Exit criteria**
- Text payload exchange interoperates with Python in both directions.

## Phase 3 — Public Text API / Cmdlets
- `Open-Wormhole` (create or join code flow).
- `Send-WormholeText` and `Receive-WormholeText`.
- Code generation and parsing (`nameplate-word-word`).
- Option to supply code manually or allocate automatically.

**Exit criteria**
- End-to-end `wormhole send --text` ↔ `PowerWormhole` receive works.
- End-to-end `PowerWormhole` send text ↔ Python `wormhole receive` works.
- Wrong-code scenario fails predictably with a user-facing wrong-password style error.

## Phase 4 — Transit + File Transfer
- Transit ability/hints negotiation messages.
- Direct TCP attempts and relay fallback support.
- Sender/Receiver handshake behavior.
- File transfer offer/answer/ack flow.
- SHA256 confirmation handling.

**Exit criteria**
- End-to-end `wormhole send <file>` ↔ `PowerWormhole` receive works.

## Phase 5 — Hardening and Packaging
- Retry behavior and cancellation paths.
- Timeouts and cleanup safety.
- Additional validation, diagnostics, and docs.
- Publish-ready module packaging.

**Exit criteria**
- Stable interop matrix passes in CI and local tests.

---

## Key Technical Decisions (Planned)

1. **Rendezvous default**
   - Expose module-level default relay: `ws://relay.magic-wormhole.io:4000/v1`.
   - Allow override via cmdlet parameter and environment variable.

2. **State model**
   - Implement a finite-state machine so mailbox, PAKE, and transfer transitions are explicit and testable.

3. **Message model**
   - Centralized message encode/decode helpers (JSON + UTF-8 + hex conversion for message body).

4. **Crypto abstraction**
   - Keep SPAKE2, HKDF, and secretbox-like encryption behind adapters for future replacement while preserving wire format.

5. **Interop as contract tests**
   - Treat Python `magic-wormhole` as authoritative behavior baseline.

---

## Interop Test Matrix (Planned)

For each test, run both directions where applicable:
1. PowerWormhole allocate code, Python receives text.
2. Python allocate code, PowerWormhole receives text.
3. PowerWormhole send text with explicit code, Python `wormhole receive` consumes it.
4. Python `wormhole send --text` with explicit code, PowerWormhole receives it.
5. Wrong code / decryption failure behavior.
6. Duplicate and out-of-order mailbox message handling.
7. Reconnect during mailbox session.
8. File transfer via direct TCP hints.
9. File transfer via relay fallback.

Success criteria:
- Protocol succeeds without custom server changes.
- Failure modes map cleanly to user-facing errors.
- No PowerShell 7-specific requirements.

---

## Risks and Mitigations

1. **Crypto primitive parity risk**
   - Mitigation: lock interop tests early (Phase 2), verify test vectors before cmdlet UX.

2. **WebSocket behavior differences in PowerShell 5.1**
   - Mitigation: isolate transport with robust reconnect and framing tests.

3. **Transit negotiation complexity**
   - Mitigation: keep v1 limited to direct-tcp-v1 + relay-v1 before broader abilities.

4. **Protocol evolution upstream**
   - Mitigation: ignore unknown message keys/types as required, keep protocol constants centralized.

---

## Documentation Deliverables (Planned)

- Quickstart for text send/receive.
- File transfer walkthrough.
- Compatibility matrix with tested Python versions.
- Troubleshooting guide for relay, NAT, and wrong-code errors.
- Security notes (PAKE trust model, verification strings, and failure modes).

---

## Immediate Next Step (after plan approval)

Implement **Phase 0** and **Phase 1 skeleton**:
1. Module manifest and folder scaffolding.
2. WebSocket mailbox transport + message envelope handling.
3. Minimal interop smoke test against Python client using the default relay URL.
