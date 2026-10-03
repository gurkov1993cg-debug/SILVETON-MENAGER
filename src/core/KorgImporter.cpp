#include "silveton/manager/KorgImporter.h"

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_set>
#include <vector>

namespace silveton::manager {
namespace {

std::uint32_t be32(const std::uint8_t* p) noexcept {
    return (static_cast<std::uint32_t>(p[0]) << 24U) |
           (static_cast<std::uint32_t>(p[1]) << 16U) |
           (static_cast<std::uint32_t>(p[2]) << 8U) |
           static_cast<std::uint32_t>(p[3]);
}

std::uint32_t be24(const std::uint8_t* p) noexcept {
    return (static_cast<std::uint32_t>(p[0]) << 16U) |
           (static_cast<std::uint32_t>(p[1]) << 8U) |
           static_cast<std::uint32_t>(p[2]);
}

bool readAll(const std::string& path, std::vector<std::uint8_t>& out, std::string& error) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) { error = "Cannot open Korg file: " + path; return false; }
    const std::streamsize size = f.tellg();
    if (size <= 0) { error = "Korg file is empty: " + path; return false; }
    f.seekg(0, std::ios::beg);
    out.resize(static_cast<std::size_t>(size));
    if (!f.read(reinterpret_cast<char*>(out.data()), size)) {
        error = "Failed to read Korg file: " + path;
        return false;
    }
    return true;
}

std::string fixedString(const std::uint8_t* p, std::size_t n) {
    std::size_t len = 0U;
    while (len < n && p[len] != 0U) ++len;
    while (len > 0U && p[len - 1U] == static_cast<std::uint8_t>(' ')) --len;
    return std::string(reinterpret_cast<const char*>(p), len);
}

std::string trim(const std::string& s) {
    std::size_t first = 0U;
    while (first < s.size() && std::isspace(static_cast<unsigned char>(s[first])) != 0) ++first;
    std::size_t last = s.size();
    while (last > first && std::isspace(static_cast<unsigned char>(s[last - 1U])) != 0) --last;
    return s.substr(first, last - first);
}

struct Chunk {
    std::array<char, 4> id{};
    const std::uint8_t* data{nullptr};
    std::size_t size{0U};
};

bool idIs(const Chunk& c, const char* id) noexcept {
    return c.id[0] == id[0] && c.id[1] == id[1] && c.id[2] == id[2] && c.id[3] == id[3];
}

bool parseChunks(const std::vector<std::uint8_t>& bytes, std::vector<Chunk>& chunks, std::string& error) {
    std::size_t pos = 0U;
    while (pos + 8U <= bytes.size()) {
        Chunk chunk{};
        for (std::size_t i = 0U; i < 4U; ++i) chunk.id[i] = static_cast<char>(bytes[pos + i]);
        chunk.size = static_cast<std::size_t>(be32(bytes.data() + pos + 4U));
        const std::size_t payload = pos + 8U;
        if (payload > bytes.size() || chunk.size > bytes.size() - payload) {
            error = "Corrupt Korg chunk size";
            return false;
        }
        chunk.data = bytes.data() + payload;
        chunks.push_back(chunk);
        pos = payload + chunk.size;
    }
    if (pos != bytes.size()) {
        error = "Trailing bytes after final Korg chunk";
        return false;
    }
    if (chunks.empty()) {
        error = "Korg file contains no chunks";
        return false;
    }
    return true;
}

const Chunk* findChunk(const std::vector<Chunk>& chunks, const char* id) noexcept {
    for (const auto& chunk : chunks) if (idIs(chunk, id)) return &chunk;
    return nullptr;
}

std::string sourceIdentityFor(const std::filesystem::path& path) {
    std::error_code ec;
    const auto canonical = std::filesystem::weakly_canonical(path, ec);
    return (ec ? path.lexically_normal() : canonical).generic_string();
}

std::string ksfPathFor(const std::filesystem::path& kmpPath, const std::string& filename) {
    const auto direct = kmpPath.parent_path() / filename;
    if (std::filesystem::exists(direct)) return direct.string();
    const auto nested = kmpPath.parent_path() / kmpPath.stem() / filename;
    if (std::filesystem::exists(nested)) return nested.string();
    return direct.string();
}

std::string lowerExtension(std::filesystem::path p) {
    std::string ext = p.extension().string();
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext;
}

} // namespace

float KorgImporter::normalizedPan(std::uint8_t raw) noexcept {
    if (raw == 64U) return 0.0F;
    if (raw < 64U) return static_cast<float>(static_cast<int>(raw) - 64) / 64.0F;
    return static_cast<float>(static_cast<int>(raw) - 64) / 63.0F;
}

