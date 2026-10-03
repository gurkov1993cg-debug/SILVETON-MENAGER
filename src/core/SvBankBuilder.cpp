#include "silveton/manager/SvBankBuilder.h"

#include "silveton/manager/SampleHash.h"
#include "silveton/manager/SvBankFormat.h"

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace silveton::manager {
namespace {

std::uint64_t alignUp(std::uint64_t value, std::uint64_t alignment) noexcept {
    if (alignment == 0U) return value;
    const std::uint64_t mask = alignment - 1U;
    return (value + mask) & ~mask;
}

bool toU32(std::size_t value, std::uint32_t& out) noexcept {
    if (value > static_cast<std::size_t>(std::numeric_limits<std::uint32_t>::max())) return false;
    out = static_cast<std::uint32_t>(value);
    return true;
}

class StringTable {
public:
    StringTable() { bytes_.push_back(0U); offsets_.emplace(std::string{}, 0U); }

    std::uint32_t add(const std::string& text) {
        const auto found = offsets_.find(text);
        if (found != offsets_.end()) return found->second;
        const auto offset = static_cast<std::uint32_t>(bytes_.size());
        bytes_.insert(bytes_.end(), text.begin(), text.end());
        bytes_.push_back(0U);
        offsets_.emplace(text, offset);
        return offset;
    }

    const std::vector<std::uint8_t>& bytes() const noexcept { return bytes_; }

private:
    std::vector<std::uint8_t> bytes_;
    std::unordered_map<std::string, std::uint32_t> offsets_;
};

struct UniqueAudio {
    std::uint64_t hash{0};
    std::uint32_t sampleRate{0};
    std::uint16_t channels{0};
    AudioEncoding encoding{AudioEncoding::Pcm16LE};
    std::uint8_t bitsPerSample{0};
    std::uint64_t offset{0};
    std::vector<std::uint8_t> bytes;
};

bool sameAudio(const UniqueAudio& a, const ImportedSample& b) noexcept {
    return a.sampleRate == b.sampleRate && a.channels == b.channels && a.encoding == b.encoding &&
           a.bitsPerSample == b.bitsPerSample && a.bytes == b.audioData;
}

void appendSection(std::vector<std::uint8_t>& file, SvSectionDesc& section,
                   const std::vector<std::uint8_t>& data, std::uint64_t alignment) {
    const std::uint64_t aligned = alignUp(file.size(), alignment);
    if (aligned > file.size()) file.resize(static_cast<std::size_t>(aligned), 0U);
    section.offset = static_cast<std::uint64_t>(file.size());
    section.size = static_cast<std::uint64_t>(data.size());
    file.insert(file.end(), data.begin(), data.end());
}

bool validateProject(const BankProject& project, std::string& error) {
    for (std::size_t i = 0; i < project.samples.size(); ++i) {
        if (!project.samples[i].valid()) {
            error = "Invalid sample at index " + std::to_string(i);
            return false;
        }
    }
    for (std::size_t mi = 0; mi < project.multisamples.size(); ++mi) {
        const auto& ms = project.multisamples[mi];
        if (ms.zones.empty()) {
            error = "Multisample has no zones at index " + std::to_string(mi);
            return false;
        }
        for (const auto& z : ms.zones) {
            if (z.sampleIndex >= project.samples.size() || z.keyLow > z.keyHigh ||
                z.velocityLow == 0U || z.velocityLow > z.velocityHigh) {
                error = "Invalid zone in multisample index " + std::to_string(mi);
                return false;
            }
        }
    }
    for (std::size_t si = 0; si < project.sounds.size(); ++si) {
        const auto& sound = project.sounds[si];
        if (sound.layers.empty()) {
            error = "SOUND has no layers at index " + std::to_string(si);
            return false;
        }
        for (const auto& layer : sound.layers) {
            if (layer.multisampleIndex >= project.multisamples.size() || layer.keyLow > layer.keyHigh ||
                layer.velocityLow == 0U || layer.velocityLow > layer.velocityHigh) {
                error = "Invalid SOUND layer at sound index " + std::to_string(si);
                return false;
            }
        }
    }
    return true;
}

} // namespace

SvBuildResult SvBankBuilder::build(const BankProject& project) {
    SvBuildResult result{};
    if (!validateProject(project, result.error)) return result;

    std::uint32_t soundCount = 0U, multisampleCount = 0U, sampleCount = 0U;
    if (!toU32(project.sounds.size(), soundCount) || !toU32(project.multisamples.size(), multisampleCount) ||
        !toU32(project.samples.size(), sampleCount)) {
        result.error = "Bank object count exceeds format limits";
        return result;
    }

    StringTable strings;
    SvBankHeader header{};
    header.bankNameOffset = strings.add(project.name);
    header.soundCount = soundCount;
    header.multisampleCount = multisampleCount;
    header.sampleCount = sampleCount;

    std::vector<std::uint8_t> soundBytes;
    std::vector<std::uint8_t> layerBytes;
    std::vector<std::uint8_t> multisampleBytes;
    std::vector<std::uint8_t> sampleBytes;
    std::vector<std::uint8_t> zoneBytes;
    std::vector<std::uint8_t> audioBytes;

    std::uint32_t layerCursor = 0U;
    for (const auto& sound : project.sounds) {
        SvSoundRecord record{};
        record.nameOffset = strings.add(sound.name);
        record.firstLayer = layerCursor;
        if (!toU32(sound.layers.size(), record.layerCount)) { result.error = "SOUND layer count exceeds format limits"; return result; }
        record.bank = sound.bank; record.page = sound.page; record.slot = sound.slot; record.category = sound.category;
        appendSoundRecord(soundBytes, record);
        for (const auto& layer : sound.layers) {
            SvSoundLayerRecord lr{};
            lr.multisampleIndex = layer.multisampleIndex;
            lr.enabled = layer.enabled ? 1U : 0U;
            lr.keyLow = layer.keyLow; lr.keyHigh = layer.keyHigh; lr.velocityLow = layer.velocityLow; lr.velocityHigh = layer.velocityHigh;
            lr.transposeSemitones = layer.transposeSemitones; lr.tuneCents = layer.tuneCents; lr.levelDb = layer.levelDb; lr.pan = layer.pan;
            appendSoundLayerRecord(layerBytes, lr);
            ++layerCursor;
        }
    }
    header.soundLayerCount = layerCursor;

    std::uint32_t zoneCursor = 0U;
    for (const auto& ms : project.multisamples) {
        SvMultisampleRecord record{};
        record.nameOffset = strings.add(ms.name);
        record.sourceIdentityOffset = strings.add(ms.sourceIdentity);
        record.firstZone = zoneCursor;
        if (!toU32(ms.zones.size(), record.zoneCount)) { result.error = "Zone count exceeds format limits"; return result; }
        appendMultisampleRecord(multisampleBytes, record);
        for (const auto& zone : ms.zones) {
            SvZoneRecord zr{};
            zr.sampleIndex = zone.sampleIndex;
            zr.keyLow = zone.keyLow; zr.keyHigh = zone.keyHigh; zr.velocityLow = zone.velocityLow; zr.velocityHigh = zone.velocityHigh;
            zr.rootKey = zone.rootKey; zr.transposeSemitones = zone.transposeSemitones;
            zr.flags = static_cast<std::uint8_t>((zone.oneShot ? 1U : 0U) | (zone.reverse ? 2U : 0U) | (zone.nonTranspose ? 4U : 0U));
            zr.sourcePanRaw = zone.sourcePanRaw; zr.sourceLevelRaw = zone.sourceLevelRaw; zr.sourceFilterRaw = zone.sourceFilterRaw;
            zr.tuneCents = zone.tuneCents; zr.gainDb = zone.gainDb; zr.pan = zone.pan;
            appendZoneRecord(zoneBytes, zr);
            ++zoneCursor;
        }
    }
    header.zoneCount = zoneCursor;

    std::vector<UniqueAudio> uniqueAudio;
    std::unordered_map<std::uint64_t, std::vector<std::size_t>> hashBuckets;
    for (const auto& sample : project.samples) {
        const std::uint64_t hash = hashSampleAudio(sample);
        result.stats.audioBytesBeforeDedup += static_cast<std::uint64_t>(sample.audioData.size());
        std::size_t uniqueIndex = std::numeric_limits<std::size_t>::max();
        const auto bucket = hashBuckets.find(hash);
        if (bucket != hashBuckets.end()) {
            for (const auto candidate : bucket->second) {
                if (sameAudio(uniqueAudio[candidate], sample)) { uniqueIndex = candidate; break; }
            }
        }
        if (uniqueIndex == std::numeric_limits<std::size_t>::max()) {
            UniqueAudio entry{};
            entry.hash = hash;
            entry.sampleRate = sample.sampleRate;
            entry.channels = sample.channels;
            entry.encoding = sample.encoding;
            entry.bitsPerSample = sample.bitsPerSample;
            entry.offset = static_cast<std::uint64_t>(audioBytes.size());
            entry.bytes = sample.audioData;
            audioBytes.insert(audioBytes.end(), entry.bytes.begin(), entry.bytes.end());
            uniqueIndex = uniqueAudio.size();
            uniqueAudio.push_back(std::move(entry));
            hashBuckets[hash].push_back(uniqueIndex);
        }
        const auto& audio = uniqueAudio[uniqueIndex];
        SvSampleRecord sr{};
        sr.nameOffset = strings.add(sample.name);
        sr.sourceIdentityOffset = strings.add(sample.sourceIdentity);
        sr.sampleRate = sample.sampleRate; sr.channels = sample.channels;
        sr.encoding = static_cast<std::uint8_t>(sample.encoding); sr.bitsPerSample = sample.bitsPerSample; sr.rootKey = sample.rootKey;
        sr.loopEnabled = sample.loop.enabled ? 1U : 0U; sr.fineTuneCents = sample.fineTuneCents; sr.totalFrames = sample.totalFrames;
        sr.loopStart = sample.loop.startFrame; sr.loopEnd = sample.loop.endFrame; sr.loopCrossfadeFrames = sample.loop.crossfadeFrames;
        sr.audioOffset = audio.offset; sr.audioSize = static_cast<std::uint64_t>(audio.bytes.size()); sr.audioHash = hash;
        appendSampleRecord(sampleBytes, sr);
    }

    result.stats.soundCount = header.soundCount;
    result.stats.multisampleCount = header.multisampleCount;
    result.stats.sampleCount = header.sampleCount;
    result.stats.zoneCount = header.zoneCount;
    result.stats.uniqueAudioPayloadCount = static_cast<std::uint32_t>(uniqueAudio.size());
    result.stats.audioBytesAfterDedup = static_cast<std::uint64_t>(audioBytes.size());

    std::vector<std::uint8_t> file(kSvBankHeaderSize, 0U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Sounds)], soundBytes, 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::SoundLayers)], layerBytes, 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Multisamples)], multisampleBytes, 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Samples)], sampleBytes, 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Zones)], zoneBytes, 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Strings)], strings.bytes(), 16U);
    appendSection(file, header.sections[static_cast<std::size_t>(SvSection::Audio)], audioBytes, 4096U);
    header.fileSize = static_cast<std::uint64_t>(file.size());
    header.payloadSha256 = sha256(file.data() + kSvBankHeaderSize, file.size() - kSvBankHeaderSize);
    const auto headerBytes = serializeHeader(header);
    std::copy(headerBytes.begin(), headerBytes.end(), file.begin());
    result.bytes = std::move(file);
    return result;
}

bool SvBankBuilder::writeAtomic(const std::string& path, const BankProject& project, SvBuildStats& stats, std::string& error) {
    const auto built = build(project);
    if (!built.ok()) { error = built.error; return false; }
    const std::filesystem::path target(path);
    const std::filesystem::path temp = target.string() + ".tmp";
    {
        std::ofstream out(temp, std::ios::binary | std::ios::trunc);
        if (!out) { error = "Cannot create temporary bank file: " + temp.string(); return false; }
        out.write(reinterpret_cast<const char*>(built.bytes.data()), static_cast<std::streamsize>(built.bytes.size()));
        if (!out) { error = "Failed while writing temporary bank file"; return false; }
        out.flush();
        if (!out) { error = "Failed while flushing temporary bank file"; return false; }
    }
    std::error_code ec;
    std::filesystem::rename(temp, target, ec);
    if (ec) {
        std::filesystem::remove(target, ec);
        ec.clear();
        std::filesystem::rename(temp, target, ec);
    }
    if (ec) {
        std::filesystem::remove(temp);
        error = "Atomic bank replacement failed: " + ec.message();
        return false;
    }
    stats = built.stats;
    error.clear();
    return true;
}

} // namespace silveton::manager
