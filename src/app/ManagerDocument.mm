#import <Foundation/Foundation.h>

#include "silveton/manager/AudioFileLoader.h"
#include "silveton/manager/KorgImporter.h"
#include "silveton/manager/SampleEditor.h"
#include "silveton/manager/SvBankBuilder.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <deque>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

namespace {
using namespace silveton::manager;

struct SampleHistoryEntry {
    std::size_t sampleIndex{0U};
    ImportedSample sample{};
    std::size_t storageBytes{0U};
};

constexpr std::size_t kMaxSampleHistoryEntries = 16U;
constexpr std::size_t kMaxSampleHistoryBytes = 256U * 1024U * 1024U;
constexpr std::uint16_t kLibraryAxisMaximum = 127U;

std::size_t filenameStart(const std::string& path) noexcept {
    const std::size_t slash = path.find_last_of("/\\");
    return slash == std::string::npos ? 0U : slash + 1U;
}

std::string filenameOnly(const std::string& path) {
    return path.substr(filenameStart(path));
}

std::string lowerExtension(const std::string& path) {
    const std::size_t start = filenameStart(path);
    const std::size_t dot = path.find_last_of('.');
    std::string ext;
    if (dot != std::string::npos && dot >= start) ext = path.substr(dot);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext;
}

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
}

void setError(NSString** error, const std::string& message) {
    if (error != nullptr) *error = nsString(message);
}

void clearError(NSString** error) {
    if (error != nullptr) *error = nil;
}

std::size_t sampleStorageBytes(const ImportedSample& sample) noexcept {
    return sizeof(ImportedSample) + sample.audioData.size() + sample.name.size() + sample.sourcePath.size() + sample.sourceIdentity.size();
}

void clearHistory(std::deque<SampleHistoryEntry>& history, std::size_t& historyBytes) noexcept {
    history.clear();
    historyBytes = 0U;
}

void trimHistory(std::deque<SampleHistoryEntry>& history, std::size_t& historyBytes) noexcept {
    while (history.size() > kMaxSampleHistoryEntries ||
           (historyBytes > kMaxSampleHistoryBytes && history.size() > 1U)) {
        historyBytes -= history.front().storageBytes;
        history.pop_front();
    }
}

void pushHistory(std::deque<SampleHistoryEntry>& history,
                 std::size_t& historyBytes,
                 std::size_t sampleIndex,
                 const ImportedSample& sample) {
    SampleHistoryEntry entry{};
    entry.sampleIndex = sampleIndex;
    entry.sample = sample;
    entry.storageBytes = sampleStorageBytes(entry.sample);
    historyBytes += entry.storageBytes;
    history.push_back(std::move(entry));
    trimHistory(history, historyBytes);
}

void commitSampleEdit(BankProject& project,
                      std::size_t sampleIndex,
                      ImportedSample edited,
                      std::deque<SampleHistoryEntry>& undoHistory,
                      std::size_t& undoBytes,
                      std::deque<SampleHistoryEntry>& redoHistory,
                      std::size_t& redoBytes) {
    pushHistory(undoHistory, undoBytes, sampleIndex, project.samples[sampleIndex]);
    clearHistory(redoHistory, redoBytes);
    project.samples[sampleIndex] = std::move(edited);
}

bool validSampleIndex(const BankProject& project, NSUInteger index) noexcept {
    return static_cast<std::size_t>(index) < project.samples.size();
}

bool validMultisampleIndex(const BankProject& project, NSUInteger index) noexcept {
    return static_cast<std::size_t>(index) < project.multisamples.size();
}

bool validZoneIndex(const BankProject& project, NSUInteger multisampleIndex, NSUInteger zoneIndex) noexcept {
    if (!validMultisampleIndex(project, multisampleIndex)) return false;
    return static_cast<std::size_t>(zoneIndex) < project.multisamples[static_cast<std::size_t>(multisampleIndex)].zones.size();
}

bool validSoundIndex(const BankProject& project, NSUInteger index) noexcept {
    return static_cast<std::size_t>(index) < project.sounds.size();
}

template <typename EditFunction>
bool applySampleEdit(BankProject& project,
                     NSUInteger index,
                     std::deque<SampleHistoryEntry>& undoHistory,
                     std::size_t& undoBytes,
                     std::deque<SampleHistoryEntry>& redoHistory,
                     std::size_t& redoBytes,
                     NSString** error,
                     EditFunction&& edit) {
    if (!validSampleIndex(project, index)) {
        if (error != nullptr) *error = @"No sample is selected.";
        return false;
    }
    const std::size_t sampleIndex = static_cast<std::size_t>(index);
    ImportedSample edited = project.samples[sampleIndex];
    std::string editError;
    if (!edit(edited, editError)) {
        setError(error, editError);
        return false;
    }
    commitSampleEdit(project, sampleIndex, std::move(edited), undoHistory, undoBytes, redoHistory, redoBytes);
    clearError(error);
    return true;
}

void assignAutomaticAddress(SoundDefinition& sound, std::size_t index) {
    constexpr std::size_t kSlotsPerPage = 128U;
    constexpr std::size_t kPagesPerBank = 128U;
    sound.slot = static_cast<std::uint16_t>(index % kSlotsPerPage);
    const std::size_t pageIndex = index / kSlotsPerPage;
    sound.page = static_cast<std::uint16_t>(pageIndex % kPagesPerBank);
    sound.bank = static_cast<std::uint16_t>(pageIndex / kPagesPerBank);
}

void appendSoundForMultisample(BankProject& project, std::uint32_t multisampleIndex, const std::string& name) {
    SoundDefinition sound{};
    sound.name = name.empty() ? std::string("Imported SOUND") : name;
    assignAutomaticAddress(sound, project.sounds.size());
    SoundLayer layer{};
    layer.multisampleIndex = multisampleIndex;
    sound.layers.push_back(layer);
    project.sounds.push_back(std::move(sound));
}