KorgSampleResult KorgImporter::loadKsf(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::string error;
    if (!readAll(path, bytes, error)) return {{}, error};

    std::vector<Chunk> chunks;
    if (!parseChunks(bytes, chunks, error)) return {{}, error};
    const Chunk* smp = findChunk(chunks, "SMP1");
    const Chunk* smd = findChunk(chunks, "SMD1");
    if (smp == nullptr || smp->size < 32U || smd == nullptr || smd->size < 12U) {
        return {{}, "KSF requires SMP1(32) and SMD1 chunks"};
    }

    const std::uint32_t sampleRate = be32(smd->data);
    const auto loopTune = static_cast<std::int8_t>(smd->data[5U]);
    const std::uint8_t channels = smd->data[6U];
    const std::uint8_t bitDepth = smd->data[7U];
    const std::uint32_t samplePoints = be32(smd->data + 8U);
    if (sampleRate == 0U || channels == 0U || channels > 2U || bitDepth != 16U) {
        return {{}, "Manager KSF import currently requires uncompressed 16-bit mono/stereo PCM"};
    }

    const std::uint64_t expectedBytes = static_cast<std::uint64_t>(samplePoints) * channels * 2U;
    if (smd->size != 12U + expectedBytes) {
        return {{}, "Compressed, divided, or malformed KSF data is not supported"};
    }

    const std::uint32_t modernStart = be32(smp->data + 16U);
    const bool oldLayout = smp->data[16U] <= 3U && modernStart > samplePoints;
    std::uint32_t start = 0U;
    std::uint32_t loopStart = 0U;
    std::uint32_t loopEnd = 0U;
    if (oldLayout) {
        start = be24(smp->data + 17U);
        loopStart = be32(smp->data + 24U);
        loopEnd = be32(smp->data + 28U);
    } else {
        start = modernStart;
        loopStart = be32(smp->data + 24U);
        loopEnd = be32(smp->data + 28U);
    }
    if (start >= samplePoints) start = 0U;

    ImportedSample out{};
    out.name = fixedString(smp->data, 16U);
    out.sourcePath = path;
    out.sourceIdentity = sourceIdentityFor(path);
    out.sampleRate = sampleRate;
    out.channels = channels;
    out.encoding = AudioEncoding::Pcm16LE;
    out.bitsPerSample = 16U;
    out.fineTuneCents = static_cast<float>(loopTune);
    out.totalFrames = static_cast<std::uint64_t>(samplePoints - start);

    const std::uint8_t* sourcePcm = smd->data + 12U + static_cast<std::size_t>(start) * channels * 2U;
    const std::size_t pcmBytes = static_cast<std::size_t>(out.totalFrames) * channels * 2U;
    out.audioData.resize(pcmBytes);
    for (std::size_t i = 0U; i < pcmBytes; i += 2U) {
        out.audioData[i] = sourcePcm[i + 1U];
        out.audioData[i + 1U] = sourcePcm[i];
    }

    if (loopStart >= start) loopStart -= start; else loopStart = 0U;
    if (loopEnd >= start) loopEnd -= start; else loopEnd = 0U;
    if (loopEnd > loopStart && static_cast<std::uint64_t>(loopEnd) <= out.totalFrames) {
        out.loop.enabled = true;
        out.loop.startFrame = loopStart;
        out.loop.endFrame = loopEnd;
    }

    if (!out.valid()) return {{}, "Decoded KSF sample failed validation"};
    return {std::move(out), {}};
}

