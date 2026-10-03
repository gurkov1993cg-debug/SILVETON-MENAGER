# SILVETON MANAGER — STRUCTURE

Updated: 2026-10-03

## Repository
- `gurkov1993cg-debug/SILVETON-MENAGER`
- Active development branch: `silveton-manager-development`
- `main` is preserved and is not used as the working branch for the initial implementation.

## Target
- Native desktop application for Intel iMac 2011.
- Architecture: x86_64 only.
- Language baseline: C++17 core + Objective-C++/AppKit GUI.
- Minimum macOS deployment target: 10.13.
- No JUCE and no browser/Electron GUI runtime.

## Product role
SILVETON Manager performs the heavy offline preparation work for SILVETON Sampler:

`import -> analysis -> multisample building -> SOUND building -> deduplication -> SILVETON_BANK.sv`

The Android tablet remains the live-performance runtime and must not rebuild KMP/KSC/sample structures at startup.

## Current implemented repository files

### `CMakeLists.txt`
- Defines the Intel x86_64 / macOS 10.13 build contract.
- Uses C++17.
- Declares `silveton_manager_core` as the platform-independent Manager core library.
- Declares the native AppKit application target `SILVETON Manager`.
- Declares the Manager core regression-test target.
- Enables strict compiler warnings for the core and tests.

### `include/silveton/manager/ManagerTypes.h`
- Defines the Manager-side import and bank model.
- Defines canonical bank audio encodings: PCM16LE, PCM24LE and Float32LE.
- Defines sample metadata, loop metadata, multisample zones, SOUND layers and bank/page/slot addresses.
- Preserves raw Korg RLP1 pan/level/filter source values instead of replacing them with undocumented conversions.
- Keeps canonical audio bytes separate from source-path metadata so later `.sv` building can deduplicate payloads safely.

### `include/silveton/manager/KorgImporter.h`
- Declares KSF, KMP and KSC import results and entry points.
- Exposes normalized pan only as an editor/runtime view while preserving the original raw Korg pan value.
- Keeps import warnings separate from hard errors so missing/unsupported regions cannot silently become fake samples.

### `src/core/KorgImporter.cpp`
- Implements chunk-safe KSF/KMP/KSC parsing.
- KSF import validates SMP1/SMD1, sample rate, channels, 16-bit uncompressed payload length and loop bounds.
- Converts KSF big-endian PCM16 into canonical little-endian PCM16 for `.sv` storage without resampling.
- KMP import preserves skipped/internal regions, exact key ranges, root key, tune, non-transpose and raw pan/level/filter metadata.
- Resolves external KSF files beside the KMP or in the common same-name nested directory.
- KSC import resolves relative KMP/KSF entries and avoids duplicate standalone KSF imports already referenced by a KMP.

### `include/silveton/manager/SampleHash.h`
- Declares deterministic FNV-1a hashing for canonical sample audio plus format metadata.
- Hashing is used as a fast dedup candidate key; exact byte comparison remains mandatory before payload sharing.

## Planned source layout already reserved by CMake

### Core
- `include/silveton/manager/...`
- `src/core/AudioFileLoader.cpp`
- `src/core/KorgImporter.cpp`
- `src/core/SvBankBuilder.cpp`
- `src/core/SvBankFormat.cpp`
- `src/core/SvBankReader.cpp`
- `src/core/SampleHash.cpp`

### Native macOS application
- `src/app/main.mm`
- `src/app/AppDelegate.mm`
- `src/app/MainWindowController.mm`
- `src/app/ManagerDocument.mm`

### Tests
- `tests/ManagerCoreTests.cpp`

## Donor source policy
The Manager reuses only proven sampler-side parsing/loading concepts that are appropriate for offline desktop preparation. The current SILVETON Sampler R4 source is the donor reference for KMP/KSF/KSC import, WAV/AIFF loading and compatible sample/multisample metadata. Android runtime, Direct-ALSA, Direct-MIDI, COMBI GUI and realtime tablet code are not copied into Manager.

## Real Korg regression fixture
User-provided `SALEAS-GRK SH.kmp` plus `MS000000.KSF` ... `MS000012.KSF` is the first real import fixture.
Verified facts: 14 RLP1 regions total; region 0 is `SKIPPEDSAMPL` for keys 0..1; 13 external KSF samples produce 13 zones; files are 48 kHz/16-bit/mono; first playable zone is C4/root 60 at keys 2..61; playable raw pan is 64 and is preserved; no false forward loop is created.

## SILVETON_BANK.sv contract direction
One master bank remains the target. Logical sections: header, SOUND index, SOUND layers, multisample index, sample index, zone records, strings, deduplicated audio and integrity/version data.

## Verification status
- Development branch exists and `main` remains untouched.
- CMake baseline, Manager data model, Korg importer and hash contract are committed.
- Local strict Korg smoke test passes against SALEAS-GRK.
- Local in-progress `.sv` core test already passes SHA-256, build/read round-trip, exact audio recovery, duplicate audio elimination and corrupt-bank rejection; those format/builder/reader files are being committed next.
- Repository-wide build is not yet claimed until every CMake-referenced source exists and CI runs.

## Next implementation order
1. Commit sample hash implementation and `.sv` format/builder/reader.
2. Adapt WAV/AIFF import.
3. Commit regression tests and make the core target build cleanly.
4. Build native AppKit GUI around the proven core.
5. Add batch import, one-click bank build and tablet transfer workflow.
