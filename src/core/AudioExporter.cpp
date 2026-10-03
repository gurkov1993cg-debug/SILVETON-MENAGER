#include "silveton/manager/AudioExporter.h"

#include <cmath>
#include <cstdint>
#include <cstring>
#include <fstream>
#include <limits>
#include <string>
#include <vector>

namespace silveton::manager {
namespace {

void appendAscii(std::vector<std::uint8_t>& out, const char* text, std::size_t count) {
    for (std::size_t i = 0U; i < count; ++i) out.push_back(static_cast<std::uint8_t>(text[i]));
}

void appendLE16(std::vector<std::uint8_t>& out, std::uint16_t value) {
    out.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
}

void appendLE32(std::vector<std::uint8_t>& out, std::uint32_t value) {
    out.push_back(static_cast<std::uint8_t>(value & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xFFU));
}

void appendBE16(std::vector<std::uint8_t>& out, std::uint16_t value) {
    out.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

void appendBE32(std::vector<std::uint8_t>& out, std::uint32_t value) {
    out.push_back(static_cast<std::uint8_t>((value >> 24U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 16U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>((value >> 8U) & 0xFFU));
    out.push_back(static_cast<std::uint8_t>(value & 0xFFU));
}

void appendBE64(std::vector<std::uint8_t>& out, std::uint64_t value) {
    for (int shift = 56; shift >= 0; shift -= 8) {
        out.push_back(static_cast<std::uint8_t>((value >> static_cast<unsigned int>(shift)) & 0xFFU));
    }
}

std::uint16_t bitsForEncoding(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 16U;
        case AudioEncoding::Pcm24LE: return 24U;
        case AudioEncoding::Float32LE: return 32U;
    }
    return 0U;
}

std::uint16_t bytesForEncoding(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 2U;
        case AudioEncoding::Pcm24LE: return 3U;
        case AudioEncoding::Float32LE: return 4U;
    }
    return 0U;
}

bool checked32(std::uint64_t value, std::uint32_t& out) noexcept {
    if (value > static_cast<std::uint64_t>(std::numeric_limits<std::uint32_t>::max())) return false;
    out = static_cast<std::uint32_t>(value);
    return true;
}

std::vector<std::uint8_t> aiffAudioBytes(const ImportedSample& sample) {
    std::vector<std::uint8_t> out;
    out.reserve(sample.audioData.size());
    const std::uint16_t bytesPerSample = bytesForEncoding(sample.encoding);
    for (std::size_t offset = 0U; offset < sample.audioData.size(); offset += bytesPerSample) {
        for (std::uint16_t i = 0U; i < bytesPerSample; ++i) {
            out.push_back(sample.audioData[offset + static_cast<std::size_t>(bytesPerSample - 1U - i)]);
        }
    }
    return out;
}

void appendExtended80(std::vector<std::uint8_t>& out, double value) {
    if (!(value > 0.0) || !std::isfinite(value)) {
        for (int i = 0; i < 10; ++i) out.push_back(0U);
        return;
    }

    int exponent = 0;
    const double fraction = std::frexp(value, &exponent);
    const long double normalized = static_cast<long double>(fraction) * 2.0L;
    const int unbiased = exponent - 1;
    const std::uint16_t biased = static_cast<std::uint16_t>(unbiased + 16383);
    long double mantissaValue = std::ldexp(normalized, 63);
    const long double max64 = static_cast<long double>(std::numeric_limits<std::uint64_t>::max());
    if (mantissaValue > max64) mantissaValue = max64;
    const std::uint64_t mantissa = static_cast<std::uint64_t>(mantissaValue);
    appendBE16(out, biased);
    appendBE64(out, mantissa);
}

bool buildWav(const ImportedSample& sample, std::vector<std::uint8_t>& bytes, std::string& error) {
    const std::uint16_t bits = bitsForEncoding(sample.encoding);
    const std::uint16_t bytesPerSample = bytesForEncoding(sample.encoding);
    if (bits == 0U || bytesPerSample == 0U) {
        error = "Unsupported WAV sample encoding.";
        return false;
    }

    std::uint32_t dataSize = 0U;
    if (!checked32(sample.audioData.size(), dataSize)) {
        error = "Sample is too large for RIFF/WAV export.";
        return false;
    }
    const std::uint16_t blockAlign = static_cast<std::uint16_t>(sample.channels * bytesPerSample);
    const std::uint64_t byteRate64 = static_cast<std::uint64_t>(sample.sampleRate) * blockAlign;
    std::uint32_t byteRate = 0U;
    if (!checked32(byteRate64, byteRate)) {
        error = "WAV byte rate is out of range.";
        return false;
    }
    const std::uint32_t pad = (dataSize & 1U) != 0U ? 1U : 0U;
    const std::uint64_t riffSize64 = 36ULL + static_cast<std::uint64_t>(dataSize) + pad;
    std::uint32_t riffSize = 0U;
    if (!checked32(riffSize64, riffSize)) {
        error = "WAV file is too large for RIFF.";
        return false;
    }

    bytes.clear();
    bytes.reserve(static_cast<std::size_t>(riffSize) + 8U);
    appendAscii(bytes, "RIFF", 4U);
    appendLE32(bytes, riffSize);
    appendAscii(bytes, "WAVE", 4U);
    appendAscii(bytes, "fmt ", 4U);
    appendLE32(bytes, 16U);
    appendLE16(bytes, sample.encoding == AudioEncoding::Float32LE ? 3U : 1U);
    appendLE16(bytes, sample.channels);
    appendLE32(bytes, sample.sampleRate);
    appendLE32(bytes, byteRate);
    appendLE16(bytes, blockAlign);
    appendLE16(bytes, bits);
    appendAscii(bytes, "data", 4U);
    appendLE32(bytes, dataSize);
    bytes.insert(bytes.end(), sample.audioData.begin(), sample.audioData.end());
    if (pad != 0U) bytes.push_back(0U);
    error.clear();
    return true;
}

bool buildAiff(const ImportedSample& sample, std::vector<std::uint8_t>& bytes, std::string& error) {
    const std::uint16_t bits = bitsForEncoding(sample.encoding);
    if (bits == 0U) {
        error = "Unsupported AIFF sample encoding.";
        return false;
    }
    std::uint32_t frames = 0U;
    if (!checked32(sample.totalFrames, frames)) {
        error = "Sample is too long for AIFF export.";
        return false;
    }

    std::vector<std::uint8_t> audio = aiffAudioBytes(sample);
    std::uint32_t audioSize = 0U;
    if (!checked32(audio.size(), audioSize)) {
        error = "Sample is too large for AIFF export.";
        return false;
    }
    const bool floatAifc = sample.encoding == AudioEncoding::Float32LE;
    const std::uint32_t commSize = floatAifc ? 44U : 18U;
    const std::uint32_t pad = (audioSize & 1U) != 0U ? 1U : 0U;
    const std::uint64_t formSize64 = 4ULL + 8ULL + commSize + 8ULL + 8ULL + static_cast<std::uint64_t>(audioSize) + pad;
    std::uint32_t formSize = 0U;
    if (!checked32(formSize64, formSize)) {
        error = "AIFF file is too large.";
        return false;
    }

    bytes.clear();
    bytes.reserve(static_cast<std::size_t>(formSize) + 8U);
    appendAscii(bytes, "FORM", 4U);
    appendBE32(bytes, formSize);
    appendAscii(bytes, floatAifc ? "AIFC" : "AIFF", 4U);
    appendAscii(bytes, "COMM", 4U);
    appendBE32(bytes, commSize);
    appendBE16(bytes, sample.channels);
    appendBE32(bytes, frames);
    appendBE16(bytes, bits);
    appendExtended80(bytes, static_cast<double>(sample.sampleRate));

    if (floatAifc) {
        appendAscii(bytes, "fl32", 4U);
        const char* name = "32-bit floating point";
        constexpr std::uint8_t nameLength = 21U;
        bytes.push_back(nameLength);
        appendAscii(bytes, name, nameLength);
    }

    appendAscii(bytes, "SSND", 4U);
    appendBE32(bytes, static_cast<std::uint32_t>(8U + audioSize));
    appendBE32(bytes, 0U);
    appendBE32(bytes, 0U);
    bytes.insert(bytes.end(), audio.begin(), audio.end());
    if (pad != 0U) bytes.push_back(0U);
    error.clear();
    return true;
}

} // namespace

bool AudioExporter::writeFile(const std::string& path,
                              const ImportedSample& sample,
                              ExportAudioFormat format,
                              std::string& error) {
    if (!sample.valid()) {
        error = "Cannot export an invalid sample.";
        return false;
    }
    if (path.empty()) {
        error = "No export path was supplied.";
        return false;
    }

    std::vector<std::uint8_t> bytes;
    const bool built = format == ExportAudioFormat::Wav ? buildWav(sample, bytes, error) : buildAiff(sample, bytes, error);
    if (!built) return false;

    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) {
        error = "Could not create export file: " + path;
        return false;
    }
    if (!bytes.empty()) {
        stream.write(reinterpret_cast<const char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
    }
    stream.close();
    if (!stream) {
        error = "Failed while writing export file: " + path;
        return false;
    }
    error.clear();
    return true;
}

} // namespace silveton::manager