void appendKmp(BankProject& project, KorgImportResult imported) {
    const std::uint32_t sampleBase = static_cast<std::uint32_t>(project.samples.size());
    for (auto& zone : imported.multisample.zones) zone.sampleIndex += sampleBase;
    for (auto& sample : imported.samples) project.samples.push_back(std::move(sample));
    const std::uint32_t multisampleIndex = static_cast<std::uint32_t>(project.multisamples.size());
    const std::string name = imported.multisample.name;
    project.multisamples.push_back(std::move(imported.multisample));
    appendSoundForMultisample(project, multisampleIndex, name);
}

void appendKsc(BankProject& project, KorgCollectionResult imported) {
    const std::uint32_t sampleBase = static_cast<std::uint32_t>(project.samples.size());
    const std::uint32_t multisampleBase = static_cast<std::uint32_t>(project.multisamples.size());
    for (auto& multisample : imported.multisamples) {
        for (auto& zone : multisample.zones) zone.sampleIndex += sampleBase;
    }
    for (auto& sample : imported.samples) project.samples.push_back(std::move(sample));
    for (std::size_t i = 0U; i < imported.multisamples.size(); ++i) {
        const std::string name = imported.multisamples[i].name;
        project.multisamples.push_back(std::move(imported.multisamples[i]));
        appendSoundForMultisample(project, multisampleBase + static_cast<std::uint32_t>(i), name);
    }
}

void appendSingleSample(BankProject& project, ImportedSample sample) {
    const std::uint32_t sampleIndex = static_cast<std::uint32_t>(project.samples.size());
    const std::string name = sample.name.empty() ? std::string("Imported Sample") : sample.name;
    const std::uint8_t root = sample.rootKey;
    project.samples.push_back(std::move(sample));

    ImportedMultisample multisample{};
    multisample.name = name;
    multisample.sourceIdentity = std::string("single:") + project.samples.back().sourceIdentity;
    ImportedZone zone{};
    zone.sampleIndex = sampleIndex;
    zone.rootKey = root;
    multisample.zones.push_back(zone);

    const std::uint32_t multisampleIndex = static_cast<std::uint32_t>(project.multisamples.size());
    project.multisamples.push_back(std::move(multisample));
    appendSoundForMultisample(project, multisampleIndex, name);
}

std::string joinMessages(const std::vector<std::string>& messages) {
    std::ostringstream stream;
    for (std::size_t i = 0U; i < messages.size(); ++i) {
        if (i != 0U) stream << '\n';
        stream << messages[i];
    }
    return stream.str();
}

bool soundAddressInUse(const BankProject& project,
                       std::uint16_t bank,
                       std::uint16_t page,
                       std::uint16_t slot,
                       std::size_t excludingIndex) noexcept {
    for (std::size_t i = 0U; i < project.sounds.size(); ++i) {
        if (i == excludingIndex) continue;
        const auto& sound = project.sounds[i];
        if (sound.bank == bank && sound.page == page && sound.slot == slot) return true;
    }
    return false;
}

bool nextLibraryAddress(std::uint16_t& bank, std::uint16_t& page, std::uint16_t& slot) noexcept {
    if (slot < kLibraryAxisMaximum) { ++slot; return true; }
    slot = 0U;
    if (page < kLibraryAxisMaximum) { ++page; return true; }
    page = 0U;
    if (bank < kLibraryAxisMaximum) { ++bank; return true; }
    return false;
}

} // namespace

@interface SVManagerDocument : NSObject {
@private
    silveton::manager::BankProject _project;
    std::deque<SampleHistoryEntry> _undoHistory;
    std::deque<SampleHistoryEntry> _redoHistory;
    std::size_t _undoHistoryBytes;
    std::size_t _redoHistoryBytes;
    silveton::manager::SampleRegion _sampleClipboard;
    bool _hasSampleClipboard;
}
- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (NSArray<NSString*>*)displayRows;
- (NSString*)statusSummary;
- (void)clearProject;

- (NSUInteger)sampleCount;
- (NSArray<NSString*>*)sampleDisplayRows;
- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index;
- (NSDictionary<NSString*, id>*)auditionStateAtIndex:(NSUInteger)index error:(NSString**)error;
- (NSArray<NSNumber*>*)waveformAtIndex:(NSUInteger)index pointCount:(NSUInteger)pointCount error:(NSString**)error;
- (BOOL)trimSampleAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)setLoopForSampleAtIndex:(NSUInteger)index enabled:(BOOL)enabled startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)applyLoopCrossfadeForSampleAtIndex:(NSUInteger)index frames:(uint32_t)frames error:(NSString**)error;
- (BOOL)reverseSampleAtIndex:(NSUInteger)index error:(NSString**)error;
- (BOOL)applyGainForSampleAtIndex:(NSUInteger)index gainDb:(float)gainDb error:(NSString**)error;
- (BOOL)normalizeSampleAtIndex:(NSUInteger)index targetPeakDb:(float)targetPeakDb error:(NSString**)error;
- (BOOL)fadeInSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error;
- (BOOL)fadeOutSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error;
- (BOOL)setRootKeyForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey error:(NSString**)error;
- (BOOL)setFineTuneForSampleAtIndex:(NSUInteger)index cents:(float)cents error:(NSString**)error;
- (BOOL)setTuningForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey cents:(float)cents error:(NSString**)error;
- (uint64_t)nearestZeroCrossingForSampleAtIndex:(NSUInteger)index frame:(uint64_t)frame radius:(uint64_t)radius;
- (BOOL)canUndoSampleEdit;
- (BOOL)canRedoSampleEdit;
- (BOOL)undoSampleEdit:(NSString**)error;
- (BOOL)redoSampleEdit:(NSString**)error;

