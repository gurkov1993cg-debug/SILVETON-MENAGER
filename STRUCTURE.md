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
`import -> sample edit -> multisample building -> bank/library organization -> deduplication -> SILVETON_BANK.sv`

SOUND editing is intentionally not duplicated in Manager. SOUND editing stays in SILVETON Sampler on the tablet. Manager owns sample editing, multisample editing and bank/library preparation.

Tablet runtime must only open the prepared bank/index and stream audio; it must not rebuild KMP/KSC structures on startup.

## Implemented files
- `CMakeLists.txt`: portable core + Apple-only Objective-C++ AppKit target, x86_64/macOS 10.13, strict warnings as errors.
- `include/silveton/manager/ManagerTypes.h`: canonical Manager sample/multisample/SOUND model and preserved raw Korg metadata.
- `include/silveton/manager/KorgImporter.h`, `src/core/KorgImporter.cpp`: KSF/KMP/KSC import, exact zones/dependencies, canonical PCM16LE. Path handling no longer depends on `std::filesystem`; it uses macOS-10.13-compatible string/POSIX path operations while preserving direct and nested KSF resolution and stable source identities.
- `include/silveton/manager/SampleEditor.h`: sample-editor public contract for destructive trim, loop metadata, reverse, gain, normalize, fades, root key, fine tune, peak readback, nearest zero crossing and waveform-envelope generation. Implementation is being added without duplicating tablet SOUND controls.
- `include/silveton/manager/SampleHash.h`, `src/core/SampleHash.cpp`: deterministic sample-audio hashing plus exact-byte dedup policy.
- `include/silveton/manager/SvBankFormat.h`, `src/core/SvBankFormat.cpp`: `.sv` v1 explicit little-endian fixed records + SHA-256.
- `include/silveton/manager/SvBankBuilder.h`, `src/core/SvBankBuilder.cpp`: reference validation, string/audio dedup, 4096-byte audio alignment, integrity and atomic writing without `std::filesystem`.
- `include/silveton/manager/SvBankReader.h`, `src/core/SvBankReader.cpp`: bounds/integrity/reference validation and complete project reconstruction.
- `include/silveton/manager/AudioFileLoader.h`, `src/core/AudioFileLoader.cpp`: WAV PCM16/24/Float32, AIFF PCM16/24, AIFC NONE/sowt with supported root/loop metadata. Path identity, extension and stem handling now use macOS-10.13-compatible string/POSIX operations instead of `std::filesystem`.
- `tests/ManagerCoreTests.cpp`: always-active Release regression suite for KSF/KMP/WAV/AIFF, SHA-256, `.sv` round-trip/dedup/corruption/atomic write. Test fixture path handling now uses macOS-10.13-compatible string/POSIX temp-directory operations instead of `std::filesystem`.

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

## Sample editor scope
Manager sample editing is the authoritative desktop editing layer for:
- waveform visualization;
- trim start/end;
- loop start/end/crossfade metadata;
- normalize and gain;
- fade in/out;
- reverse;
- nearest-zero-crossing assistance;
- root key and fine tune.

Manager will not duplicate tablet SOUND parameters such as amp/filter/LFO/portamento/TONE/FX.

## Verification status
- Local Linux Release core/tests: PASS, `ctest` 1/1 for the pre-sample-editor core baseline.
- Intel run `37092662586`: Xcode 16.4 configure PASS; core compile FAILED in `SvBankBuilder.cpp` because libc++ `std::filesystem` is unavailable for deployment target macOS 10.13. `SvBankBuilder.cpp` was corrected without raising the target.
- Intel run `37092813628`: configuration PASS and `SvBankBuilder.cpp` progressed past the prior failure; next failure was `KorgImporter.cpp` for the same macOS 10.13 `std::filesystem` availability rule. `KorgImporter.cpp` was corrected without raising the target.
- Intel run `37108737366` / run 48: `KorgImporter.cpp`, `SvBankBuilder.cpp`, `SvBankReader.cpp`, `SvBankFormat.cpp` progressed through compile. The next real failure was isolated to `tests/ManagerCoreTests.cpp`, where the test fixture still used `std::filesystem` APIs unavailable for a macOS 10.13 deployment target.
- `tests/ManagerCoreTests.cpp` commit `73ff5b5999240b724483556ae185adb397284f45` removes only that test-side incompatibility: string/POSIX temp path creation, file names and cleanup replace `std::filesystem`; the actual regression assertions and Manager behavior are preserved.
- Intel run `37109218356` / run 49: configuration PASS and `ManagerCoreTests.cpp` progressed past the prior failure. The next real compile failure is `src/core/AudioFileLoader.cpp`, where source identity, extension and stem helpers still used `std::filesystem` unavailable at macOS 10.13.
- `src/core/AudioFileLoader.cpp` commit `52947cf4a95ab9784a9f643cb6bea12234173c84` removes only that path-library incompatibility. WAV/AIFF parsing, root/loop metadata, PCM conversion and public API remain unchanged.
- Sample-editor API added; implementation and regression coverage are not yet claimed as verified until their build/tests run.
- No app-build success is claimed until a subsequent Intel run reaches compile/link/test/sign/package checks.

## Next
1. Implement and test `SampleEditor` core operations without changing the tablet SOUND contract.
2. Wire the verified sample editor core to the native waveform GUI.
3. Add multisample keyboard/velocity-zone editor.
4. Continue Intel build/test/sign/package verification and fix only the next real failed step/log.
