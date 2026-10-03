#import <Foundation/Foundation.h>

#include "silveton/manager/AudioFileLoader.h"
#include "silveton/manager/KorgImporter.h"
#include "silveton/manager/SvBankBuilder.h"

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <sstream>
#include <string>
#include <vector>

namespace {
using namespace silveton::manager;

std::string lowerExtension(const std::string& path) {
    std::string ext = std::filesystem::path(path).extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext;
}

NSString* nsString(const std::string& value) {
    return [NSString stringWithUTF8String:value.c_str()];
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
                messages.push_back(std::filesystem::path(path).filename().string() + ": " + result.error);
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
                messages.push_back(std::filesystem::path(path).filename().string() + ": " + result.error);
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
                messages.push_back(std::filesystem::path(path).filename().string() + ": " + result.error);
                continue;
            }
            appendSingleSample(_project, std::move(result.sample));
            ++importedObjects;
            continue;
        }

        if (ext == ".wav" || ext == ".wave" || ext == ".aif" || ext == ".aiff" || ext == ".aifc") {
            auto result = AudioFileLoader::load(path);
            if (!result.ok()) {
                messages.push_back(std::filesystem::path(path).filename().string() + ": " + result.error);
                continue;
            }
            appendSingleSample(_project, std::move(result.sample));
            ++importedObjects;
            continue;
        }

        messages.push_back(std::filesystem::path(path).filename().string() + ": unsupported file type");
    }

    if (importedObjects == 0U) {
        const std::string text = messages.empty() ? std::string("No supported files were selected") : joinMessages(messages);
        if (error != nullptr) *error = nsString(text);
        return NO;
    }

    if (error != nullptr) {
        *error = messages.empty() ? nil : nsString(joinMessages(messages));
    }
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
        if (error != nullptr) *error = nsString(buildError);
        return NO;
    }

    if (summary != nullptr) {
        const double beforeMiB = static_cast<double>(stats.audioBytesBeforeDedup) / (1024.0 * 1024.0);
        const double afterMiB = static_cast<double>(stats.audioBytesAfterDedup) / (1024.0 * 1024.0);
        *summary = [NSString stringWithFormat:@"Built %u SOUNDs · %u multisamples · %u samples · %u unique audio payloads · %.1f -> %.1f MiB",
                    stats.soundCount, stats.multisampleCount, stats.sampleCount, stats.uniqueAudioPayloadCount, beforeMiB, afterMiB];
    }
    if (error != nullptr) *error = nil;
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

@end