- (BOOL)copySampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)cutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)deleteSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)silenceSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)pasteSampleRangeAtIndex:(NSUInteger)index atFrame:(uint64_t)atFrame error:(NSString**)error;
- (BOOL)reverseSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)applyGainForSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame gainDb:(float)gainDb error:(NSString**)error;
- (BOOL)normalizeSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame targetPeakDb:(float)targetPeakDb error:(NSString**)error;
- (BOOL)fadeInSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)fadeOutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)hasSampleClipboard;
- (NSString*)sampleClipboardSummary;

- (NSUInteger)multisampleCount;
- (NSArray<NSString*>*)multisampleDisplayRows;
- (NSDictionary<NSString*, id>*)multisampleStateAtIndex:(NSUInteger)index;
- (NSArray<NSDictionary<NSString*, id>*>*)zoneStatesForMultisampleAtIndex:(NSUInteger)index;
- (BOOL)createMultisampleNamed:(NSString*)name sampleIndexes:(NSIndexSet*)sampleIndexes error:(NSString**)error createdIndex:(NSUInteger*)createdIndex;
- (BOOL)renameMultisampleAtIndex:(NSUInteger)index name:(NSString*)name error:(NSString**)error;
- (BOOL)addZoneToMultisampleAtIndex:(NSUInteger)multisampleIndex sampleIndex:(NSUInteger)sampleIndex error:(NSString**)error;
- (BOOL)removeZoneFromMultisampleAtIndex:(NSUInteger)multisampleIndex zoneIndex:(NSUInteger)zoneIndex error:(NSString**)error;
- (BOOL)updateZoneAtMultisampleIndex:(NSUInteger)multisampleIndex
                           zoneIndex:(NSUInteger)zoneIndex
                         sampleIndex:(NSUInteger)sampleIndex
                              keyLow:(NSUInteger)keyLow
                             keyHigh:(NSUInteger)keyHigh
                         velocityLow:(NSUInteger)velocityLow
                        velocityHigh:(NSUInteger)velocityHigh
                             rootKey:(NSUInteger)rootKey
                  transposeSemitones:(NSInteger)transposeSemitones
                           tuneCents:(float)tuneCents
                              gainDb:(float)gainDb
                                 pan:(float)pan
                               error:(NSString**)error;

- (NSUInteger)soundCount;
- (NSArray<NSString*>*)soundDisplayRows;
- (NSDictionary<NSString*, id>*)soundStateAtIndex:(NSUInteger)index;
- (BOOL)updateSoundAtIndex:(NSUInteger)index name:(NSString*)name bank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot category:(NSUInteger)category error:(NSString**)error;
- (NSDictionary<NSString*, NSNumber*>*)nextFreeSoundAddressFromBank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot excludingIndex:(NSUInteger)excludingIndex error:(NSString**)error;
- (BOOL)autoPackSoundAddressesFromBank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot error:(NSString**)error;
@end

@implementation SVManagerDocument

- (instancetype)init {
    self = [super init];
    if (self) {
        _project.name = "SILVETON BANK";
        _undoHistoryBytes = 0U;
        _redoHistoryBytes = 0U;
        _hasSampleClipboard = false;
    }
    return self;
}

- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error {
    std::size_t importedObjects = 0U;
    std::vector<std::string> messages;
    for (NSString* nsPath in paths) {
        if (nsPath.length == 0U) continue;
        const std::string path([nsPath fileSystemRepresentation]);
        const std::string ext = lowerExtension(path);
        if (ext == ".kmp") {
            auto result = KorgImporter::loadKmp(path);
            if (!result.ok()) { messages.push_back(filenameOnly(path) + ": " + result.error); continue; }
            for (const auto& warning : result.warnings) messages.push_back(warning);
            appendKmp(_project, std::move(result)); ++importedObjects; continue;
        }
        if (ext == ".ksc") {
            auto result = KorgImporter::loadKsc(path);
            if (!result.ok()) { messages.push_back(filenameOnly(path) + ": " + result.error); continue; }
            for (const auto& warning : result.warnings) messages.push_back(warning);
            importedObjects += result.multisamples.size(); appendKsc(_project, std::move(result)); continue;
        }
        if (ext == ".ksf") {
            auto result = KorgImporter::loadKsf(path);
            if (!result.ok()) { messages.push_back(filenameOnly(path) + ": " + result.error); continue; }
            appendSingleSample(_project, std::move(result.sample)); ++importedObjects; continue;
        }
        if (ext == ".wav" || ext == ".wave" || ext == ".aif" || ext == ".aiff" || ext == ".aifc") {
            auto result = AudioFileLoader::load(path);
            if (!result.ok()) { messages.push_back(filenameOnly(path) + ": " + result.error); continue; }
            appendSingleSample(_project, std::move(result.sample)); ++importedObjects; continue;
        }
        messages.push_back(filenameOnly(path) + ": unsupported file type");
    }
    if (importedObjects == 0U) {
        setError(error, messages.empty() ? std::string("No supported files were selected") : joinMessages(messages));
        return NO;
    }
    clearHistory(_undoHistory, _undoHistoryBytes);
    clearHistory(_redoHistory, _redoHistoryBytes);
    if (error != nullptr) *error = messages.empty() ? nil : nsString(joinMessages(messages));
    return YES;
}

- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary {
    if (_project.sounds.empty() || _project.multisamples.empty() || _project.samples.empty()) {
        if (error != nullptr) *error = @"Nothing has been imported yet."; return NO;
    }
    if (path.length == 0U) { if (error != nullptr) *error = @"No output path was selected."; return NO; }
    SvBuildStats stats{}; std::string buildError;
    if (!SvBankBuilder::writeAtomic([path fileSystemRepresentation], _project, stats, buildError)) { setError(error, buildError); return NO; }
    if (summary != nullptr) {
        const double beforeMiB = static_cast<double>(stats.audioBytesBeforeDedup) / (1024.0 * 1024.0);
        const double afterMiB = static_cast<double>(stats.audioBytesAfterDedup) / (1024.0 * 1024.0);
        *summary = [NSString stringWithFormat:@"Built %u SOUNDs · %u multisamples · %u samples · %u unique audio payloads · %.1f -> %.1f MiB",
                    stats.soundCount, stats.multisampleCount, stats.sampleCount, stats.uniqueAudioPayloadCount, beforeMiB, afterMiB];
    }
    clearError(error); return YES;
}

