#include "silveton/manager/SampleEditor.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>

namespace silveton::manager {
namespace {

std::size_t bytesPerSample(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 2U;
        case AudioEncoding::Pcm24LE: return 3U;
        case AudioEncoding::Float32LE: return 4U;
    }
    return 0U;
}

std::size_t frameBytes(const ImportedSample& sample) noexcept {
    return static_cast<std::size_t>(sample.channels) * bytesPerSample(sample.encoding);
}

float readScalar(const std::uint8_t* p, AudioEncoding encoding) noexcept {
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

float clampAudio(float value) noexcept {
    return std::max(-1.0F, std::min(1.0F, value));
}

void writeScalar(std::uint8_t* p, AudioEncoding encoding, float input) noexcept {
    const float value = clampAudio(input);
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

bool editable(const ImportedSample& sample, std::string& error) {
    if (!sample.valid()) {
        error = "Sample data is invalid";
        return false;
    }
    if (bytesPerSample(sample.encoding) == 0U) {
        error = "Unsupported sample encoding";
        return false;
    }
    return true;
}

float frameValue(const ImportedSample& sample, std::uint64_t frame) noexcept {
    if (!sample.valid() || frame >= sample.totalFrames || sample.channels == 0U) return 0.0F;
    const std::size_t bps = bytesPerSample(sample.encoding);
    const std::size_t fb = frameBytes(sample);
    const std::size_t offset = static_cast<std::size_t>(frame) * fb;
    float sum = 0.0F;
    for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
        sum += readScalar(sample.audioData.data() + offset + static_cast<std::size_t>(channel) * bps, sample.encoding);
    }
    return sum / static_cast<float>(sample.channels);
}

void multiplyFrames(ImportedSample& sample,
                    std::uint64_t firstFrame,
                    std::uint64_t frameCount,
                    float (*gainForIndex)(std::uint64_t, std::uint64_t)) noexcept {
    const std::size_t bps = bytesPerSample(sample.encoding);
    const std::size_t fb = frameBytes(sample);
    for (std::uint64_t i = 0U; i < frameCount; ++i) {
        const float gain = gainForIndex(i, frameCount);
        const std::size_t frameOffset = static_cast<std::size_t>(firstFrame + i) * fb;
        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            std::uint8_t* scalar = sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps;
            writeScalar(scalar, sample.encoding, readScalar(scalar, sample.encoding) * gain);
        }
    }
}

float fadeInGain(std::uint64_t index, std::uint64_t count) noexcept {
    if (count <= 1U) return 0.0F;
    return static_cast<float>(static_cast<double>(index) / static_cast<double>(count - 1U));
}

float fadeOutGain(std::uint64_t index, std::uint64_t count) noexcept {
    if (count <= 1U) return 0.0F;
    return static_cast<float>(static_cast<double>((count - 1U) - index) / static_cast<double>(count - 1U));
}

} // namespace

bool SampleEditor::trim(ImportedSample& sample,
                        std::uint64_t startFrame,
                        std::uint64_t endFrame,
                        std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (startFrame >= endFrame || endFrame > sample.totalFrames) {
        error = "Trim range must satisfy start < end <= total frames";
        return false;
    }

    const std::size_t fb = frameBytes(sample);
    const std::size_t byteStart = static_cast<std::size_t>(startFrame) * fb;
    const std::size_t byteEnd = static_cast<std::size_t>(endFrame) * fb;
    std::vector<std::uint8_t> trimmed(sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteStart),
                                      sample.audioData.begin() + static_cast<std::ptrdiff_t>(byteEnd));
    sample.audioData.swap(trimmed);
    sample.totalFrames = endFrame - startFrame;

    if (sample.loop.enabled) {
        if (sample.loop.startFrame >= startFrame && sample.loop.endFrame <= endFrame) {
            sample.loop.startFrame -= startFrame;
            sample.loop.endFrame -= startFrame;
            const std::uint64_t loopLength = sample.loop.endFrame - sample.loop.startFrame;
            if (static_cast<std::uint64_t>(sample.loop.crossfadeFrames) * 2U > loopLength) {
                sample.loop.crossfadeFrames = static_cast<std::uint32_t>(loopLength / 2U);
            }
        } else {
            sample.loop = {};
        }
    }

    return sample.valid();
}

