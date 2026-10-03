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
- Portable core project declares C/CXX globally and enables Objective-C++ only on Apple.
- macOS is locked to x86_64 and deployment target 10.13.
- Core/tests compile with strict warnings as errors.
- AppKit bundle target remains Apple-only.

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
- Reference validation, deduplication, 4096-byte audio alignment, SHA-256 and atomic writing.

### `include/silveton/manager/SvBankReader.h`
### `src/core/SvBankReader.cpp`
- Bounds/integrity/reference validation and full project reconstruction.

### `include/silveton/manager/AudioFileLoader.h`
### `src/core/AudioFileLoader.cpp`
- WAV PCM16/PCM24/Float32 import with `smpl` root/forward loop support.
- AIFF PCM16/PCM24 and AIFC `NONE`/`sowt` import; canonical little-endian output.
- AIFF INST root key and valid forward sustain loop support.

### `tests/ManagerCoreTests.cpp`
- Always-active Release-safe regression checks.
- Synthetic KSF/KMP/WAV/AIFF fixtures plus `.sv` integrity/dedup/round-trip tests.

### `src/app/ManagerDocument.mm`
- Real Manager project owner; no placeholder data.
- Imports KMP, KSC, KSF, WAV, WAVE, AIF, AIFF and AIFC through the implemented core importers.
- Imported KMP/KSC multisamples become real SOUND records with deterministic Bank/Page/Slot addresses.
- Standalone KSF/WAV/AIFF imports become one-sample multisamples and SOUNDs.
- Build action writes the real `SILVETON_BANK.sv` through `SvBankBuilder::writeAtomic` and returns real dedup/count statistics.
- Provides actual SOUND rows/status counts for the AppKit GUI and a real clear-project operation.

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
- Release CMake build with `-Werror`: core + tests build successfully; `ctest` 1/1 PASS.
- `ManagerDocument.mm` is committed but native AppKit application build is not yet claimed until the remaining window/app/main `.mm` files exist and an Intel macOS build runs.

## Next
1. Implement native MainWindowController with only real Import/Clear/Build actions.
2. Implement AppDelegate and main entry.
3. Build the Intel macOS application target.
4. Replace the empty GitHub Actions workflow and run Intel macOS CI.
5. Add batch workflow polish and tablet transfer.
