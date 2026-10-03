#include "silveton/manager/SampleEditor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

namespace silveton::manager {
namespace {

std::size_t regionBytesPerSample(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 2U;
        case AudioEncoding::Pcm24LE: return 3U;
        case AudioEncoding::Float32LE: return 4U;
    }
    return 0U;
}

std::size_t regionFrameBytes(const ImportedSample& sample) noexcept {
    return static_cast<std::size_t>(sample.channels) * regionBytesPerSample(sample.encoding);
}

bool regionEditable(const ImportedSample& sample, std::string& error) {
    if (!sample.valid()) {
        error = "Sample data is invalid";
        return false;
    }
    if (regionBytesPerSample(sample.encoding) == 0U) {
        error = "Unsupported sample encoding";
        return false;
    }
    return true;
}

bool validRange(const ImportedSample& sample,
                std::uint64_t startFrame,
                std::uint64_t endFrame,
                std::string& error) {
    if (!regionEditable(sample, error)) return false;
    if (startFrame >= endFrame || endFrame > sample.totalFrames) {
        error = "Edit range must satisfy start < end <= total frames";
        return false;
    }
    return true;
}

float readRegionScalar(const std::uint8_t* p, AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: {
            const std::uint16_t raw = static_cast<std::uint16_t>(p[0]) |
                                      static_cast<std::uint16_t>(static_cast<std::uint16_t>(p[1]) << 8U);
            const std::int16_t value = static_cast<std::int16_t>(raw);
            return value < 0 ? static_cast<float>(value) / 32768.0F
                             : static_cast<float>(value) / 32767.0F;
        }
        case AudioEncoding::Pcm24LE: {
            std::int32_t value = static_cast<std::int32_t>(p[0]) |
                                 (static_cast<std::int32_t>(p[1]) << 8) |
                                 (static_cast<std::int32_t>(p[2]) << 16);
            if ((value & 0x00800000) != 0) value |= static_cast<std::int32_t>(0xFF000000U);
            return value < 0 ? static_cast<float>(value) / 8388608.0F
                             : static_cast<float>(value) / 8388607.0F;
        }
        case AudioEncoding::Float32LE: {
            const std::uint32_t raw = static_cast<std::uint32_t>(p[0]) |
                                      (static_cast<std::uint32_t>(p[1]) << 8U) |
                                      (static_cast<std::uint32_t>(p[2]) << 16U) |
                                      (static_cast<std::uint32_t>(p[3]) << 24U);
            float value = 0.0F;
            std::memcpy(&value, &raw, sizeof(value));
            return std::isfinite(value) ? value : 0.0F;
        }
    }
    return 0.0F;
}

float clampRegionAudio(float value) noexcept {
    return std::max(-1.0F, std::min(1.0F, value));
}

void writeRegionScalar(std::uint8_t* p, AudioEncoding encoding, float input) noexcept {
    const float value = clampRegionAudio(input);
    switch (encoding) {
        case AudioEncoding::Pcm16LE: {
            std::int32_t quantized = 0;
            if (value <= -1.0F) quantized = -32768;
            else if (value >= 1.0F) quantized = 32767;
            else if (value < 0.0F) quantized = static_cast<std::int32_t>(std::lround(static_cast<double>(value) * 32768.0));
            else quantized = static_cast<std::int32_t>(std::lround(static_cast<double>(value) * 32767.0));
            const std::uint16_t raw = static_cast<std::uint16_t>(static_cast<std::int16_t>(quantized));
            p[0] = static_cast<std::uint8_t>(raw & 0xFFU);
            p[1] = static_cast<std::uint8_t>((raw >> 8U) & 0xFFU);
            break;
        }
        case AudioEncoding::Pcm24LE: {
            std::int32_t quantized = 0;
            if (value <= -1.0F) quantized = -8388608;
            else if (value >= 1.0F) quantized = 8388607;
            else if (value < 0.0F) quantized = static_cast<std::int32_t>(std::lround(static_cast<double>(value) * 8388608.0));
            else quantized = static_cast<std::int32_t>(std::lround(static_cast<double>(value) * 8388607.0));
            const std::uint32_t raw = static_cast<std::uint32_t>(quantized) & 0x00FFFFFFU;
            p[0] = static_cast<std::uint8_t>(raw & 0xFFU);
            p[1] = static_cast<std::uint8_t>((raw >> 8U) & 0xFFU);
            p[2] = static_cast<std::uint8_t>((raw >> 16U) & 0xFFU);
            break;
        }
        case AudioEncoding::Float32LE: {
            std::uint32_t raw = 0U;
            std::memcpy(&raw, &value, sizeof(raw));
            p[0] = static_cast<std::uint8_t>(raw & 0xFFU);
            p[1] = static_cast<std::uint8_t>((raw >> 8U) & 0xFFU);
            p[2] = static_cast<std::uint8_t>((raw >> 16U) & 0xFFU);
            p[3] = static_cast<std::uint8_t>((raw >> 24U) & 0xFFU);
            break;
        }
    }
}

