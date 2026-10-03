#import <Foundation/Foundation.h>

#include "silveton/manager/AudioFileLoader.h"
#include "silveton/manager/KorgImporter.h"
#include "silveton/manager/SampleEditor.h"
#include "silveton/manager/SvBankBuilder.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <sstream>
#include <string>
#include <vector>

namespace {
using namespace silveton::manager;

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
    for (auto& ms : imported.multisamples) {
        for (auto& zone : ms.zones) zone.sampleIndex += sampleBase;
    }
    for (auto& sample : imported.samples) project.samples.push_back(std::move(sample));
    for (std::size_t i = 0; i < imported.multisamples.size(); ++i) {
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

    ImportedMultisample ms{};
    ms.name = name;
    ms.sourceIdentity = std::string("single:") + project.samples.back().sourceIdentity;
    ImportedZone zone{};
    zone.sampleIndex = sampleIndex;
    zone.rootKey = root;
    ms.zones.push_back(zone);

    const std::uint32_t multisampleIndex = static_cast<std::uint32_t>(project.multisamples.size());
    project.multisamples.push_back(std::move(ms));
    appendSoundForMultisample(project, multisampleIndex, name);
}

std::string joinMessages(const std::vector<std::string>& messages) {
    std::ostringstream stream;
    for (std::size_t i = 0; i < messages.size(); ++i) {
        if (i != 0U) stream << '\n';
        stream << messages[i];
    }
    return stream.str();
}

bool validSampleIndex(const BankProject& project, NSUInteger index) noexcept {
    return static_cast<std::size_t>(index) < project.samples.size();
}

} // namespace

@interface SVManagerDocument : NSObject {
@private
    silveton::manager::BankProject _project;
}
- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (NSArray<NSString*>*)displayRows;
- (NSString*)statusSummary;
- (void)clearProject;

- (NSUInteger)sampleCount;
- (NSArray<NSString*>*)sampleDisplayRows;
- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index;
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
- (uint64_t)nearestZeroCrossingForSampleAtIndex:(NSUInteger)index frame:(uint64_t)frame radius:(uint64_t)radius;
@end

@implementation SVManagerDocument

- (instancetype)init {
    self = [super init];
    if (self) _project.name = "SILVETON BANK";
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
            if (!result.ok()) {
                messages.push_back(filenameOnly(path) + ": " + result.error);
                continue;
            }
            for (const auto& warning : result.warnings) messages.push_back(warning);
            appendKmp(_project, std::move(result));
            ++importedObjects;
            continue;
        }

        if (ext == ".ksc") {
            auto result = KorgImporter::loadKsc(path);
            if (!result.ok()) {
                messages.push_back(filenameOnly(path) + ": " + result.error);
                continue;
            }
            for (const auto& warning : result.warnings) messages.push_back(warning);
            importedObjects += result.multisamples.size();
            appendKsc(_project, std::move(result));
            continue;
        }

        if (ext == ".ksf") {
            auto result = KorgImporter::loadKsf(path);
            if (!result.ok()) {
                messages.push_back(filenameOnly(path) + ": " + result.error);
                continue;
            }
            appendSingleSample(_project, std::move(result.sample));
            ++importedObjects;
            continue;
        }

        if (ext == ".wav" || ext == ".wave" || ext == ".aif" || ext == ".aiff" || ext == ".aifc") {
            auto result = AudioFileLoader::load(path);
            if (!result.ok()) {
                messages.push_back(filenameOnly(path) + ": " + result.error);
                continue;
            }
            appendSingleSample(_project, std::move(result.sample));
            ++importedObjects;
            continue;
        }

        messages.push_back(filenameOnly(path) + ": unsupported file type");
    }

    if (importedObjects == 0U) {
        const std::string text = messages.empty() ? std::string("No supported files were selected") : joinMessages(messages);
        setError(error, text);
        return NO;
    }

    if (error != nullptr) *error = messages.empty() ? nil : nsString(joinMessages(messages));
    return YES;
}

- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary {
    if (_project.sounds.empty() || _project.multisamples.empty() || _project.samples.empty()) {
        if (error != nullptr) *error = @"Nothing has been imported yet.";
        return NO;
    }
    if (path.length == 0U) {
        if (error != nullptr) *error = @"No output path was selected.";
        return NO;
    }

    SvBuildStats stats{};
    std::string buildError;
    if (!SvBankBuilder::writeAtomic([path fileSystemRepresentation], _project, stats, buildError)) {
        setError(error, buildError);
        return NO;
    }

    if (summary != nullptr) {
        const double beforeMiB = static_cast<double>(stats.audioBytesBeforeDedup) / (1024.0 * 1024.0);
        const double afterMiB = static_cast<double>(stats.audioBytesAfterDedup) / (1024.0 * 1024.0);
        *summary = [NSString stringWithFormat:@"Built %u SOUNDs · %u multisamples · %u samples · %u unique audio payloads · %.1f -> %.1f MiB",
                    stats.soundCount, stats.multisampleCount, stats.sampleCount, stats.uniqueAudioPayloadCount, beforeMiB, afterMiB];
    }
    clearError(error);
    return YES;
}

- (NSArray<NSString*>*)displayRows {
    NSMutableArray<NSString*>* rows = [NSMutableArray arrayWithCapacity:_project.sounds.size()];
    for (std::size_t i = 0U; i < _project.sounds.size(); ++i) {
        const auto& sound = _project.sounds[i];
        std::size_t zones = 0U;
        for (const auto& layer : sound.layers) {
            if (layer.multisampleIndex < _project.multisamples.size()) zones += _project.multisamples[layer.multisampleIndex].zones.size();
        }
        NSString* name = nsString(sound.name);
        [rows addObject:[NSString stringWithFormat:@"%03zu   %@   ·   %zu zone%@   ·   B%u P%u S%u",
                         i + 1U, name, zones, zones == 1U ? @"" : @"s", sound.bank, sound.page, sound.slot]];
    }
    return rows;
}

- (NSString*)statusSummary {
    std::uint64_t audioBytes = 0U;
    for (const auto& sample : _project.samples) audioBytes += static_cast<std::uint64_t>(sample.audioData.size());
    const double mib = static_cast<double>(audioBytes) / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%zu SOUNDs   ·   %zu multisamples   ·   %zu samples   ·   %.1f MiB source audio",
            _project.sounds.size(), _project.multisamples.size(), _project.samples.size(), mib];
}

- (void)clearProject {
    _project = BankProject{};
    _project.name = "SILVETON BANK";
}

- (NSUInteger)sampleCount {
    return static_cast<NSUInteger>(_project.samples.size());
}

- (NSArray<NSString*>*)sampleDisplayRows {
    NSMutableArray<NSString*>* rows = [NSMutableArray arrayWithCapacity:_project.samples.size()];
    for (std::size_t i = 0U; i < _project.samples.size(); ++i) {
        const auto& sample = _project.samples[i];
        const double seconds = sample.sampleRate == 0U ? 0.0 : static_cast<double>(sample.totalFrames) / static_cast<double>(sample.sampleRate);
        NSString* name = nsString(sample.name.empty() ? std::string("Unnamed Sample") : sample.name);
        [rows addObject:[NSString stringWithFormat:@"%03zu   %@   ·   %u Hz   ·   %u ch   ·   %.3f s",
                         i + 1U, name, sample.sampleRate, sample.channels, seconds]];
    }
    return rows;
}

- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index {
    if (!validSampleIndex(_project, index)) return nil;
    const auto& sample = _project.samples[static_cast<std::size_t>(index)];
    const float peak = SampleEditor::peakLinear(sample);
    const float peakDb = peak > 0.0F ? static_cast<float>(20.0 * std::log10(static_cast<double>(peak))) : -120.0F;
    return @{
        @"name": nsString(sample.name),
        @"sampleRate": [NSNumber numberWithUnsignedInt:sample.sampleRate],
        @"channels": [NSNumber numberWithUnsignedInt:sample.channels],
        @"totalFrames": [NSNumber numberWithUnsignedLongLong:sample.totalFrames],
        @"rootKey": [NSNumber numberWithUnsignedInt:sample.rootKey],
        @"fineTuneCents": [NSNumber numberWithFloat:sample.fineTuneCents],
        @"loopEnabled": [NSNumber numberWithBool:sample.loop.enabled],
        @"loopStart": [NSNumber numberWithUnsignedLongLong:sample.loop.startFrame],
        @"loopEnd": [NSNumber numberWithUnsignedLongLong:sample.loop.endFrame],
        @"crossfadeFrames": [NSNumber numberWithUnsignedInt:sample.loop.crossfadeFrames],
        @"peakDb": [NSNumber numberWithFloat:peakDb]
    };
}

- (NSArray<NSNumber*>*)waveformAtIndex:(NSUInteger)index pointCount:(NSUInteger)pointCount error:(NSString**)error {
    if (!validSampleIndex(_project, index)) {
        if (error != nullptr) *error = @"No sample is selected.";
        return nil;
    }
    std::vector<WaveformPoint> points;
    std::string editError;
    if (!SampleEditor::buildWaveform(_project.samples[static_cast<std::size_t>(index)], static_cast<std::size_t>(pointCount), points, editError)) {
        setError(error, editError);
        return nil;
    }
    NSMutableArray<NSNumber*>* flattened = [NSMutableArray arrayWithCapacity:points.size() * 2U];
    for (const auto& point : points) {
        [flattened addObject:[NSNumber numberWithFloat:point.minimum]];
        [flattened addObject:[NSNumber numberWithFloat:point.maximum]];
    }
    clearError(error);
    return flattened;
}

- (BOOL)trimSampleAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::trim(_project.samples[static_cast<std::size_t>(index)], startFrame, endFrame, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)setLoopForSampleAtIndex:(NSUInteger)index enabled:(BOOL)enabled startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::setLoop(_project.samples[static_cast<std::size_t>(index)], enabled == YES, startFrame, endFrame, 0U, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)applyLoopCrossfadeForSampleAtIndex:(NSUInteger)index frames:(uint32_t)frames error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::applyLoopCrossfade(_project.samples[static_cast<std::size_t>(index)], frames, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)reverseSampleAtIndex:(NSUInteger)index error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::reverse(_project.samples[static_cast<std::size_t>(index)], editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)applyGainForSampleAtIndex:(NSUInteger)index gainDb:(float)gainDb error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::applyGainDb(_project.samples[static_cast<std::size_t>(index)], gainDb, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)normalizeSampleAtIndex:(NSUInteger)index targetPeakDb:(float)targetPeakDb error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::normalize(_project.samples[static_cast<std::size_t>(index)], targetPeakDb, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)fadeInSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::fadeIn(_project.samples[static_cast<std::size_t>(index)], frames, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)fadeOutSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::fadeOut(_project.samples[static_cast<std::size_t>(index)], frames, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)setRootKeyForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::setRootKey(_project.samples[static_cast<std::size_t>(index)], rootKey, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (BOOL)setFineTuneForSampleAtIndex:(NSUInteger)index cents:(float)cents error:(NSString**)error {
    if (!validSampleIndex(_project, index)) { if (error != nullptr) *error = @"No sample is selected."; return NO; }
    std::string editError;
    if (!SampleEditor::setFineTuneCents(_project.samples[static_cast<std::size_t>(index)], cents, editError)) { setError(error, editError); return NO; }
    clearError(error);
    return YES;
}

- (uint64_t)nearestZeroCrossingForSampleAtIndex:(NSUInteger)index frame:(uint64_t)frame radius:(uint64_t)radius {
    if (!validSampleIndex(_project, index)) return frame;
    return SampleEditor::nearestZeroCrossing(_project.samples[static_cast<std::size_t>(index)], frame, radius);
}

@end
