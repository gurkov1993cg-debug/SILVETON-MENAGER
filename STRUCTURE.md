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
- Canonical Manager sample/multisample/SOUND model with preserved raw Korg source metadata.

### `include/silveton/manager/KorgImporter.h`
### `src/core/KorgImporter.cpp`
- KSF/KMP/KSC parsing, canonical PCM16LE output, exact zones and dependency loading.

### `include/silveton/manager/SampleHash.h`
### `src/core/SampleHash.cpp`
- Deterministic sample-audio hash; exact byte equality remains mandatory for dedup.

### `include/silveton/manager/SvBankFormat.h`
### `src/core/SvBankFormat.cpp`
- `.sv` v1 fixed header/records, explicit little-endian serialization and SHA-256.

### `include/silveton/manager/SvBankBuilder.h`
### `src/core/SvBankBuilder.cpp`
- Reference validation, string/audio dedup, 4096-byte audio alignment, SHA-256 and atomic writing.

### `include/silveton/manager/SvBankReader.h`
### `src/core/SvBankReader.cpp`
- Bounds/integrity/reference validation and full project reconstruction from `.sv`.

### `include/silveton/manager/AudioFileLoader.h`
### `src/core/AudioFileLoader.cpp`
- WAV import: PCM16, PCM24 and IEEE float32, mono/stereo, exact canonical bytes.
- Reads WAV `smpl` unity note and valid forward loop without inventing missing loops.
- AIFF import: PCM16/PCM24 mono/stereo with big-endian -> canonical little-endian conversion.
- AIFC supports uncompressed `NONE` and little-endian `sowt`; compressed codecs are rejected explicitly.
- AIFF `INST` root key and forward sustain loop are read when valid MARK references exist.

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
- Local full `.sv` build/read round-trip, exact audio recovery, dedup and corrupt-bank rejection PASS.
- Audio loader implementation compiles locally with strict `-Wall -Wextra -Wpedantic -Wshadow -Wconversion -Werror`.
- Repository-wide build is not yet claimed until regression tests and AppKit sources are committed and CI runs.

## Next
1. Commit regression tests and make core build cleanly.
2. Native AppKit GUI with real Import/Build Bank actions.
3. Batch import, one-click bank build, tablet transfer.