bool regionCompatible(const ImportedSample& sample, const SampleRegion& region, std::string& error) {
    if (region.empty()) {
        error = "Sample clipboard is empty";
        return false;
    }
    if (sample.sampleRate != region.sampleRate || sample.channels != region.channels || sample.encoding != region.encoding) {
        error = "Clipboard audio format does not match the destination sample";
        return false;
    }
    if (region.bitsPerSample != 0U && sample.bitsPerSample != 0U && sample.bitsPerSample != region.bitsPerSample) {
        error = "Clipboard bit depth does not match the destination sample";
        return false;
    }
    const std::size_t fb = regionFrameBytes(sample);
    if (fb == 0U || region.frameCount > static_cast<std::uint64_t>(std::numeric_limits<std::size_t>::max() / fb)) {
        error = "Clipboard region is too large";
        return false;
    }
    const std::size_t expectedBytes = static_cast<std::size_t>(region.frameCount) * fb;
    if (region.audioData.size() != expectedBytes) {
        error = "Clipboard audio payload is invalid";
        return false;
    }
    return true;
}

void remapLoopAfterDelete(ImportedSample& sample,
                          std::uint64_t startFrame,
                          std::uint64_t endFrame) noexcept {
    if (!sample.loop.enabled) return;
    const std::uint64_t removed = endFrame - startFrame;
    if (endFrame <= sample.loop.startFrame) {
        sample.loop.startFrame -= removed;
        sample.loop.endFrame -= removed;
        return;
    }
    if (startFrame >= sample.loop.endFrame) return;
    sample.loop = {};
}

void remapLoopAfterInsert(ImportedSample& sample,
                          std::uint64_t atFrame,
                          std::uint64_t insertedFrames) noexcept {
    if (!sample.loop.enabled) return;
    if (atFrame <= sample.loop.startFrame) {
        sample.loop.startFrame += insertedFrames;
        sample.loop.endFrame += insertedFrames;
    } else if (atFrame < sample.loop.endFrame) {
        sample.loop.endFrame += insertedFrames;
    }
}

void remapLoopAfterReverseRegion(ImportedSample& sample,
                                 std::uint64_t startFrame,
                                 std::uint64_t endFrame) noexcept {
    if (!sample.loop.enabled) return;
    if (sample.loop.endFrame <= startFrame || sample.loop.startFrame >= endFrame) return;
    if (sample.loop.startFrame >= startFrame && sample.loop.endFrame <= endFrame) {
        const std::uint64_t oldStart = sample.loop.startFrame;
        const std::uint64_t oldEnd = sample.loop.endFrame;
        sample.loop.startFrame = startFrame + (endFrame - oldEnd);
        sample.loop.endFrame = startFrame + (endFrame - oldStart);
        return;
    }
    sample.loop = {};
}

