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
- `CMakeLists.txt`: portable core + Apple-only Objective-C++ AppKit target, x86_64/macOS 10.13, strict warnings as errors.
- `include/silveton/manager/ManagerTypes.h`: canonical Manager sample/multisample/SOUND model and preserved raw Korg metadata.
- `include/silveton/manager/KorgImporter.h`, `src/core/KorgImporter.cpp`: KSF/KMP/KSC import, exact zones/dependencies, canonical PCM16LE.
- `include/silveton/manager/SampleHash.h`, `src/core/SampleHash.cpp`: deterministic sample-audio hashing plus exact-byte dedup policy.
- `include/silveton/manager/SvBankFormat.h`, `src/core/SvBankFormat.cpp`: `.sv` v1 explicit little-endian fixed records + SHA-256.
- `include/silveton/manager/SvBankBuilder.h`, `src/core/SvBankBuilder.cpp`: reference validation, string/audio dedup, 4096-byte audio alignment, integrity and atomic writing.
- `include/silveton/manager/SvBankReader.h`, `src/core/SvBankReader.cpp`: bounds/integrity/reference validation and complete project reconstruction.
- `include/silveton/manager/AudioFileLoader.h`, `src/core/AudioFileLoader.cpp`: WAV PCM16/24/Float32, AIFF PCM16/24, AIFC NONE/sowt with supported root/loop metadata.
- `tests/ManagerCoreTests.cpp`: always-active Release regression suite for KSF/KMP/WAV/AIFF, SHA-256, `.sv` round-trip/dedup/corruption/atomic write.

### `src/app/ManagerDocument.mm`
- Real project owner, no placeholder library.
- Imports KMP/KSC/KSF/WAV/WAVE/AIF/AIFF/AIFC through the core.
- KMP/KSC multisamples become real SOUND records with deterministic Bank/Page/Slot addresses.
- Standalone samples become real one-zone multisamples and SOUNDs.
- Real bank build through `SvBankBuilder::writeAtomic`, exposing actual counts/dedup statistics.
- Real clear/status/SOUND list operations.

### `src/app/MainWindowController.mm`
- Native AppKit window with only real controls.
- `Import Samples…` opens the actual importer path and refreshes actual SOUND rows/counts.
- `Clear` clears the real in-memory Manager project after confirmation.
- `Build SILVETON_BANK.sv…` uses the real save path and real `.sv` builder; successful build displays real dedup/build statistics and output path.
- Table content is generated from real imported SOUNDs; no fake CPU/meter/status widgets are present.

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
- Local `.sv` round-trip/exact-audio/dedup/corruption tests PASS.
- Release core + tests build with `-Werror`; `ctest` 1/1 PASS.
- Native AppKit window/document code is committed, but full macOS application build is not yet claimed until AppDelegate/main are committed and Intel macOS CI runs.

## Next
1. Implement AppDelegate and main entry.
2. Fix any Intel/macOS compiler findings from the first real AppKit build.
3. Replace the empty GitHub Actions workflow and run Intel macOS CI.
4. Add folder/batch workflow polish and tablet transfer.