- (NSArray<NSString*>*)displayRows {
    NSMutableArray<NSString*>* rows = [NSMutableArray arrayWithCapacity:_project.sounds.size()];
    for (std::size_t i = 0U; i < _project.sounds.size(); ++i) {
        const auto& sound = _project.sounds[i]; std::size_t zones = 0U;
        for (const auto& layer : sound.layers) if (layer.multisampleIndex < _project.multisamples.size()) zones += _project.multisamples[layer.multisampleIndex].zones.size();
        [rows addObject:[NSString stringWithFormat:@"%03zu   %@   ·   %zu zone%@   ·   B%u P%u S%u   ·   C%u",
                         i + 1U, nsString(sound.name), zones, zones == 1U ? @"" : @"s", sound.bank, sound.page, sound.slot, sound.category]];
    }
    return rows;
}

- (NSString*)statusSummary {
    std::uint64_t audioBytes = 0U; for (const auto& sample : _project.samples) audioBytes += static_cast<std::uint64_t>(sample.audioData.size());
    const double mib = static_cast<double>(audioBytes) / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%zu SOUNDs   ·   %zu multisamples   ·   %zu samples   ·   %.1f MiB source audio",
            _project.sounds.size(), _project.multisamples.size(), _project.samples.size(), mib];
}

- (void)clearProject {
    _project = BankProject{}; _project.name = "SILVETON BANK";
    clearHistory(_undoHistory, _undoHistoryBytes); clearHistory(_redoHistory, _redoHistoryBytes);
    _sampleClipboard = SampleRegion{}; _hasSampleClipboard = false;
}

- (NSUInteger)sampleCount { return static_cast<NSUInteger>(_project.samples.size()); }

- (NSArray<NSString*>*)sampleDisplayRows {
    NSMutableArray<NSString*>* rows = [NSMutableArray arrayWithCapacity:_project.samples.size()];
    for (std::size_t i = 0U; i < _project.samples.size(); ++i) {
        const auto& sample = _project.samples[i];
        const double seconds = sample.sampleRate == 0U ? 0.0 : static_cast<double>(sample.totalFrames) / static_cast<double>(sample.sampleRate);
        [rows addObject:[NSString stringWithFormat:@"%03zu   %@   ·   %u Hz   ·   %u ch   ·   %.3f s",
                         i + 1U, nsString(sample.name.empty() ? std::string("Unnamed Sample") : sample.name), sample.sampleRate, sample.channels, seconds]];
    }
    return rows;
}

- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index {
    if (!validSampleIndex(_project, index)) return nil;
    const auto& sample = _project.samples[static_cast<std::size_t>(index)];
    const float peak = SampleEditor::peakLinear(sample);
    const float peakDb = peak > 0.0F ? static_cast<float>(20.0 * std::log10(static_cast<double>(peak))) : -120.0F;
    return @{@"name": nsString(sample.name), @"sampleRate": @(sample.sampleRate), @"channels": @(sample.channels), @"totalFrames": @(sample.totalFrames),
             @"rootKey": @(sample.rootKey), @"fineTuneCents": @(sample.fineTuneCents), @"loopEnabled": @(sample.loop.enabled), @"loopStart": @(sample.loop.startFrame),
             @"loopEnd": @(sample.loop.endFrame), @"crossfadeFrames": @(sample.loop.crossfadeFrames), @"peakDb": @(peakDb)};
}

- (NSDictionary<NSString*, id>*)auditionStateAtIndex:(NSUInteger)index error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return nil; }
    const auto& sample = _project.samples[static_cast<std::size_t>(index)];
    if (!sample.valid() || sample.audioData.empty()) { if (error != nullptr) *error = @"The selected sample has no valid audio data."; return nil; }
    NSData* audio = [NSData dataWithBytes:sample.audioData.data() length:static_cast<NSUInteger>(sample.audioData.size())];
    clearError(error);
    return @{@"name": nsString(sample.name), @"audioData": audio, @"sampleRate": @(sample.sampleRate), @"channels": @(sample.channels),
             @"encoding": @(static_cast<unsigned int>(sample.encoding)), @"bitsPerSample": @(sample.bitsPerSample), @"totalFrames": @(sample.totalFrames),
             @"loopEnabled": @(sample.loop.enabled), @"loopStart": @(sample.loop.startFrame), @"loopEnd": @(sample.loop.endFrame)};
}

- (NSArray<NSNumber*>*)waveformAtIndex:(NSUInteger)index pointCount:(NSUInteger)pointCount error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return nil; }
    std::vector<WaveformPoint> points; std::string editError;
    if (!SampleEditor::buildWaveform(_project.samples[static_cast<std::size_t>(index)], static_cast<std::size_t>(pointCount), points, editError)) {
        setError(error, editError); return nil;
    }
    NSMutableArray<NSNumber*>* flattened = [NSMutableArray arrayWithCapacity:points.size() * 2U];
    for (const auto& point : points) { [flattened addObject:@(point.minimum)]; [flattened addObject:@(point.maximum)]; }
    clearError(error); return flattened;
}

- (BOOL)trimSampleAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::trim(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)setLoopForSampleAtIndex:(NSUInteger)index enabled:(BOOL)enabled startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    const bool on = enabled == YES;
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [on, startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::setLoop(sample, on, startFrame, endFrame, 0U, e); }) ? YES : NO;
}