bool applyRegionGainLinear(ImportedSample& sample,
                           std::uint64_t startFrame,
                           std::uint64_t endFrame,
                           float gain,
                           std::string& error) {
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::size_t bps = regionBytesPerSample(sample.encoding);
    const std::size_t fb = regionFrameBytes(sample);
    for (std::uint64_t frame = startFrame; frame < endFrame; ++frame) {
        const std::size_t frameOffset = static_cast<std::size_t>(frame) * fb;
        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            std::uint8_t* scalar = sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps;
            writeRegionScalar(scalar, sample.encoding, readRegionScalar(scalar, sample.encoding) * gain);
        }
    }
    return true;
}

} // namespace

bool SampleEditor::copyRegion(const ImportedSample& sample,
                              std::uint64_t startFrame,
                              std::uint64_t endFrame,
                              SampleRegion& region,
                              std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::size_t fb = regionFrameBytes(sample);
    const std::size_t byteStart = static_cast<std::size_t>(startFrame) * fb;
    const std::size_t byteEnd = static_cast<std::size_t>(endFrame) * fb;

    SampleRegion copied{};
    copied.sampleRate = sample.sampleRate;
    copied.channels = sample.channels;
    copied.encoding = sample.encoding;
    copied.bitsPerSample = sample.bitsPerSample;
    copied.frameCount = endFrame - startFrame;
    copied.audioData.assign(sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteStart),
                            sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteEnd));
    region = std::move(copied);
    return true;
}

bool SampleEditor::deleteRegion(ImportedSample& sample,
                                std::uint64_t startFrame,
                                std::uint64_t endFrame,
                                std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    if (startFrame == 0U && endFrame == sample.totalFrames) {
        error = "Delete range cannot remove the entire sample";
        return false;
    }

    const std::size_t fb = regionFrameBytes(sample);
    const std::size_t byteStart = static_cast<std::size_t>(startFrame) * fb;
    const std::size_t byteEnd = static_cast<std::size_t>(endFrame) * fb;
    remapLoopAfterDelete(sample, startFrame, endFrame);
    sample.audioData.erase(sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteStart),
                           sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteEnd));
    sample.totalFrames -= endFrame - startFrame;
    return sample.valid();
}

bool SampleEditor::silenceRegion(ImportedSample& sample,
                                 std::uint64_t startFrame,
                                 std::uint64_t endFrame,
                                 std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::size_t fb = regionFrameBytes(sample);
    const std::size_t byteStart = static_cast<std::size_t>(startFrame) * fb;
    const std::size_t byteEnd = static_cast<std::size_t>(endFrame) * fb;
    std::fill(sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteStart),
              sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteEnd),
              static_cast<std::uint8_t>(0U));
    return true;
}

bool SampleEditor::insertRegion(ImportedSample& sample,
                                std::uint64_t atFrame,
                                const SampleRegion& region,
                                std::string& error) {
    error.clear();
    if (!regionEditable(sample, error)) return false;
    if (atFrame > sample.totalFrames) {
        error = "Paste position must be inside or at the end of the sample";
        return false;
    }
    if (!regionCompatible(sample, region, error)) return false;
    if (region.frameCount > std::numeric_limits<std::uint64_t>::max() - sample.totalFrames) {
        error = "Pasted region would overflow sample frame count";
        return false;
    }

    const std::size_t fb = regionFrameBytes(sample);
    const std::size_t byteOffset = static_cast<std::size_t>(atFrame) * fb;
    remapLoopAfterInsert(sample, atFrame, region.frameCount);
    sample.audioData.insert(sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteOffset),
                            region.audioData.begin(), region.audioData.end());
    sample.totalFrames += region.frameCount;
    return sample.valid();
}

bool SampleEditor::reverseRegion(ImportedSample& sample,
                                 std::uint64_t startFrame,
                                 std::uint64_t endFrame,
                                 std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::size_t fb = regionFrameBytes(sample);
    std::array<std::uint8_t, 8U> temporary{};
    if (fb > temporary.size()) {
        error = "Sample frame size is unsupported";
        return false;
    }

    std::uint64_t left = startFrame;
    std::uint64_t right = endFrame - 1U;
    while (left < right) {
        std::uint8_t* leftPtr = sample.audioData.data() + static_cast<std::size_t>(left) * fb;
        std::uint8_t* rightPtr = sample.audioData.data() + static_cast<std::size_t>(right) * fb;
        std::copy(leftPtr, leftPtr + fb, temporary.begin());
        std::copy(rightPtr, rightPtr + fb, leftPtr);
        std::copy(temporary.begin(), temporary.begin() + static_cast<std::ptrdiff_t>(fb), rightPtr);
        ++left;
        --right;
    }
    remapLoopAfterReverseRegion(sample, startFrame, endFrame);
    return true;
}

