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
- Canonical Manager sample/multisample/SOUND data model.
- Korg raw pan/level/filter source metadata retained.

### `include/silveton/manager/KorgImporter.h`
### `src/core/KorgImporter.cpp`
- KSF/KMP/KSC parser.
- KSF PCM16 big-endian -> canonical PCM16LE without resampling.
- Exact KMP key ranges/root/tune/non-transpose/source metadata retained.
- Relative KSC dependencies and KSF lookup implemented.

### `include/silveton/manager/SampleHash.h`
### `src/core/SampleHash.cpp`
- Deterministic FNV-1a sample-audio hash including format metadata.
- Hash only selects dedup candidates; exact byte equality remains mandatory.

### `include/silveton/manager/SvBankFormat.h`
### `src/core/SvBankFormat.cpp`
- `.sv` v1 fixed 256-byte header, seven indexed sections and fixed-size records.
- Explicit little-endian serializer/parser; architecture-independent Intel -> ARM data.
- SHA-256 payload integrity with no external dependency.

### `include/silveton/manager/SvBankBuilder.h`
- Declares in-memory bank build and atomic file-write operations.
- Build statistics expose SOUND/multisample/sample/zone counts and before/after audio dedup byte counts.

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
8. Audio payload section; builder aligns it to 4096 bytes for random access/streaming.

## Verification status
- Development branch exists; `main` untouched.
- Strict local SALEAS Korg import smoke test PASS.
- SHA-256 matches the standard `abc` test vector locally.
- In-progress bank builder/reader locally passes round-trip, exact audio recovery, dedup and corruption rejection.
- Repository-wide build is not yet claimed until all CMake-referenced sources and tests are committed and CI runs.

## Next
1. Commit bank builder implementation and reader contract/implementation.
2. WAV/AIFF importer.
3. Regression tests + clean core build.
4. Native AppKit GUI.
5. Batch import, one-click bank build, tablet transfer.
