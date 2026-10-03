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
- `CMakeLists.txt`: portable core + Apple-only Objective-C++ AppKit target, x86_64/macOS 10.13, strict warnings as errors. `src/core/SampleEditor.cpp` is part of the real core target. ARC (`-fobjc-arc`) is enabled only for the AppKit Manager target so Objective-C object ivars follow the ownership model used by the GUI code; the C++ core is unchanged.
- `include/silveton/manager/ManagerTypes.h`: canonical Manager sample/multisample/SOUND model and preserved raw Korg metadata.
- `include/silveton/manager/KorgImporter.h`, `src/core/KorgImporter.cpp`: KSF/KMP/KSC import, exact zones/dependencies, canonical PCM16LE. Path handling no longer depends on `std::filesystem`; it uses macOS-10.13-compatible string/POSIX path operations while preserving direct and nested KSF resolution and stable source identities.
- `include/silveton/manager/SampleEditor.h`, `src/core/SampleEditor.cpp`: real offline sample-edit core for PCM16LE/PCM24LE/Float32LE project copies. Implements destructive trim, validated loop metadata/crossfade bounds, explicit user-triggered destructive loop-crossfade baking, frame-correct reverse with loop remap, gain, peak normalize, fade in/out, root key, fine tune, peak readback, nearest zero crossing and waveform min/max envelope generation. Source files on disk are not modified by these operations.
- `include/silveton/manager/SampleHash.h`, `src/core/SampleHash.cpp`: deterministic sample-audio hashing plus exact-byte dedup policy.
- `include/silveton/manager/SvBankFormat.h`, `src/core/SvBankFormat.cpp`: `.sv` v1 explicit little-endian fixed records + SHA-256. The SHA-256 round constant at index 53 is corrected to standard `0x4ed8aa4aU`.
- `include/silveton/manager/SvBankBuilder.h`, `src/core/SvBankBuilder.cpp`: reference validation, string/audio dedup, 4096-byte audio alignment, integrity and atomic writing without `std::filesystem`.
- `include/silveton/manager/SvBankReader.h`, `src/core/SvBankReader.cpp`: bounds/integrity/reference validation and complete project reconstruction.
- `include/silveton/manager/AudioFileLoader.h`, `src/core/AudioFileLoader.cpp`: WAV PCM16/24/Float32, AIFF PCM16/24, AIFC NONE/sowt with supported root/loop metadata. Path identity, extension and stem handling use macOS-10.13-compatible string/POSIX operations instead of `std::filesystem`.
- `tests/ManagerCoreTests.cpp`: always-active Release regression suite for KSF/KMP/WAV/AIFF, SampleEditor PCM mutation/no-auto-apply behavior, SHA-256, `.sv` round-trip/dedup/corruption/atomic write. Sample-editor coverage checks setLoop metadata without PCM mutation, explicit real loop-crossfade PCM mutation, fade in/out, trim, reverse, gain, normalize, root key, fine tune, zero crossing and waveform generation.

### Native AppKit application
- `src/app/ManagerDocument.mm`: real imports, real status/list/clear, real atomic `.sv` build, real selected-sample edit bridge and real multisample/zone data bridge. Existing sample operations remain intact. The multisample bridge exposes actual multisample rows/state and actual zone records, supports multisample rename, zone add/remove, sample assignment and direct edits of Key Low/High, Velocity Low/High, Root Key, Transpose, Tune, Gain and Pan. Creating a multisample from selected samples sorts the real samples by Root Key, rejects duplicate Root Keys and creates contiguous key zones using midpoint boundaries between adjacent roots; those zone records are the same records serialized by `SvBankBuilder`. Import and Build never auto-apply sample DSP edits.
- `src/app/MainWindowController.mm`: current checked-in GUI is still the sample-editor window only. It shows the actual sample list, actual waveform min/max data, actual loop markers and numeric controls for Trim, Loop, Loop Crossfade, Fade In/Out, Gain, Normalize, Reverse, Root Key, Fine Tune and explicit Zero-Crossing Snap helpers. At this exact revision there is still no visible multisample keyboard/zone editor; that absence must not be described as complete Manager GUI.
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
- loop start/end/crossfade;
- normalize and gain;
- fade in/out;
- reverse;
- nearest-zero-crossing assistance;
- root key and fine tune.

All destructive sample-edit operations are explicit user actions. Import and `.sv` build do not auto-normalize, auto-trim, auto-fade, auto-crossfade, auto-reverse, auto-snap loop/start/end points or alter root/tune values without the user's command.

Loop crossfade behavior is real: `applyLoopCrossfade()` linearly blends the selected loop tail with the selected loop head per channel and per sample, writes the overlap into the project-copy audio, advances loop start by the overlap length so the fade-in material is not replayed twice, and clears the pending crossfade metadata after the bake. This function is never called automatically.

## Multisample editor scope
The project model and ManagerDocument bridge now support real multisample zone editing:
- actual sample assignment per zone;
- Key Low / Key High;
- Velocity Low / Velocity High;
- Root Key;
- Transpose;
- Tune cents;
- Gain dB;
- Pan;
- zone add/remove;
- multisample rename;
- automatic contiguous key mapping from selected samples using their actual Root Keys.

The visible piano keyboard/key-zone GUI is not yet implemented in `MainWindowController.mm` at this revision. It must read/write these real zone records and must not be a decorative keyboard.

Manager will not duplicate tablet SOUND parameters such as amp/filter/LFO/portamento/TONE/FX.