bool SampleEditor::applyGainDbRegion(ImportedSample& sample,
                                     std::uint64_t startFrame,
                                     std::uint64_t endFrame,
                                     float gainDb,
                                     std::string& error) {
    error.clear();
    if (!std::isfinite(gainDb) || gainDb < -120.0F || gainDb > 60.0F) {
        error = "Gain must be finite and between -120 dB and +60 dB";
        return false;
    }
    const float gain = static_cast<float>(std::pow(10.0, static_cast<double>(gainDb) / 20.0));
    return applyRegionGainLinear(sample, startFrame, endFrame, gain, error);
}

bool SampleEditor::normalizeRegion(ImportedSample& sample,
                                   std::uint64_t startFrame,
                                   std::uint64_t endFrame,
                                   float targetPeakDb,
                                   std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    if (!std::isfinite(targetPeakDb) || targetPeakDb < -120.0F || targetPeakDb > 0.0F) {
        error = "Normalize target must be finite and between -120 dBFS and 0 dBFS";
        return false;
    }

    const std::size_t bps = regionBytesPerSample(sample.encoding);
    const std::size_t fb = regionFrameBytes(sample);
    float peak = 0.0F;
    for (std::uint64_t frame = startFrame; frame < endFrame; ++frame) {
        const std::size_t frameOffset = static_cast<std::size_t>(frame) * fb;
        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            const float value = readRegionScalar(sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps,
                                                 sample.encoding);
            peak = std::max(peak, std::fabs(value));
        }
    }
    if (!(peak > 0.0F)) {
        error = "Cannot normalize a silent range";
        return false;
    }
    const float target = static_cast<float>(std::pow(10.0, static_cast<double>(targetPeakDb) / 20.0));
    return applyRegionGainLinear(sample, startFrame, endFrame, target / peak, error);
}

bool SampleEditor::fadeInRegion(ImportedSample& sample,
                                std::uint64_t startFrame,
                                std::uint64_t endFrame,
                                std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::uint64_t count = endFrame - startFrame;
    const std::size_t bps = regionBytesPerSample(sample.encoding);
    const std::size_t fb = regionFrameBytes(sample);
    for (std::uint64_t index = 0U; index < count; ++index) {
        const float gain = count <= 1U ? 0.0F : static_cast<float>(static_cast<double>(index) / static_cast<double>(count - 1U));
        const std::size_t frameOffset = static_cast<std::size_t>(startFrame + index) * fb;
        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            std::uint8_t* scalar = sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps;
            writeRegionScalar(scalar, sample.encoding, readRegionScalar(scalar, sample.encoding) * gain);
        }
    }
    return true;
}

bool SampleEditor::fadeOutRegion(ImportedSample& sample,
                                 std::uint64_t startFrame,
                                 std::uint64_t endFrame,
                                 std::string& error) {
    error.clear();
    if (!validRange(sample, startFrame, endFrame, error)) return false;
    const std::uint64_t count = endFrame - startFrame;
    const std::size_t bps = regionBytesPerSample(sample.encoding);
    const std::size_t fb = regionFrameBytes(sample);
    for (std::uint64_t index = 0U; index < count; ++index) {
        const float gain = count <= 1U ? 0.0F : static_cast<float>(static_cast<double>((count - 1U) - index) / static_cast<double>(count - 1U));
        const std::size_t frameOffset = static_cast<std::size_t>(startFrame + index) * fb;
        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            std::uint8_t* scalar = sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps;
            writeRegionScalar(scalar, sample.encoding, readRegionScalar(scalar, sample.encoding) * gain);
        }
    }
    return true;
}

} // namespace silveton::manager