- (BOOL)applyLoopCrossfadeForSampleAtIndex:(NSUInteger)index frames:(uint32_t)frames error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [frames](ImportedSample& sample, std::string& e) { return SampleEditor::applyLoopCrossfade(sample, frames, e); }) ? YES : NO;
}

- (BOOL)reverseSampleAtIndex:(NSUInteger)index error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [](ImportedSample& sample, std::string& e) { return SampleEditor::reverse(sample, e); }) ? YES : NO;
}

- (BOOL)applyGainForSampleAtIndex:(NSUInteger)index gainDb:(float)gainDb error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [gainDb](ImportedSample& sample, std::string& e) { return SampleEditor::applyGainDb(sample, gainDb, e); }) ? YES : NO;
}

- (BOOL)normalizeSampleAtIndex:(NSUInteger)index targetPeakDb:(float)targetPeakDb error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [targetPeakDb](ImportedSample& sample, std::string& e) { return SampleEditor::normalize(sample, targetPeakDb, e); }) ? YES : NO;
}

- (BOOL)fadeInSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [frames](ImportedSample& sample, std::string& e) { return SampleEditor::fadeIn(sample, frames, e); }) ? YES : NO;
}

- (BOOL)fadeOutSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [frames](ImportedSample& sample, std::string& e) { return SampleEditor::fadeOut(sample, frames, e); }) ? YES : NO;
}

- (BOOL)setRootKeyForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [rootKey](ImportedSample& sample, std::string& e) { return SampleEditor::setRootKey(sample, rootKey, e); }) ? YES : NO;
}

- (BOOL)setFineTuneForSampleAtIndex:(NSUInteger)index cents:(float)cents error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [cents](ImportedSample& sample, std::string& e) { return SampleEditor::setFineTuneCents(sample, cents, e); }) ? YES : NO;
}

- (BOOL)setTuningForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey cents:(float)cents error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [rootKey, cents](ImportedSample& sample, std::string& e) {
                               if (!SampleEditor::setRootKey(sample, rootKey, e)) return false;
                               return SampleEditor::setFineTuneCents(sample, cents, e);
                           }) ? YES : NO;
}

- (uint64_t)nearestZeroCrossingForSampleAtIndex:(NSUInteger)index frame:(uint64_t)frame radius:(uint64_t)radius {
    if (!validSampleIndex(_project, index)) return frame;
    return SampleEditor::nearestZeroCrossing(_project.samples[static_cast<std::size_t>(index)], frame, radius);
}

- (BOOL)canUndoSampleEdit { return _undoHistory.empty() ? NO : YES; }
- (BOOL)canRedoSampleEdit { return _redoHistory.empty() ? NO : YES; }

- (BOOL)undoSampleEdit:(NSString**)error {
    if (_undoHistory.empty()) { if (error != nullptr) *error = @"There is no sample edit to undo."; return NO; }
    SampleHistoryEntry entry = std::move(_undoHistory.back()); _undoHistoryBytes -= entry.storageBytes; _undoHistory.pop_back();
    if (entry.sampleIndex >= _project.samples.size()) {
        if (error != nullptr) *error = @"Undo history points to a sample that no longer exists.";
        clearHistory(_undoHistory, _undoHistoryBytes); clearHistory(_redoHistory, _redoHistoryBytes); return NO;
    }
    pushHistory(_redoHistory, _redoHistoryBytes, entry.sampleIndex, _project.samples[entry.sampleIndex]);
    _project.samples[entry.sampleIndex] = std::move(entry.sample); clearError(error); return YES;
}

- (BOOL)redoSampleEdit:(NSString**)error {
    if (_redoHistory.empty()) { if (error != nullptr) *error = @"There is no sample edit to redo."; return NO; }
    SampleHistoryEntry entry = std::move(_redoHistory.back()); _redoHistoryBytes -= entry.storageBytes; _redoHistory.pop_back();
    if (entry.sampleIndex >= _project.samples.size()) {
        if (error != nullptr) *error = @"Redo history points to a sample that no longer exists.";
        clearHistory(_undoHistory, _undoHistoryBytes); clearHistory(_redoHistory, _redoHistoryBytes); return NO;
    }
    pushHistory(_undoHistory, _undoHistoryBytes, entry.sampleIndex, _project.samples[entry.sampleIndex]);
    _project.samples[entry.sampleIndex] = std::move(entry.sample); clearError(error); return YES;
}

- (BOOL)copySampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    SampleRegion copied{}; std::string e;
    if (!SampleEditor::copyRegion(_project.samples[static_cast<std::size_t>(index)], startFrame, endFrame, copied, e)) { setError(error, e); return NO; }
    _sampleClipboard = std::move(copied); _hasSampleClipboard = true; clearError(error); return YES;
}

- (BOOL)cutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    SampleRegion copied{}; std::string e;
    if (!SampleEditor::copyRegion(_project.samples[static_cast<std::size_t>(index)], startFrame, endFrame, copied, e)) { setError(error, e); return NO; }
    const BOOL ok = applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                                    [startFrame, endFrame](ImportedSample& sample, std::string& editError) { return SampleEditor::deleteRegion(sample, startFrame, endFrame, editError); }) ? YES : NO;
    if (ok == YES) { _sampleClipboard = std::move(copied); _hasSampleClipboard = true; }
    return ok;
}

- (BOOL)deleteSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::deleteRegion(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)silenceSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::silenceRegion(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)pasteSampleRangeAtIndex:(NSUInteger)index atFrame:(uint64_t)atFrame error:(NSString**)error {
    if (!_hasSampleClipboard) { if (error != nullptr) *error = @"The sample clipboard is empty."; return NO; }
    const SampleRegion clipboard = _sampleClipboard;
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [atFrame, clipboard](ImportedSample& sample, std::string& e) { return SampleEditor::insertRegion(sample, atFrame, clipboard, e); }) ? YES : NO;
}

