# SILVETON MANAGER — STRUCTURE

Updated: 2026-10-03

## Repository
- `gurkov1993cg-debug/SILVETON-MENAGER`
- Active development branch: `silveton-manager-development`
- `main` is preserved.

## Target
- Native Intel iMac 2011 application.
- x86_64 only, C++17 core, Objective-C++/AppKit GUI.
- macOS deployment target 10.13.
- No JUCE, Electron, or browser GUI runtime.

## Product role
`import -> analysis -> multisample building -> SOUND building -> deduplication -> SILVETON_BANK.sv`

Tablet runtime must only open the prepared bank/index and stream audio; it must not rebuild KMP/KSC structures on startup.

## Implemented files

### `CMakeLists.txt`
- Intel/macOS baseline, core library, AppKit target and tests.

### `include/silveton/manager/ManagerTypes.h`
- Canonical Manager sample/multisample/SOUND data model and preserved raw Korg source metadata.

### `include/silveton/manager/KorgImporter.h`
### `src/core/KorgImporter.cpp`
- KSF/KMP/KSC parser with canonical PCM16LE output, exact zones and dependency loading.

### `include/silveton/manager/SampleHash.h`
### `src/core/SampleHash.cpp`
- Deterministic sample-audio hash; exact byte equality remains required for dedup.

### `include/silveton/manager/SvBankFormat.h`
### `src/core/SvBankFormat.cpp`
- `.sv` v1 fixed header/records, explicit little-endian serialization and internal SHA-256.

### `include/silveton/manager/SvBankBuilder.h`
### `src/core/SvBankBuilder.cpp`
- Validates all sample, zone and SOUND references before writing.
- Builds deduplicated string and audio payloads.
- Audio dedup uses hash buckets plus exact format and byte equality, so a hash collision cannot merge different audio.
- Generates fixed metadata sections and 4096-byte-aligned audio payload for random access/streaming.
- Computes SHA-256 over all payload bytes and writes the final header last.
- Provides atomic `.tmp` -> target replacement and build statistics.

## Real Korg regression fixture
User-provided `SALEAS-GRK SH.kmp` + 13 KSF files.
Verified: 14 RLP1 regions; first is `SKIPPEDSAMPL` keys 0..1; 13 playable zones; 48 kHz/16-bit/mono; first playable zone C4/root 60 keys 2..61; raw pan 64 preserved and maps to centre; no fake loop.

## SILVETON_BANK.sv v1 layout
1. Fixed 256-byte header: magic/version/counts/section offsets/SHA-256.
2. SOUND records.
3. SOUND layer records.
4. Multisample records.
5. Sample records.
6. Zone records.
7. Deduplicated string table.
8. 4096-byte-aligned deduplicated audio payload.

## Verification status
- Development branch exists; `main` untouched.
- Strict local SALEAS import smoke test PASS.
- SHA-256 standard `abc` vector PASS.
- Local builder/reader round-trip PASS using SALEAS data.
- Dedup test PASS: an added duplicate sample produces 14 sample records but only 13 physical audio payloads.
- Repository-wide build is not yet claimed until reader, audio loader, tests and remaining CMake sources are committed.

## Next
1. Commit bank reader contract/implementation.
2. WAV/AIFF importer.
3. Regression tests + clean core build.
4. Native AppKit GUI.
5. Batch import, one-click bank build, tablet transfer.