bool SampleEditor::setLoop(ImportedSample& sample,
                           bool enabled,
                           std::uint64_t startFrame,
                           std::uint64_t endFrame,
                           std::uint32_t crossfadeFrames,
                           std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (!enabled) {
        sample.loop = {};
        return true;
    }
    if (startFrame >= endFrame || endFrame > sample.totalFrames) {
        error = "Loop range must satisfy start < end <= total frames";
        return false;
    }
    const std::uint64_t loopLength = endFrame - startFrame;
    if (static_cast<std::uint64_t>(crossfadeFrames) * 2U > loopLength) {
        error = "Loop crossfade cannot exceed half of the loop length";
        return false;
    }
    sample.loop.enabled = true;
    sample.loop.startFrame = startFrame;
    sample.loop.endFrame = endFrame;
    sample.loop.crossfadeFrames = crossfadeFrames;
    return true;
}

bool SampleEditor::applyLoopCrossfade(ImportedSample& sample,
                                      std::uint32_t crossfadeFrames,
                                      std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (!sample.loop.enabled) {
        error = "Loop crossfade requires an enabled loop";
        return false;
    }
    if (sample.loop.startFrame >= sample.loop.endFrame || sample.loop.endFrame > sample.totalFrames) {
        error = "Configured loop range is invalid";
        return false;
    }
    if (crossfadeFrames == 0U) {
        error = "Loop crossfade length must be greater than zero";
        return false;
    }

    const std::uint64_t loopLength = sample.loop.endFrame - sample.loop.startFrame;
    if (static_cast<std::uint64_t>(crossfadeFrames) * 2U > loopLength) {
        error = "Loop crossfade cannot exceed half of the loop length";
        return false;
    }

    const std::size_t bps = bytesPerSample(sample.encoding);
    const std::size_t fb = frameBytes(sample);
    const std::uint64_t fadeFrames = static_cast<std::uint64_t>(crossfadeFrames);
    const std::uint64_t tailStart = sample.loop.endFrame - fadeFrames;
    const std::uint64_t headStart = sample.loop.startFrame;

    for (std::uint64_t i = 0U; i < fadeFrames; ++i) {
        const float headMix = static_cast<float>(static_cast<double>(i + 1U) / static_cast<double>(fadeFrames));
        const float tailMix = 1.0F - headMix;
        const std::size_t tailOffset = static_cast<std::size_t>(tailStart + i) * fb;
        const std::size_t headOffset = static_cast<std::size_t>(headStart + i) * fb;

        for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
            const std::size_t channelOffset = static_cast<std::size_t>(channel) * bps;
            std::uint8_t* tailScalar = sample.audioData.data() + tailOffset + channelOffset;
            const std::uint8_t* headScalar = sample.audioData.data() + headOffset + channelOffset;
            const float blended = readScalar(tailScalar, sample.encoding) * tailMix +
                                  readScalar(headScalar, sample.encoding) * headMix;
            writeScalar(tailScalar, sample.encoding, blended);
        }
    }

    // The first crossfadeFrames from the old loop head are now represented in
    // the overlap at the loop tail. Advancing the loop start prevents those
    // frames from being played a second time after the wrap.
    sample.loop.startFrame += fadeFrames;
    sample.loop.crossfadeFrames = 0U;
    return true;
}