KorgImportResult KorgImporter::loadKmp(const std::string& path) {
    std::vector<std::uint8_t> bytes;
    std::string error;
    if (!readAll(path, bytes, error)) return {{}, {}, error, {}};

    std::vector<Chunk> chunks;
    if (!parseChunks(bytes, chunks, error)) return {{}, {}, error, {}};
    const Chunk* msp = findChunk(chunks, "MSP1");
    const Chunk* rlp = findChunk(chunks, "RLP1");
    if (msp == nullptr || msp->size < 18U || rlp == nullptr) {
        return {{}, {}, "KMP requires MSP1 and RLP1 chunks", {}};
    }

    const std::uint8_t regionCount = msp->data[16U];
    if (regionCount == 0U || rlp->size < static_cast<std::size_t>(regionCount) * 18U) {
        return {{}, {}, "KMP RLP1 region count/size mismatch", {}};
    }

    KorgImportResult out{};
    out.multisample.name = fixedString(msp->data, 16U);
    out.multisample.sourceIdentity = sourceIdentityFor(path);
    const std::filesystem::path kmpPath(path);
    std::uint8_t lowKey = 0U;

    for (std::uint8_t i = 0U; i < regionCount; ++i) {
        const std::uint8_t* r = rlp->data + static_cast<std::size_t>(i) * 18U;
        const std::uint8_t originalRaw = r[0U];
        const bool nonTranspose = (originalRaw & 0x80U) != 0U;
        const std::uint8_t originalKey = static_cast<std::uint8_t>(originalRaw & 0x7FU);
        const std::uint8_t topKey = static_cast<std::uint8_t>(std::min<int>(127, r[1U]));
        const auto tune = static_cast<std::int8_t>(r[2U]);
        const auto level = static_cast<std::int8_t>(r[3U]);
        const std::uint8_t panRaw = r[4U];
        const auto cutoff = static_cast<std::int8_t>(r[5U]);
        const std::string filename = fixedString(r + 6U, 12U);

        if (filename.empty() || filename == "SKIPPEDSAMPL" || filename.rfind("INTERNAL", 0U) == 0U) {
            out.warnings.push_back("Skipped KMP region with unavailable sample: " + filename);
            lowKey = topKey < 127U ? static_cast<std::uint8_t>(topKey + 1U) : 127U;
            continue;
        }

        const auto sampleResult = loadKsf(ksfPathFor(kmpPath, filename));
        if (!sampleResult.ok()) {
            out.warnings.push_back(filename + ": " + sampleResult.error);
            lowKey = topKey < 127U ? static_cast<std::uint8_t>(topKey + 1U) : 127U;
            continue;
        }

        const std::uint32_t sampleIndex = static_cast<std::uint32_t>(out.samples.size());
        out.samples.push_back(sampleResult.sample);
        ImportedZone zone{};
        zone.sampleIndex = sampleIndex;
        zone.keyLow = lowKey;
        zone.keyHigh = std::max(lowKey, topKey);
        zone.rootKey = originalKey;
        zone.tuneCents = static_cast<float>(tune);
        zone.nonTranspose = nonTranspose;
        zone.sourceLevelRaw = level;
        zone.sourceFilterRaw = cutoff;
        zone.sourcePanRaw = panRaw;
        zone.pan = normalizedPan(panRaw);
        zone.gainDb = 0.0F;
        out.multisample.zones.push_back(zone);
        lowKey = topKey < 127U ? static_cast<std::uint8_t>(topKey + 1U) : 127U;
    }

    if (out.multisample.zones.empty()) {
        out.error = "KMP contained no loadable external KSF regions";
    }
    return out;
}

std::vector<std::string> KorgImporter::parseKsc(const std::string& path, std::string& error) {
    std::ifstream f(path);
    if (!f) { error = "Cannot open KSC file: " + path; return {}; }
    std::vector<std::string> entries;
    std::string line;
    bool sawHeader = false;
    while (std::getline(f, line)) {
        line = trim(line);
        if (line.empty()) continue;
        if (line[0] == '#') {
            if (!sawHeader && line.rfind("#KORG Script Version", 0U) == 0U) sawHeader = true;
            continue;
        }
        entries.push_back(line);
    }
    if (!sawHeader) {
        error = "KSC header is missing or unsupported";
        return {};
    }
    error.clear();
    return entries;
}

KorgCollectionResult KorgImporter::loadKsc(const std::string& path) {
    KorgCollectionResult out{};
    std::string error;
    const auto entries = parseKsc(path, error);
    if (!error.empty()) { out.error = error; return out; }

    const std::filesystem::path base = std::filesystem::path(path).parent_path();
    std::unordered_set<std::string> sampleIdentities;
    for (const auto& entry : entries) {
        std::filesystem::path p = entry;
        if (p.is_relative()) p = base / p;
        const auto ext = lowerExtension(p);
        if (ext == ".kmp") {
            auto imported = loadKmp(p.string());
            if (!imported.ok()) {
                out.warnings.push_back(p.filename().string() + ": " + imported.error);
                continue;
            }
            const std::uint32_t sampleBase = static_cast<std::uint32_t>(out.samples.size());
            for (auto& zone : imported.multisample.zones) zone.sampleIndex += sampleBase;
            for (auto& sample : imported.samples) {
                sampleIdentities.insert(sample.sourceIdentity);
                out.samples.push_back(std::move(sample));
            }
            out.multisamples.push_back(std::move(imported.multisample));
            out.warnings.insert(out.warnings.end(), imported.warnings.begin(), imported.warnings.end());
        } else if (ext == ".ksf") {
            auto sample = loadKsf(p.string());
            if (!sample.ok()) {
                out.warnings.push_back(p.filename().string() + ": " + sample.error);
                continue;
            }
            if (sampleIdentities.find(sample.sample.sourceIdentity) != sampleIdentities.end()) continue;
            const std::uint32_t sampleIndex = static_cast<std::uint32_t>(out.samples.size());
            ImportedMultisample ms{};
            ms.name = sample.sample.name.empty() ? p.stem().string() : sample.sample.name;
            ms.sourceIdentity = std::string("KSF:") + sample.sample.sourceIdentity;
            ImportedZone zone{};
            zone.sampleIndex = sampleIndex;
            zone.rootKey = sample.sample.rootKey;
            ms.zones.push_back(zone);
            sampleIdentities.insert(sample.sample.sourceIdentity);
            out.samples.push_back(std::move(sample.sample));
            out.multisamples.push_back(std::move(ms));
        } else {
            out.warnings.push_back("Skipped unsupported KSC entry: " + entry);
        }
    }

    if (out.multisamples.empty()) out.error = "KSC contained no loadable KMP/KSF resources";
    return out;
}

} // namespace silveton::manager
