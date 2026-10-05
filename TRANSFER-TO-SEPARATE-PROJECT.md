# SILVETON Manager — transfer state

Date: 2026-10-05

## Canonical project

Repository: `gurkov1993cg-debug/SILVETON-MENAGER`

The repository is already separate from the tablet sampler project. The current repository source archive is `silveton-manager.zip`.

Target:
- native desktop application for macOS;
- Intel x86_64;
- macOS 10.13 deployment target;
- C++17 core;
- Objective-C++ only where macOS/AppKit integration is needed;
- no JUCE.

## Latest product direction

SILVETON Manager is not only a converter. It is the desktop preparation/editor application for the sampler library.

The current direction is:

`IMPORT -> SAMPLE EDIT -> MULTISAMPLE -> SOUND -> DEDUP -> SILVETON_BANK.sv`

The tablet must stay a performance device. Heavy sample preparation belongs in Manager.

### Import

Manager must accept batch input, including KMP, KSF, KSC and WAV/raw sample collections. Korg import must resolve KMP -> KSF dependencies and preserve real metadata rather than guessing: sample identity, Root Key, Key Low/High, Velocity Low/High, tune, level, loop start/end, sample assignment and multisample zones.

### Sample editor

Manager must be a full sample editor, not a duplicated SOUND editor from the tablet. Sample-edit operations are user initiated only. They must never modify material automatically without an explicit user action.

Required editing direction includes waveform/sample selection, trim/cut-style editing, loop start/end editing, loop audition, fade-in/fade-out and loop crossfade. Crossfade/fades/loop processing are optional tools selected by the user, not automatic repair functions.

### Bank architecture

The target output is one master file:

`SILVETON_BANK.sv`

The bank contains ready SOUND records, multisample definitions, zone data and sample audio data. The agreed high-level structure is:

- HEADER
- SOUND/PROGRAM INDEX
- MULTISAMPLE INDEX
- SAMPLE INDEX
- SOUND DATA
- MULTISAMPLE ZONES
- AUDIO DATA

The header/index contract must contain magic/version/counts/offsets/sizes and integrity information as needed. Index records must provide direct offsets so the tablet does not scan the whole bank when switching sounds.

Duplicate sample audio must be stored once and referenced from all SOUND/multisample objects that use it.

## Current code areas

The current Manager source contains/uses the following major areas:

- `SvBankFormat` — .sv binary format contract
- `SvBankBuilder` — bank writer/builder
- `SvBankReader` — bank reader
- `ManagerTypes` — Manager data model
- `KorgImporter` — KMP/KSF/KSC import path
- `AudioFileLoader`
- `SampleConverter`
- `SampleHash`
- `SampleEditor`
- `SoundEditor`
- `ObjectManager`
- `MediaPathPolicy`
- macOS app layer including `ManagerDocument`, `MainWindowController`, `GUIIntegration`, `FinalGUITheme`
- Manager core/document tests

## Latest known integration issue

The latest available build log after adding Sample Editor workspace integration reaches the macOS app build and fails in `src/app/GUIIntegration.mm` because it calls:

`[main showSampleWorkspace];`

but the compiler does not know that selector on the visible `MainWindowController` interface/category declaration. The failure is a compile-time interface declaration/integration issue, not evidence that the Sample Editor core is absent.

The transfer project should keep this issue explicit and fix the declaration/wiring before treating the latest Sample Editor GUI integration as build-proven.

## Next real integration test

Create one real test blend in Manager, export it into `SILVETON_BANK.sv`, copy the bank to the tablet and verify the complete path:

`Manager -> .sv writer -> tablet .sv reader -> SOUND/COMBI -> MIDI -> audio`

This is the first useful end-to-end proof of the Manager/bank contract.

## Truth boundary

Do not claim a feature is physically verified just because its source exists. Keep separate states for:
- present in source;
- build-proven;
- tested on Mac;
- tested through the real SM-X130 sampler runtime.
