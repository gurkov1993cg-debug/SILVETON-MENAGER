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

### Native AppKit application
- `src/app/ManagerDocument.mm`: real imports, real SOUND creation, real status/list/clear, real atomic `.sv` build.
- `src/app/MainWindowController.mm`: real Import/Clear/Build controls and real project table/status/path; no fake controls/meters.
- `src/app/AppDelegate.mm`: owns/shows the Manager window and application lifecycle.
- `src/app/main.mm`: native NSApplication entry/event loop.

### `.github/workflows/SILVETON MENAGER.yml`
- Runner `macos-15-intel`, Xcode 16.4, Release x86_64, deployment target 10.13.
- Tests before AppKit build; architecture/deployment/Info.plist/signing/package checks afterward.

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
- Local Linux Release core/tests: PASS, `ctest` 1/1.
- First real Intel run `37092662586`: Xcode 16.4 configure PASS; core compile FAILED in `SvBankBuilder.cpp` because libc++ `std::filesystem` APIs are unavailable for a macOS 10.13 deployment target (introduced 10.15).
- The target was NOT raised. `SvBankBuilder.cpp` now uses macOS-10.13-compatible `std::string` paths plus C/POSIX `rename/remove` for atomic replacement, preserving the 10.13 contract.
- No app-build success is claimed until a subsequent Intel run reaches all compile/link/sign/package checks.

## Next
1. Inspect the next Intel run and fix only the next real failed step/log, if any.
2. Once green, verify/download the packaged `.app` artifact and preserve it as the proven Manager baseline.
3. Add folder/batch workflow polish and tablet transfer.
