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
- Intel x86_64 / macOS 10.13 / C++17 build contract.
- Platform-independent Manager core, native AppKit target and regression-test target.
- Strict compiler warnings enabled.

### `include/silveton/manager/ManagerTypes.h`
- Manager import/bank model, canonical PCM encodings, loops, samples, zones, SOUND layers and bank/page/slot addressing.
- Raw Korg RLP1 pan/level/filter values are preserved without undocumented transfer functions.

### `include/silveton/manager/KorgImporter.h`
- KSF/KMP/KSC import contract with separate hard errors and warnings.

### `src/core/KorgImporter.cpp`
- Chunk-safe KSF/KMP/KSC parsing.
- KSF big-endian PCM16 becomes canonical little-endian PCM16 without resampling.
- Exact KMP zone/root/tune/non-transpose and raw source metadata are retained.
- External KSF resolution and KSC relative dependency loading are implemented.

### `include/silveton/manager/SampleHash.h`
- Deterministic sample-audio hash contract.

### `src/core/SampleHash.cpp`
- FNV-1a 64-bit hashing includes sample rate, channels, encoding, bit depth, frame count and canonical audio bytes.
- Hash is only a fast dedup candidate key; bank builder still requires exact metadata/audio byte equality before sharing payload data.

## Planned/active source layout

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
The Manager reuses only proven sampler-side parsing/loading concepts appropriate for offline desktop preparation. Android runtime, Direct-ALSA, Direct-MIDI, COMBI GUI and realtime tablet code are not copied into Manager.

## Real Korg regression fixture
User-provided `SALEAS-GRK SH.kmp` plus `MS000000.KSF` ... `MS000012.KSF` is the first real import fixture.
Verified: 14 RLP1 regions; region 0 is `SKIPPEDSAMPL` for keys 0..1; 13 external KSF files produce 13 playable zones; 48 kHz/16-bit/mono; first playable zone C4/root 60 on keys 2..61; playable raw pan is 64 and is preserved/normalized to centre; no false forward loop is created.

## SILVETON_BANK.sv direction
One master bank. Logical sections: fixed header, SOUND records, SOUND layers, multisample records, sample records, zone records, string table, deduplicated audio payload and integrity/version data.

## Verification status
- Development branch exists and `main` remains untouched.
- CMake baseline, Manager data model, Korg importer and deterministic sample hash are committed.
- Local strict Korg smoke test passes against SALEAS-GRK.
- Local in-progress `.sv` core test passes SHA-256 known vector, build/read round-trip, exact audio recovery, duplicate audio elimination and corrupt-bank rejection; format/builder/reader files are being committed next.
- Repository-wide build is not yet claimed until every CMake-referenced source exists and CI runs.

## Next implementation order
1. Commit `.sv` format/builder/reader.
2. Adapt WAV/AIFF import.
3. Commit regression tests and make core target build cleanly.
4. Build native AppKit GUI around proven core.
5. Add batch import, one-click bank build and tablet transfer workflow.