- (BOOL)reverseSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::reverseRegion(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)applyGainForSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame gainDb:(float)gainDb error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame, gainDb](ImportedSample& sample, std::string& e) { return SampleEditor::applyGainDbRegion(sample, startFrame, endFrame, gainDb, e); }) ? YES : NO;
}

- (BOOL)normalizeSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame targetPeakDb:(float)targetPeakDb error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame, targetPeakDb](ImportedSample& sample, std::string& e) { return SampleEditor::normalizeRegion(sample, startFrame, endFrame, targetPeakDb, e); }) ? YES : NO;
}

- (BOOL)fadeInSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::fadeInRegion(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)fadeOutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    return applySampleEdit(_project, index, _undoHistory, _undoHistoryBytes, _redoHistory, _redoHistoryBytes, error,
                           [startFrame, endFrame](ImportedSample& sample, std::string& e) { return SampleEditor::fadeOutRegion(sample, startFrame, endFrame, e); }) ? YES : NO;
}

- (BOOL)hasSampleClipboard { return _hasSampleClipboard ? YES : NO; }
- (NSString*)sampleClipboardSummary {
    if (!_hasSampleClipboard) return @"Clipboard empty";
    return [NSString stringWithFormat:@"Clipboard: %llu frames · %u Hz · %u ch", static_cast<unsigned long long>(_sampleClipboard.frameCount), _sampleClipboard.sampleRate, _sampleClipboard.channels];
}

- (NSUInteger)multisampleCount { return static_cast<NSUInteger>(_project.multisamples.size()); }

- (NSArray<NSString*>*)multisampleDisplayRows {
    NSMutableArray<NSString*>* rows = [NSMutableArray arrayWithCapacity:_project.multisamples.size()];
    for (std::size_t i = 0U; i < _project.multisamples.size(); ++i) {
        const auto& multisample = _project.multisamples[i];
        [rows addObject:[NSString stringWithFormat:@"%03zu   %@   ·   %zu zone%@", i + 1U,
                         nsString(multisample.name.empty() ? std::string("Unnamed Multisample") : multisample.name),
                         multisample.zones.size(), multisample.zones.size() == 1U ? @"" : @"s"]];
    }
    return rows;
}

- (NSDictionary<NSString*, id>*)multisampleStateAtIndex:(NSUInteger)index {
    if (!validMultisampleIndex(_project, index)) return nil;
    const auto& multisample = _project.multisamples[static_cast<std::size_t>(index)];
    return @{@"name": nsString(multisample.name), @"sourceIdentity": nsString(multisample.sourceIdentity),
             @"zoneCount": @(static_cast<unsigned long long>(multisample.zones.size()))};
}

- (NSArray<NSDictionary<NSString*, id>*>*)zoneStatesForMultisampleAtIndex:(NSUInteger)index {
    if (!validMultisampleIndex(_project, index)) return @[];
    const auto& multisample = _project.multisamples[static_cast<std::size_t>(index)];
    NSMutableArray<NSDictionary<NSString*, id>*>* rows = [NSMutableArray arrayWithCapacity:multisample.zones.size()];
    for (std::size_t zoneIndex = 0U; zoneIndex < multisample.zones.size(); ++zoneIndex) {
        const auto& zone = multisample.zones[zoneIndex];
        NSString* sampleName = zone.sampleIndex < _project.samples.size() ? nsString(_project.samples[zone.sampleIndex].name) : @"Invalid sample";
        [rows addObject:@{@"zoneIndex": @(static_cast<unsigned long long>(zoneIndex)), @"sampleIndex": @(zone.sampleIndex), @"sampleName": sampleName,
                          @"keyLow": @(zone.keyLow), @"keyHigh": @(zone.keyHigh), @"velocityLow": @(zone.velocityLow), @"velocityHigh": @(zone.velocityHigh),
                          @"rootKey": @(zone.rootKey), @"transposeSemitones": @(zone.transposeSemitones), @"tuneCents": @(zone.tuneCents), @"gainDb": @(zone.gainDb),
                          @"pan": @(zone.pan), @"oneShot": @(zone.oneShot), @"reverse": @(zone.reverse), @"nonTranspose": @(zone.nonTranspose)}];
    }
    return rows;
}

