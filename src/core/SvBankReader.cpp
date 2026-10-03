#include "silveton/manager/SvBankReader.h"

#include <algorithm>
#include <cstdint>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

namespace silveton::manager {
namespace {

bool sectionValid(const SvBankHeader& header, SvSection section) noexcept {
    const auto& s = header.sections[static_cast<std::size_t>(section)];
    return s.offset >= kSvBankHeaderSize && s.offset <= header.fileSize && s.size <= header.fileSize - s.offset;
}

bool recordSectionSize(const SvBankHeader& header, SvSection section, std::uint64_t count, std::size_t recordSize) noexcept {
    const auto& s = header.sections[static_cast<std::size_t>(section)];
    if (count > std::numeric_limits<std::uint64_t>::max() / recordSize) return false;
    return s.size == count * static_cast<std::uint64_t>(recordSize);
}

bool readString(const std::vector<std::uint8_t>& bytes, const SvBankHeader& header,
                std::uint32_t offset, std::string& out) {
    const auto& strings = header.sections[static_cast<std::size_t>(SvSection::Strings)];
    if (offset >= strings.size) return false;
    const std::size_t begin = static_cast<std::size_t>(strings.offset + offset);
    const std::size_t end = static_cast<std::size_t>(strings.offset + strings.size);
    std::size_t pos = begin;
    while (pos < end && bytes[pos] != 0U) ++pos;
    if (pos >= end) return false;
    out.assign(reinterpret_cast<const char*>(bytes.data() + begin), pos - begin);
    return true;
}

} // namespace

SvReadResult SvBankReader::read(const std::vector<std::uint8_t>& bytes, bool verifyIntegrity) {
    SvReadResult out{};
    if (!deserializeHeader(bytes.data(), bytes.size(), out.header, out.error)) return out;
    if (out.header.fileSize != bytes.size()) { out.error = "SV bank file-size mismatch"; return out; }
    for (std::size_t i = 0; i < kSvSectionCount; ++i) {
        if (!sectionValid(out.header, static_cast<SvSection>(i))) {
            out.error = "SV bank section is outside file bounds";
            return out;
        }
    }
    if (!recordSectionSize(out.header, SvSection::Sounds, out.header.soundCount, kSvSoundRecordSize) ||
        !recordSectionSize(out.header, SvSection::SoundLayers, out.header.soundLayerCount, kSvSoundLayerRecordSize) ||
        !recordSectionSize(out.header, SvSection::Multisamples, out.header.multisampleCount, kSvMultisampleRecordSize) ||
        !recordSectionSize(out.header, SvSection::Samples, out.header.sampleCount, kSvSampleRecordSize) ||
        !recordSectionSize(out.header, SvSection::Zones, out.header.zoneCount, kSvZoneRecordSize)) {
        out.error = "SV bank record-section size mismatch";
        return out;
    }
    if (verifyIntegrity) {
        const auto digest = sha256(bytes.data() + kSvBankHeaderSize, bytes.size() - kSvBankHeaderSize);
        if (digest != out.header.payloadSha256) { out.error = "SV bank SHA-256 integrity mismatch"; return out; }
    }

    if (!readString(bytes, out.header, out.header.bankNameOffset, out.project.name)) {
        out.error = "SV bank name string offset is invalid";
        return out;
    }

    const auto& sampleSec = out.header.sections[static_cast<std::size_t>(SvSection::Samples)];
    const auto& audioSec = out.header.sections[static_cast<std::size_t>(SvSection::Audio)];
    out.project.samples.reserve(out.header.sampleCount);
    for (std::uint32_t i = 0; i < out.header.sampleCount; ++i) {
        SvSampleRecord sr{};
        const std::size_t offset = static_cast<std::size_t>(sampleSec.offset) + static_cast<std::size_t>(i) * kSvSampleRecordSize;
        if (!readSampleRecord(bytes.data() + offset, bytes.size() - offset, sr)) { out.error = "Cannot decode SV sample record"; return out; }
        if (sr.audioOffset > audioSec.size || sr.audioSize > audioSec.size - sr.audioOffset) { out.error = "SV sample audio range is invalid"; return out; }
        ImportedSample sample{};
        if (!readString(bytes, out.header, sr.nameOffset, sample.name) || !readString(bytes, out.header, sr.sourceIdentityOffset, sample.sourceIdentity)) {
            out.error = "SV sample string offset is invalid";
            return out;
        }
        sample.sampleRate = sr.sampleRate; sample.channels = sr.channels; sample.encoding = static_cast<AudioEncoding>(sr.encoding);
        sample.bitsPerSample = sr.bitsPerSample; sample.rootKey = sr.rootKey; sample.fineTuneCents = sr.fineTuneCents; sample.totalFrames = sr.totalFrames;
        sample.loop.enabled = sr.loopEnabled != 0U; sample.loop.startFrame = sr.loopStart; sample.loop.endFrame = sr.loopEnd; sample.loop.crossfadeFrames = sr.loopCrossfadeFrames;
        const std::size_t audioStart = static_cast<std::size_t>(audioSec.offset + sr.audioOffset);
        sample.audioData.assign(bytes.begin() + static_cast<std::ptrdiff_t>(audioStart), bytes.begin() + static_cast<std::ptrdiff_t>(audioStart + sr.audioSize));
        if (!sample.valid()) { out.error = "SV sample record failed semantic validation"; return out; }
        out.project.samples.push_back(std::move(sample));
    }

    const auto& zoneSec = out.header.sections[static_cast<std::size_t>(SvSection::Zones)];
    std::vector<ImportedZone> allZones;
    allZones.reserve(out.header.zoneCount);
    for (std::uint32_t i = 0; i < out.header.zoneCount; ++i) {
        SvZoneRecord zr{};
        const std::size_t offset = static_cast<std::size_t>(zoneSec.offset) + static_cast<std::size_t>(i) * kSvZoneRecordSize;
        if (!readZoneRecord(bytes.data() + offset, bytes.size() - offset, zr)) { out.error = "Cannot decode SV zone record"; return out; }
        if (zr.sampleIndex >= out.project.samples.size()) { out.error = "SV zone references invalid sample"; return out; }
        ImportedZone z{};
        z.sampleIndex = zr.sampleIndex; z.keyLow = zr.keyLow; z.keyHigh = zr.keyHigh; z.velocityLow = zr.velocityLow; z.velocityHigh = zr.velocityHigh;
        z.rootKey = zr.rootKey; z.transposeSemitones = zr.transposeSemitones; z.oneShot = (zr.flags & 1U) != 0U; z.reverse = (zr.flags & 2U) != 0U; z.nonTranspose = (zr.flags & 4U) != 0U;
        z.sourcePanRaw = zr.sourcePanRaw; z.sourceLevelRaw = zr.sourceLevelRaw; z.sourceFilterRaw = zr.sourceFilterRaw;
        z.tuneCents = zr.tuneCents; z.gainDb = zr.gainDb; z.pan = zr.pan;
        if (z.keyLow > z.keyHigh || z.velocityLow == 0U || z.velocityLow > z.velocityHigh) { out.error = "SV zone failed semantic validation"; return out; }
        allZones.push_back(z);
    }

    const auto& msSec = out.header.sections[static_cast<std::size_t>(SvSection::Multisamples)];
    out.project.multisamples.reserve(out.header.multisampleCount);
    for (std::uint32_t i = 0; i < out.header.multisampleCount; ++i) {
        SvMultisampleRecord mr{};
        const std::size_t offset = static_cast<std::size_t>(msSec.offset) + static_cast<std::size_t>(i) * kSvMultisampleRecordSize;
        if (!readMultisampleRecord(bytes.data() + offset, bytes.size() - offset, mr)) { out.error = "Cannot decode SV multisample record"; return out; }
        if (mr.firstZone > allZones.size() || mr.zoneCount > allZones.size() - mr.firstZone) { out.error = "SV multisample zone range is invalid"; return out; }
        ImportedMultisample ms{};
        if (!readString(bytes, out.header, mr.nameOffset, ms.name) || !readString(bytes, out.header, mr.sourceIdentityOffset, ms.sourceIdentity)) {
            out.error = "SV multisample string offset is invalid";
            return out;
        }
        ms.zones.assign(allZones.begin() + static_cast<std::ptrdiff_t>(mr.firstZone), allZones.begin() + static_cast<std::ptrdiff_t>(mr.firstZone + mr.zoneCount));
        if (ms.zones.empty()) { out.error = "SV multisample has no zones"; return out; }
        out.project.multisamples.push_back(std::move(ms));
    }

    const auto& layerSec = out.header.sections[static_cast<std::size_t>(SvSection::SoundLayers)];
    std::vector<SoundLayer> allLayers;
    allLayers.reserve(out.header.soundLayerCount);
    for (std::uint32_t i = 0; i < out.header.soundLayerCount; ++i) {
        SvSoundLayerRecord lr{};
        const std::size_t offset = static_cast<std::size_t>(layerSec.offset) + static_cast<std::size_t>(i) * kSvSoundLayerRecordSize;
        if (!readSoundLayerRecord(bytes.data() + offset, bytes.size() - offset, lr)) { out.error = "Cannot decode SV SOUND layer record"; return out; }
        if (lr.multisampleIndex >= out.project.multisamples.size()) { out.error = "SV SOUND layer references invalid multisample"; return out; }
        SoundLayer layer{};
        layer.multisampleIndex = lr.multisampleIndex; layer.enabled = lr.enabled != 0U; layer.keyLow = lr.keyLow; layer.keyHigh = lr.keyHigh;
        layer.velocityLow = lr.velocityLow; layer.velocityHigh = lr.velocityHigh; layer.transposeSemitones = lr.transposeSemitones;
        layer.tuneCents = lr.tuneCents; layer.levelDb = lr.levelDb; layer.pan = lr.pan;
        allLayers.push_back(layer);
    }

    const auto& soundSec = out.header.sections[static_cast<std::size_t>(SvSection::Sounds)];
    out.project.sounds.reserve(out.header.soundCount);
    for (std::uint32_t i = 0; i < out.header.soundCount; ++i) {
        SvSoundRecord sr{};
        const std::size_t offset = static_cast<std::size_t>(soundSec.offset) + static_cast<std::size_t>(i) * kSvSoundRecordSize;
        if (!readSoundRecord(bytes.data() + offset, bytes.size() - offset, sr)) { out.error = "Cannot decode SV SOUND record"; return out; }
        if (sr.firstLayer > allLayers.size() || sr.layerCount > allLayers.size() - sr.firstLayer) { out.error = "SV SOUND layer range is invalid"; return out; }
        SoundDefinition sound{};
        if (!readString(bytes, out.header, sr.nameOffset, sound.name)) { out.error = "SV SOUND name offset is invalid"; return out; }
        sound.bank = sr.bank; sound.page = sr.page; sound.slot = sr.slot; sound.category = sr.category;
        sound.layers.assign(allLayers.begin() + static_cast<std::ptrdiff_t>(sr.firstLayer), allLayers.begin() + static_cast<std::ptrdiff_t>(sr.firstLayer + sr.layerCount));
        if (sound.layers.empty()) { out.error = "SV SOUND has no layers"; return out; }
        out.project.sounds.push_back(std::move(sound));
    }

    out.error.clear();
    return out;
}

SvReadResult SvBankReader::readFile(const std::string& path, bool verifyIntegrity) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in) { SvReadResult r{}; r.error = "Cannot open SV bank: " + path; return r; }
    const auto size = in.tellg();
    if (size < 0) { SvReadResult r{}; r.error = "Cannot determine SV bank size"; return r; }
    in.seekg(0, std::ios::beg);
    std::vector<std::uint8_t> bytes(static_cast<std::size_t>(size));
    if (!bytes.empty() && !in.read(reinterpret_cast<char*>(bytes.data()), size)) { SvReadResult r{}; r.error = "Failed to read SV bank"; return r; }
    return read(bytes, verifyIntegrity);
}

} // namespace silveton::manager