bool SampleEditor::reverse(ImportedSample& sample, std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;

    const std::size_t fb = frameBytes(sample);
    std::array<std::uint8_t, 8U> temporary{};
    if (fb > temporary.size()) {
        error = "Sample frame size is unsupported";
        return false;
    }

    for (std::uint64_t left = 0U, right = sample.totalFrames - 1U; left < right; ++left, --right) {
        std::uint8_t* leftPtr = sample.audioData.data() + static_cast<std::size_t>(left) * fb;
        std::uint8_t* rightPtr = sample.audioData.data() + static_cast<std::size_t>(right) * fb;
        std::copy(leftPtr, leftPtr + fb, temporary.begin());
        std::copy(rightPtr, rightPtr + fb, leftPtr);
        std::copy(temporary.begin(), temporary.begin() + static_cast<std::ptrdiff_t>(fb), rightPtr);
    }

    if (sample.loop.enabled) {
        const std::uint64_t oldStart = sample.loop.startFrame;
        const std::uint64_t oldEnd = sample.loop.endFrame;
        sample.loop.startFrame = sample.totalFrames - oldEnd;
        sample.loop.endFrame = sample.totalFrames - oldStart;
    }
    return true;
}

bool SampleEditor::applyGainDb(ImportedSample& sample,
                               float gainDb,
                               std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (!std::isfinite(gainDb) || gainDb < -120.0F || gainDb > 60.0F) {
        error = "Gain must be finite and between -120 dB and +60 dB";
        return false;
    }

    const float gain = static_cast<float>(std::pow(10.0, static_cast<double>(gainDb) / 20.0));
    const std::size_t bps = bytesPerSample(sample.encoding);
    for (std::size_t offset = 0U; offset < sample.audioData.size(); offset += bps) {
        std::uint8_t* scalar = sample.audioData.data() + offset;
        writeScalar(scalar, sample.encoding, readScalar(scalar, sample.encoding) * gain);
    }
    return true;
}

bool SampleEditor::normalize(ImportedSample& sample,
                             float targetPeakDb,
                             std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (!std::isfinite(targetPeakDb) || targetPeakDb < -120.0F || targetPeakDb > 0.0F) {
        error = "Normalize target must be finite and between -120 dBFS and 0 dBFS";
        return false;
    }

    const float peak = peakLinear(sample);
    if (!(peak > 0.0F)) {
        error = "Cannot normalize a silent sample";
        return false;
    }
    const float target = static_cast<float>(std::pow(10.0, static_cast<double>(targetPeakDb) / 20.0));
    const float gain = target / peak;
    const std::size_t bps = bytesPerSample(sample.encoding);
    for (std::size_t offset = 0U; offset < sample.audioData.size(); offset += bps) {
        std::uint8_t* scalar = sample.audioData.data() + offset;
        writeScalar(scalar, sample.encoding, readScalar(scalar, sample.encoding) * gain);
    }
    return true;
}

bool SampleEditor::fadeIn(ImportedSample& sample,
                          std::uint64_t fadeFrames,
                          std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (fadeFrames == 0U || fadeFrames > sample.totalFrames) {
        error = "Fade-in length must be between 1 and total frames";
        return false;
    }
    multiplyFrames(sample, 0U, fadeFrames, fadeInGain);
    return true;
}

bool SampleEditor::fadeOut(ImportedSample& sample,
                           std::uint64_t fadeFrames,
                           std::string& error) {
    error.clear();
    if (!editable(sample, error)) return false;
    if (fadeFrames == 0U || fadeFrames > sample.totalFrames) {
        error = "Fade-out length must be between 1 and total frames";
        return false;
    }
    multiplyFrames(sample, sample.totalFrames - fadeFrames, fadeFrames, fadeOutGain);
    return true;
}

bool SampleEditor::setRootKey(ImportedSample& sample,
                              std::uint8_t rootKey,
                              std::string& error) noexcept {
    error.clear();
    if (rootKey > 127U) {
        error = "Root key must be 0..127";
        return false;
    }
    sample.rootKey = rootKey;
    return true;
}

