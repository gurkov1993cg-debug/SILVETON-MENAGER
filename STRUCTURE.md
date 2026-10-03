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
The Manager reuses only proven sampler-side parsing/loading concepts that are appropriate for offline desktop preparation. The current SILVETON Sampler R4 source is the donor reference for:
- KMP/KSF/KSC import logic.
- WAV/AIFF/audio loading logic.
- sample metadata and multisample-zone structures where compatible.

The Manager does not copy Android runtime, Direct-ALSA, Direct-MIDI, COMBI GUI, or realtime tablet code.

## Real Korg regression fixture
User-provided `SALEAS-GRK SH.kmp` plus `MS000000.KSF` ... `MS000012.KSF` is the first real import fixture.
Verified facts from the fixture:
- 14 KMP RLP1 regions total.
- Region 0 is `SKIPPEDSAMPL` and covers MIDI keys 0..1.
- 13 external KSF samples remain and produce 13 playable zones.
- Samples are 48 kHz, 16-bit, mono PCM.
- The first real zone uses C4/root 60 and covers keys 2..61.
- All playable regions carry raw pan value 64; this raw value is preserved exactly and normalizes to centre.
- The first KSF has no valid forward loop, so the importer does not invent one.

## SILVETON_BANK.sv contract direction
The final Manager output remains one master bank file rather than one file per SOUND.

Required logical sections:
- header
- SOUND index
- multisample index
- sample index
- SOUND records
- multisample-zone records
- deduplicated audio payload
- integrity/version information

Exact binary structures are not yet claimed as finalized until the format implementation and round-trip tests are in the repository.

## Verification status
- Repository inspected: it initially contained only `.github/workflows/SILVETON MENAGER.yml`, which was effectively empty.
- Development branch created successfully.
- Root CMake baseline committed.
- Manager data model committed.
- Korg importer contract and implementation committed.
- Local strict smoke test against the real SALEAS-GRK fixture passes: 13 samples, 13 zones, C4 root 60, first real zone 2..61, raw pan 64 -> centre, 48 kHz/16-bit/mono, no false loop.
- The Manager core has not yet completed a repository-wide build because the remaining CMake-referenced sources are still being implemented.

## Next implementation order
1. Define and implement the stable `.sv` binary types and format contract.
2. Add deterministic sample hashing/dedup identity.
3. Adapt WAV/AIFF import.
4. Implement bank builder and bank reader with integrity/offset validation.
5. Add regression tests for exact round-trip, corrupt-bank rejection, duplicate-sample elimination, ranges and metadata.
6. Build the native AppKit Manager GUI around the proven core.
7. Add batch import and one-click `SILVETON_BANK.sv` build workflow.
8. Add transfer workflow to the tablet after the bank format is proven.