- (BOOL)createMultisampleNamed:(NSString*)name sampleIndexes:(NSIndexSet*)sampleIndexes error:(NSString**)error createdIndex:(NSUInteger*)createdIndex {
    if (sampleIndexes == nil || sampleIndexes.count == 0U) { if (error != nullptr) *error = @"Select at least one sample for the new multisample."; return NO; }
    std::vector<std::size_t> indexes; indexes.reserve(sampleIndexes.count);
    NSUInteger current = sampleIndexes.firstIndex;
    while (current != NSNotFound) {
        if (!validSampleIndex(_project, current)) { if (error != nullptr) *error = @"The selected sample list contains an invalid sample index."; return NO; }
        indexes.push_back(static_cast<std::size_t>(current)); current = [sampleIndexes indexGreaterThanIndex:current];
    }
    auto* project = &_project;
    std::sort(indexes.begin(), indexes.end(), [project](std::size_t a, std::size_t b) {
        const auto rootA = project->samples[a].rootKey; const auto rootB = project->samples[b].rootKey; return rootA == rootB ? a < b : rootA < rootB;
    });
    for (std::size_t i = 1U; i < indexes.size(); ++i) {
        if (_project.samples[indexes[i - 1U]].rootKey == _project.samples[indexes[i]].rootKey) {
            if (error != nullptr) *error = @"Automatic key mapping requires unique Root Key values. Change one of the duplicate sample Root Keys first."; return NO;
        }
    }
    ImportedMultisample multisample{};
    NSString* trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    const std::string multisampleName = trimmed.length == 0U ? std::string("New Multisample") : std::string(trimmed.UTF8String);
    multisample.name = multisampleName; multisample.sourceIdentity = std::string("manager:multisample:") + std::to_string(_project.multisamples.size());
    multisample.zones.reserve(indexes.size());
    std::uint16_t nextLow = 0U;
    for (std::size_t i = 0U; i < indexes.size(); ++i) {
        const std::size_t sampleIndex = indexes[i]; const auto root = _project.samples[sampleIndex].rootKey; std::uint16_t high = 127U;
        if (i + 1U < indexes.size()) {
            const auto nextRoot = _project.samples[indexes[i + 1U]].rootKey;
            high = static_cast<std::uint16_t>((static_cast<unsigned int>(root) + static_cast<unsigned int>(nextRoot)) / 2U);
        }
        ImportedZone zone{}; zone.sampleIndex = static_cast<std::uint32_t>(sampleIndex); zone.keyLow = static_cast<std::uint8_t>(nextLow);
        zone.keyHigh = static_cast<std::uint8_t>(high); zone.velocityLow = 1U; zone.velocityHigh = 127U; zone.rootKey = root;
        multisample.zones.push_back(zone); nextLow = static_cast<std::uint16_t>(high + 1U);
    }
    const std::uint32_t multisampleIndex = static_cast<std::uint32_t>(_project.multisamples.size());
    _project.multisamples.push_back(std::move(multisample)); appendSoundForMultisample(_project, multisampleIndex, multisampleName);
    if (createdIndex != nullptr) *createdIndex = static_cast<NSUInteger>(multisampleIndex); clearError(error); return YES;
}

- (BOOL)renameMultisampleAtIndex:(NSUInteger)index name:(NSString*)name error:(NSString**)error {
    if (!validMultisampleIndex(_project, index)) { if (error != nullptr) *error = @"No multisample is selected."; return NO; }
    NSString* trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0U) { if (error != nullptr) *error = @"Multisample name cannot be empty."; return NO; }
    _project.multisamples[static_cast<std::size_t>(index)].name = std::string(trimmed.UTF8String); clearError(error); return YES;
}

- (BOOL)addZoneToMultisampleAtIndex:(NSUInteger)multisampleIndex sampleIndex:(NSUInteger)sampleIndex error:(NSString**)error {
    if (!validMultisampleIndex(_project, multisampleIndex)) { if (error != nullptr) *error = @"No multisample is selected."; return NO; }
    if (!validSampleIndex(_project, sampleIndex)) { if (error != nullptr) *error = @"Select a valid sample to assign to the new zone."; return NO; }
    ImportedZone zone{}; zone.sampleIndex = static_cast<std::uint32_t>(sampleIndex); zone.rootKey = _project.samples[static_cast<std::size_t>(sampleIndex)].rootKey;
    zone.keyLow = zone.rootKey; zone.keyHigh = zone.rootKey; zone.velocityLow = 1U; zone.velocityHigh = 127U;
    _project.multisamples[static_cast<std::size_t>(multisampleIndex)].zones.push_back(zone); clearError(error); return YES;
}

- (BOOL)removeZoneFromMultisampleAtIndex:(NSUInteger)multisampleIndex zoneIndex:(NSUInteger)zoneIndex error:(NSString**)error {
    if (!validZoneIndex(_project, multisampleIndex, zoneIndex)) { if (error != nullptr) *error = @"No valid zone is selected."; return NO; }
    auto& zones = _project.multisamples[static_cast<std::size_t>(multisampleIndex)].zones;
    if (zones.size() <= 1U) { if (error != nullptr) *error = @"A multisample must contain at least one zone."; return NO; }
    zones.erase(zones.begin() + static_cast<std::ptrdiff_t>(zoneIndex)); clearError(error); return YES;
}

- (BOOL)updateZoneAtMultisampleIndex:(NSUInteger)multisampleIndex
                           zoneIndex:(NSUInteger)zoneIndex
                         sampleIndex:(NSUInteger)sampleIndex
                              keyLow:(NSUInteger)keyLow
                             keyHigh:(NSUInteger)keyHigh
                         velocityLow:(NSUInteger)velocityLow
                        velocityHigh:(NSUInteger)velocityHigh
                             rootKey:(NSUInteger)rootKey
                  transposeSemitones:(NSInteger)transposeSemitones
                           tuneCents:(float)tuneCents
                              gainDb:(float)gainDb
                                 pan:(float)pan
                               error:(NSString**)error {
    if (!validZoneIndex(_project, multisampleIndex, zoneIndex)) { if (error != nullptr) *error = @"No valid zone is selected."; return NO; }
    if (!validSampleIndex(_project, sampleIndex)) { if (error != nullptr) *error = @"Zone sample assignment is invalid."; return NO; }
    if (keyLow > 127U || keyHigh > 127U || keyLow > keyHigh) { if (error != nullptr) *error = @"Key range must be 0...127 and Low cannot exceed High."; return NO; }
    if (velocityLow < 1U || velocityLow > 127U || velocityHigh < 1U || velocityHigh > 127U || velocityLow > velocityHigh) {
        if (error != nullptr) *error = @"Velocity range must be 1...127 and Low cannot exceed High."; return NO;
    }
    if (rootKey > 127U) { if (error != nullptr) *error = @"Root Key must be 0...127."; return NO; }
    if (transposeSemitones < -127 || transposeSemitones > 127) { if (error != nullptr) *error = @"Transpose must be between -127 and +127 semitones."; return NO; }
    if (!std::isfinite(tuneCents) || !std::isfinite(gainDb) || !std::isfinite(pan) || pan < -1.0F || pan > 1.0F) {
        if (error != nullptr) *error = @"Tune/Gain must be finite and Pan must be between -1.0 and +1.0."; return NO;
    }
    auto& zone = _project.multisamples[static_cast<std::size_t>(multisampleIndex)].zones[static_cast<std::size_t>(zoneIndex)];
    zone.sampleIndex = static_cast<std::uint32_t>(sampleIndex); zone.keyLow = static_cast<std::uint8_t>(keyLow); zone.keyHigh = static_cast<std::uint8_t>(keyHigh);
    zone.velocityLow = static_cast<std::uint8_t>(velocityLow); zone.velocityHigh = static_cast<std::uint8_t>(velocityHigh); zone.rootKey = static_cast<std::uint8_t>(rootKey);
    zone.transposeSemitones = static_cast<std::int8_t>(transposeSemitones); zone.tuneCents = tuneCents; zone.gainDb = gainDb; zone.pan = pan;
    clearError(error); return YES;
}