bool SampleEditor::setFineTuneCents(ImportedSample& sample,
                                    float cents,
                                    std::string& error) noexcept {
    error.clear();
    if (!std::isfinite(cents) || cents < -100.0F || cents > 100.0F) {
        error = "Fine tune must be finite and between -100 and +100 cents";
        return false;
    }
    sample.fineTuneCents = cents;
    return true;
}

float SampleEditor::peakLinear(const ImportedSample& sample) noexcept {
    if (!sample.valid()) return 0.0F;
    const std::size_t bps = bytesPerSample(sample.encoding);
    if (bps == 0U) return 0.0F;
    float peak = 0.0F;
    for (std::size_t offset = 0U; offset < sample.audioData.size(); offset += bps) {
        peak = std::max(peak, std::fabs(readScalar(sample.audioData.data() + offset, sample.encoding)));
    }
    return peak;
}

std::uint64_t SampleEditor::nearestZeroCrossing(const ImportedSample& sample,
                                                std::uint64_t frame,
                                                std::uint64_t searchRadiusFrames) noexcept {
    if (!sample.valid() || sample.totalFrames < 2U) return 0U;
    const std::uint64_t target = std::min(frame, sample.totalFrames - 1U);
    const std::uint64_t first = target > searchRadiusFrames ? target - searchRadiusFrames : 1U;
    const std::uint64_t last = std::min(sample.totalFrames - 1U, target + searchRadiusFrames);

    std::uint64_t best = target;
    std::uint64_t bestDistance = std::numeric_limits<std::uint64_t>::max();
    float bestMagnitude = std::numeric_limits<float>::max();

    for (std::uint64_t current = std::max<std::uint64_t>(1U, first); current <= last; ++current) {
        const float previous = frameValue(sample, current - 1U);
        const float value = frameValue(sample, current);
        const bool crossing = (previous <= 0.0F && value >= 0.0F) || (previous >= 0.0F && value <= 0.0F);
        if (!crossing) continue;
        const std::uint64_t distance = current > target ? current - target : target - current;
        const float magnitude = std::fabs(previous) + std::fabs(value);
        if (distance < bestDistance || (distance == bestDistance && magnitude < bestMagnitude)) {
            best = current;
            bestDistance = distance;
            bestMagnitude = magnitude;
        }
    }
    return best;
}

bool SampleEditor::buildWaveform(const ImportedSample& sample,
                                 std::size_t pointCount,
                                 std::vector<WaveformPoint>& points,
                                 std::string& error) {
    error.clear();
    points.clear();
    if (!editable(sample, error)) return false;
    if (pointCount == 0U) {
        error = "Waveform point count must be greater than zero";
        return false;
    }

    const std::size_t count = static_cast<std::size_t>(std::min<std::uint64_t>(sample.totalFrames, static_cast<std::uint64_t>(pointCount)));
    points.resize(count);
    for (std::size_t point = 0U; point < count; ++point) {
        const std::uint64_t begin = static_cast<std::uint64_t>((static_cast<long double>(point) * sample.totalFrames) / count);
        std::uint64_t end = static_cast<std::uint64_t>((static_cast<long double>(point + 1U) * sample.totalFrames) / count);
        if (end <= begin) end = begin + 1U;
        end = std::min(end, sample.totalFrames);

        float minimum = 1.0F;
        float maximum = -1.0F;
        const std::size_t bps = bytesPerSample(sample.encoding);
        const std::size_t fb = frameBytes(sample);
        for (std::uint64_t frame = begin; frame < end; ++frame) {
            const std::size_t frameOffset = static_cast<std::size_t>(frame) * fb;
            for (std::uint16_t channel = 0U; channel < sample.channels; ++channel) {
                const float value = readScalar(sample.audioData.data() + frameOffset + static_cast<std::size_t>(channel) * bps,
                                               sample.encoding);
                minimum = std::min(minimum, value);
                maximum = std::max(maximum, value);
            }
        }
        points[point] = {minimum, maximum};
    }
    return true;
}

} // namespace silveton::manager