## Verification status
- Local Linux Release core/tests: PASS, `ctest` 1/1 for the pre-sample-editor core baseline.
- Intel run `37092662586`: Xcode 16.4 configure PASS; core compile FAILED in `SvBankBuilder.cpp` because libc++ `std::filesystem` is unavailable for deployment target macOS 10.13. `SvBankBuilder.cpp` was corrected without raising the target.
- Intel run `37092813628`: configuration PASS and `SvBankBuilder.cpp` progressed past the prior failure; next failure was `KorgImporter.cpp` for the same macOS 10.13 `std::filesystem` availability rule. `KorgImporter.cpp` was corrected without raising the target.
- Intel run `37108737366` / run 48: `KorgImporter.cpp`, `SvBankBuilder.cpp`, `SvBankReader.cpp`, `SvBankFormat.cpp` progressed through compile. The next real failure was isolated to `tests/ManagerCoreTests.cpp`, where the test fixture still used `std::filesystem` APIs unavailable for a macOS 10.13 deployment target.
- `tests/ManagerCoreTests.cpp` commit `73ff5b5999240b724483556ae185adb397284f45` removes only that test-side incompatibility: string/POSIX temp path creation, file names and cleanup replace `std::filesystem`; the actual regression assertions and Manager behavior are preserved.
- Intel run `37109218356` / run 49: configuration PASS and `ManagerCoreTests.cpp` progressed past the prior failure. The next real compile failure was `src/core/AudioFileLoader.cpp`, where source identity, extension and stem helpers still used `std::filesystem` unavailable at macOS 10.13.
- `src/core/AudioFileLoader.cpp` commit `52947cf4a95ab9784a9f643cb6bea12234173c84` removes only that path-library incompatibility. WAV/AIFF parsing, root/loop metadata, PCM conversion and public API remain unchanged.
- Sample-editor implementation commit `f79a7e33bf1112585cd91a479b975050eda05801` is present.
- Real user-applied loop-crossfade implementation commit `eafe4a8776603103883e31a7f8fdfa482c91340f` is present.
- `SampleEditor.cpp` was added to the core build target in commit `2819851c494639ad3429e1761ec566caeb4b4a0e`.
- Sample-editor regression coverage commit `099babef24741c2b34971eaaa698e4640a4745c5` is present and explicitly checks that editing is user-triggered and PCM changes are real.
- Intel run `37110792932` / run 63: strict x86_64/macOS 10.13 core build including `SampleEditor.cpp` and the expanded regression test executable SUCCEEDED. CTest then failed at the independent SHA-256 standard-vector assertion before the later bank/app stages. The exact source cause was the incorrect SHA-256 K constant `0x4ed8aa4U` in `SvBankFormat.cpp`; it must be `0x4ed8aa4aU`.
- `SvBankFormat.cpp` commit `ae378ab9f1fd5673db7949db25582e6b73eb11bf` corrects only that SHA-256 round constant; the `.sv` API/layout and sample editor are unchanged.
- Intel run `37111451698` / run 69: strict x86_64/macOS 10.13 configuration PASS, core build PASS, expanded sample-editor regression tests PASS (`ctest` 1/1). The AppKit app build then failed only in `MainWindowController.mm` because `NSTextField` does not provide `unsignedLongLongValue`; 12 occurrences affected Trim/Loop/Crossfade/Fade/Zero-Crossing GUI parsing. Core/DSP code was not the cause.
- `MainWindowController.mm` commit `fa1d3537dbea13c001d2793769f5272701a88614` replaces only those unsupported field conversions with explicit validated non-negative uint64 parsing and keeps every edit user-triggered. DSP/editor algorithms, public ManagerDocument bridge and other GUI controls are unchanged.
- Intel run `37111941671` / run 71: complete CI SUCCESS — configure, core build, regression tests, AppKit app build, x86_64/macOS 10.13 verification, ad-hoc signing, packaging and artifact upload all passed. This proves build/package correctness only, not GUI runtime compatibility.
- Physical iMac 2011 / macOS 10.13.6 launch test then FAILED before the GUI became usable. Crash report: `EXC_BAD_ACCESS` on main thread, `objc_msgSend` selector `count`, frame `-[SVMainWindowController tableView:viewForTableColumn:row:]`. The application is confirmed x86-64 native on macOS 10.13.6.
- Root cause: Objective-C++ AppKit code uses ARC-style object ivars, while the Manager target had no ARC compile flag. `sampleDisplayRows` returns an autoreleased `NSMutableArray`; `_sampleRows` stored it in a raw ivar and AppKit later sent `count` after the object lifetime had ended.
- `CMakeLists.txt` commit `ab16701d4a9c6bbfdace99d1bf32d89a4fe45a43` enables `-fobjc-arc` only for `SILVETON_MANAGER`. No C++ core, sample-editor DSP/API, bank format or GUI control logic is changed. A new Intel CI run and another physical High Sierra open test are required before calling the GUI runtime proven.
- `ManagerDocument.mm` sample-edit bridge commit `9c1be226146a8ac2125e822f728e93cf74c4d549` is present.
- `MainWindowController.mm` real waveform/editor GUI wiring commit `5eecd85c88899a6c4463098369d315c5040fdc4a` is present.
- `ManagerDocument.mm` commit `3c6418df8038055e8973e536280e76474a3ecf74` adds the real multisample/zone editing bridge described above. This commit is not yet a proven GUI feature and still requires Intel CI plus visible keyboard/zone wiring in `MainWindowController.mm`.

## Next
1. Wire `MainWindowController.mm` to the real multisample/zone bridge: multisample list, zone list, 128-note key map/piano keyboard and editable zone parameters.
2. Run the exact branch through Intel x86_64/macOS 10.13 CI and fix only real compile/test failures.
3. Install/open the exact successful artifact on the physical iMac 2011/macOS 10.13.6 and verify the window, sample editor and multisample keyboard/zone editor remain usable without crash.
4. Import the real KMP fixture and prove that the visible key map represents its real zones; edit a zone and verify the built `.sv` contains the changed zone values.
