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
The Manager will reuse only proven sampler-side parsing/loading concepts that are appropriate for offline desktop preparation. The current SILVETON Sampler R4 source is the donor reference for:
- KMP/KSF/KSC import logic.
- WAV/AIFF/audio loading logic.
- sample metadata and multisample-zone structures where compatible.

The Manager will not copy Android runtime, Direct-ALSA, Direct-MIDI, COMBI GUI, or realtime tablet code.

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
- No successful Manager build is claimed yet because the source files referenced by the new CMake target are the next implementation work.

## Next implementation order
1. Define the stable `.sv` binary types and format contract.
2. Add deterministic sample hashing/dedup identity.
3. Port/adapt audio loading and Korg KMP/KSF/KSC parsing from the sampler donor source.
4. Implement bank builder and bank reader with integrity/offset validation.
5. Add regression tests for exact round-trip, corrupt-bank rejection, duplicate-sample elimination, ranges and metadata.
6. Build the native AppKit Manager GUI around the proven core.
7. Add batch import and one-click `SILVETON_BANK.sv` build workflow.
8. Add transfer workflow to the tablet after the bank format is proven.