- (NSUInteger)soundCount { return static_cast<NSUInteger>(_project.sounds.size()); }
- (NSArray<NSString*>*)soundDisplayRows { return [self displayRows]; }

- (NSDictionary<NSString*, id>*)soundStateAtIndex:(NSUInteger)index {
    if (!validSoundIndex(_project, index)) return nil;
    const auto& sound = _project.sounds[static_cast<std::size_t>(index)]; NSString* multisampleName = @"No multisample"; std::size_t zoneCount = 0U;
    if (!sound.layers.empty()) {
        const std::uint32_t multisampleIndex = sound.layers.front().multisampleIndex;
        if (multisampleIndex < _project.multisamples.size()) {
            const auto& multisample = _project.multisamples[multisampleIndex]; multisampleName = nsString(multisample.name); zoneCount = multisample.zones.size();
        }
    }
    return @{@"name": nsString(sound.name), @"bank": @(sound.bank), @"page": @(sound.page), @"slot": @(sound.slot), @"category": @(sound.category),
             @"multisampleName": multisampleName, @"zoneCount": @(static_cast<unsigned long long>(zoneCount))};
}

- (BOOL)updateSoundAtIndex:(NSUInteger)index name:(NSString*)name bank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot category:(NSUInteger)category error:(NSString**)error {
    if (!validSoundIndex(_project, index)) { if (error != nullptr) *error = @"No bank/library entry is selected."; return NO; }
    if (bank > kLibraryAxisMaximum || page > kLibraryAxisMaximum || slot > kLibraryAxisMaximum || category > kLibraryAxisMaximum) {
        if (error != nullptr) *error = @"Bank, Page, Slot and Category must each be between 0 and 127."; return NO;
    }
    NSString* trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0U) { if (error != nullptr) *error = @"Library entry name cannot be empty."; return NO; }
    const auto b = static_cast<std::uint16_t>(bank); const auto p = static_cast<std::uint16_t>(page); const auto s = static_cast<std::uint16_t>(slot);
    if (soundAddressInUse(_project, b, p, s, static_cast<std::size_t>(index))) {
        if (error != nullptr) *error = [NSString stringWithFormat:@"Bank %lu / Page %lu / Slot %lu is already occupied.", (unsigned long)bank, (unsigned long)page, (unsigned long)slot];
        return NO;
    }
    auto& sound = _project.sounds[static_cast<std::size_t>(index)]; sound.name = std::string(trimmed.UTF8String); sound.bank = b; sound.page = p; sound.slot = s;
    sound.category = static_cast<std::uint16_t>(category); clearError(error); return YES;
}

- (NSDictionary<NSString*, NSNumber*>*)nextFreeSoundAddressFromBank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot excludingIndex:(NSUInteger)excludingIndex error:(NSString**)error {
    if (bank > kLibraryAxisMaximum || page > kLibraryAxisMaximum || slot > kLibraryAxisMaximum) {
        if (error != nullptr) *error = @"Bank, Page and Slot must each be between 0 and 127."; return nil;
    }
    std::uint16_t b = static_cast<std::uint16_t>(bank); std::uint16_t p = static_cast<std::uint16_t>(page); std::uint16_t s = static_cast<std::uint16_t>(slot);
    const std::size_t excluded = excludingIndex == NSNotFound ? _project.sounds.size() : static_cast<std::size_t>(excludingIndex);
    while (true) {
        if (!soundAddressInUse(_project, b, p, s, excluded)) { clearError(error); return @{@"bank": @(b), @"page": @(p), @"slot": @(s)}; }
        if (!nextLibraryAddress(b, p, s)) break;
    }
    if (error != nullptr) *error = @"No free Bank/Page/Slot address exists at or after the requested position."; return nil;
}

- (BOOL)autoPackSoundAddressesFromBank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot error:(NSString**)error {
    if (bank > kLibraryAxisMaximum || page > kLibraryAxisMaximum || slot > kLibraryAxisMaximum) {
        if (error != nullptr) *error = @"Bank, Page and Slot must each be between 0 and 127."; return NO;
    }
    if (_project.sounds.empty()) { if (error != nullptr) *error = @"There are no library entries to pack."; return NO; }
    std::uint16_t b = static_cast<std::uint16_t>(bank); std::uint16_t p = static_cast<std::uint16_t>(page); std::uint16_t s = static_cast<std::uint16_t>(slot);
    std::vector<std::array<std::uint16_t, 3U>> addresses; addresses.reserve(_project.sounds.size());
    for (std::size_t i = 0U; i < _project.sounds.size(); ++i) {
        addresses.push_back({b, p, s});
        if (i + 1U < _project.sounds.size() && !nextLibraryAddress(b, p, s)) {
            if (error != nullptr) *error = @"There is not enough Bank/Page/Slot space to pack all entries from this starting address."; return NO;
        }
    }
    for (std::size_t i = 0U; i < _project.sounds.size(); ++i) {
        _project.sounds[i].bank = addresses[i][0]; _project.sounds[i].page = addresses[i][1]; _project.sounds[i].slot = addresses[i][2];
    }
    clearError(error); return YES;
}

@end
