#include "silveton/manager/SampleConverter.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <limits>
#include <vector>

namespace silveton::manager {
namespace {

constexpr double kPi = 3.14159265358979323846264338327950288;
constexpr int kSincRadius = 32;

std::uint32_t bytesPerSample(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 2U;
        case AudioEncoding::Pcm24LE: return 3U;
        case AudioEncoding::Float32LE: return 4U;
    }
    return 0U;
}

double decodeSample(const std::uint8_t* p, AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: {
            const std::uint16_t u = static_cast<std::uint16_t>(p[0]) |
                                    (static_cast<std::uint16_t>(p[1]) << 8U);
            const std::int16_t s = static_cast<std::int16_t>(u);
            return static_cast<double>(s) / 32768.0;
        }
        case AudioEncoding::Pcm24LE: {
            std::int32_t v = static_cast<std::int32_t>(p[0]) |
                             (static_cast<std::int32_t>(p[1]) << 8U) |
                             (static_cast<std::int32_t>(p[2]) << 16U);
            if ((v & 0x00800000) != 0) v |= static_cast<std::int32_t>(0xFF000000U);
            return static_cast<double>(v) / 8388608.0;
        }
        case AudioEncoding::Float32LE: {
            std::uint32_t bits = static_cast<std::uint32_t>(p[0]) |
                                 (static_cast<std::uint32_t>(p[1]) << 8U) |
                                 (static_cast<std::uint32_t>(p[2]) << 16U) |
                                 (static_cast<std::uint32_t>(p[3]) << 24U);
            float value = 0.0F;
            std::memcpy(&value, &bits, sizeof(value));
            return std::isfinite(value) ? static_cast<double>(value) : 0.0;
        }
    }
    return 0.0;
}

std::vector<double> decodeInterleaved(const ImportedSample& sample) {
    const std::uint32_t bps = bytesPerSample(sample.encoding);
    const std::size_t count = static_cast<std::size_t>(sample.totalFrames) * static_cast<std::size_t>(sample.channels);
    std::vector<double> decoded(count, 0.0);
    for (std::size_t i = 0U; i < count; ++i) {
        decoded[i] = decodeSample(sample.audioData.data() + (i * static_cast<std::size_t>(bps)), sample.encoding);
    }
    return decoded;
}

std::vector<double> convertChannels(const std::vector<double>& input,
                                    std::uint64_t frames,
                                    std::uint16_t sourceChannels,
                                    std::uint16_t targetChannels) {
    if (sourceChannels == targetChannels) return input;
    std::vector<double> output(static_cast<std::size_t>(frames) * static_cast<std::size_t>(targetChannels), 0.0);
    if (sourceChannels == 1U && targetChannels == 2U) {
        for (std::uint64_t frame = 0U; frame < frames; ++frame) {
            const double value = input[static_cast<std::size_t>(frame)];
            const std::size_t out = static_cast<std::size_t>(frame) * 2U;
            output[out] = value;
            output[out + 1U] = value;
        }
    } else if (sourceChannels == 2U && targetChannels == 1U) {
        for (std::uint64_t frame = 0U; frame < frames; ++frame) {
            const std::size_t in = static_cast<std::size_t>(frame) * 2U;
            output[static_cast<std::size_t>(frame)] = 0.5 * (input[in] + input[in + 1U]);
        }
    }
    return output;
}

double sinc(double x) noexcept {
    if (std::abs(x) < 1.0e-12) return 1.0;
    const double pix = kPi * x;
    return std::sin(pix) / pix;
}

double blackmanWindow(double normalizedDistance) noexcept {
    if (normalizedDistance >= 1.0) return 0.0;
    return 0.42 + 0.5 * std::cos(kPi * normalizedDistance) + 0.08 * std::cos(2.0 * kPi * normalizedDistance);
}

std::vector<double> resample(const std::vector<double>& input,
                             std::uint64_t sourceFrames,
                             std::uint16_t channels,
                             std::uint32_t sourceRate,
                             std::uint32_t targetRate,
                             std::uint64_t targetFrames) {
    if (sourceRate == targetRate || sourceFrames == targetFrames) return input;

    std::vector<double> output(static_cast<std::size_t>(targetFrames) * static_cast<std::size_t>(channels), 0.0);
    const double sourcePerTarget = static_cast<double>(sourceRate) / static_cast<double>(targetRate);
    const double rateRatio = static_cast<double>(targetRate) / static_cast<double>(sourceRate);
    const double cutoff = std::min(1.0, rateRatio) * 0.97;

    for (std::uint64_t outFrame = 0U; outFrame < targetFrames; ++outFrame) {
        const double sourcePosition = static_cast<double>(outFrame) * sourcePerTarget;
        const std::int64_t center = static_cast<std::int64_t>(std::floor(sourcePosition));
        for (std::uint16_t channel = 0U; channel < channels; ++channel) {
            double sum = 0.0;
            double weightSum = 0.0;
            for (int tap = -kSincRadius + 1; tap <= kSincRadius; ++tap) {
                const std::int64_t sourceFrame = center + static_cast<std::int64_t>(tap);
                if (sourceFrame < 0 || sourceFrame >= static_cast<std::int64_t>(sourceFrames)) continue;
                const double distance = sourcePosition - static_cast<double>(sourceFrame);
                const double normalizedDistance = std::abs(distance) / static_cast<double>(kSincRadius);
                const double weight = cutoff * sinc(cutoff * distance) * blackmanWindow(normalizedDistance);
                const std::size_t sourceIndex = static_cast<std::size_t>(sourceFrame) * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel);
                sum += input[sourceIndex] * weight;
                weightSum += weight;
            }
            const std::size_t outputIndex = static_cast<std::size_t>(outFrame) * static_cast<std::size_t>(channels) + static_cast<std::size_t>(channel);
            output[outputIndex] = std::abs(weightSum) > 1.0e-15 ? (sum / weightSum) : 0.0;
        }
    }
    return output;
}

struct DitherGenerator {
    std::uint32_t state{0xA5C31E27U};

    std::uint32_t next() noexcept {
        state ^= state << 13U;
        state ^= state >> 17U;
        state ^= state << 5U;
        return state;
    }

    double uniform() noexcept {
        return static_cast<double>(next()) / static_cast<double>(std::numeric_limits<std::uint32_t>::max());
    }

    double tpdf(double lsb) noexcept {
        return (uniform() - uniform()) * lsb;
    }
};

void append16(std::vector<std::uint8_t>& bytes, double value, bool dither, DitherGenerator& rng) {
    if (dither) value += rng.tpdf(1.0 / 32768.0);
    value = std::max(-1.0, std::min(value, 0.999969482421875));
    const long quantized = std::lround(value * 32768.0);
    const auto sample = static_cast<std::int16_t>(std::max<long>(-32768L, std::min<long>(32767L, quantized)));
    const auto u = static_cast<std::uint16_t>(sample);
    bytes.push_back(static_cast<std::uint8_t>(u & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((u >> 8U) & 0xFFU));
}

void append24(std::vector<std::uint8_t>& bytes, double value, bool dither, DitherGenerator& rng) {
    if (dither) value += rng.tpdf(1.0 / 8388608.0);
    value = std::max(-1.0, std::min(value, 0.9999998807907104));
    const long long quantized = std::llround(value * 8388608.0);
    const auto sample = static_cast<std::int32_t>(std::max<long long>(-8388608LL, std::min<long long>(8388607LL, quantized)));
    const auto u = static_cast<std::uint32_t>(sample);
    bytes.push_back(static_cast<std::uint8_t>(u & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((u >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((u >> 16U) & 0xFFU));
}

void appendFloat32(std::vector<std::uint8_t>& bytes, double value) {
    const float sample = static_cast<float>(std::max(-1.0, std::min(value, 1.0)));
    std::uint32_t bits = 0U;
    std::memcpy(&bits, &sample, sizeof(bits));
    bytes.push_back(static_cast<std::uint8_t>(bits & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((bits >> 8U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((bits >> 16U) & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((bits >> 24U) & 0xFFU));
}

std::vector<std::uint8_t> encode(const std::vector<double>& values, AudioEncoding encoding, bool dither) {
    const std::uint32_t bps = bytesPerSample(encoding);
    std::vector<std::uint8_t> bytes;
    bytes.reserve(values.size() * static_cast<std::size_t>(bps));
    DitherGenerator rng{};
    for (double value : values) {
        switch (encoding) {
            case AudioEncoding::Pcm16LE: append16(bytes, value, dither, rng); break;
            case AudioEncoding::Pcm24LE: append24(bytes, value, dither, rng); break;
            case AudioEncoding::Float32LE: appendFloat32(bytes, value); break;
        }
    }
    return bytes;
}

std::uint8_t bitDepth(AudioEncoding encoding) noexcept {
    switch (encoding) {
        case AudioEncoding::Pcm16LE: return 16U;
        case AudioEncoding::Pcm24LE: return 24U;
        case AudioEncoding::Float32LE: return 32U;
    }
    return 0U;
}

std::uint64_t scaleFrame(std::uint64_t frame, std::uint32_t sourceRate, std::uint32_t targetRate) noexcept {
    const long double scaled = static_cast<long double>(frame) * static_cast<long double>(targetRate) / static_cast<long double>(sourceRate);
    if (scaled <= 0.0L) return 0U;
    return static_cast<std::uint64_t>(std::llround(scaled));
}

} // namespace

bool SampleConverter::convert(const ImportedSample& source,
                              const SampleConversionOptions& options,
                              ImportedSample& destination,
                              std::string& error) {
    if (!source.valid()) {
        error = "The source sample is invalid.";
        return false;
    }

    const std::uint32_t targetRate = options.sampleRate == 0U ? source.sampleRate : options.sampleRate;
    const std::uint16_t targetChannels = options.channels == 0U ? source.channels : options.channels;
    const AudioEncoding targetEncoding = options.changeEncoding ? options.encoding : source.encoding;

    if (targetRate < 8000U || targetRate > 384000U) {
        error = "Target sample rate must be between 8000 and 384000 Hz.";
        return false;
    }
    if (targetChannels != 1U && targetChannels != 2U) {
        error = "Target channel count must be mono or stereo.";
        return false;
    }
    if (bytesPerSample(targetEncoding) == 0U) {
        error = "Unsupported target sample encoding.";
        return false;
    }

    const long double exactFrames = static_cast<long double>(source.totalFrames) *
                                    static_cast<long double>(targetRate) /
                                    static_cast<long double>(source.sampleRate);
    const std::uint64_t targetFrames = std::max<std::uint64_t>(1U, static_cast<std::uint64_t>(std::llround(exactFrames)));

    std::vector<double> decoded = decodeInterleaved(source);
    std::vector<double> channelConverted = convertChannels(decoded, source.totalFrames, source.channels, targetChannels);
    std::vector<double> resampled = resample(channelConverted, source.totalFrames, targetChannels, source.sampleRate, targetRate, targetFrames);

    ImportedSample converted = source;
    converted.sampleRate = targetRate;
    converted.channels = targetChannels;
    converted.encoding = targetEncoding;
    converted.bitsPerSample = bitDepth(targetEncoding);
    converted.totalFrames = targetFrames;
    converted.audioData = encode(resampled, targetEncoding, options.dither && targetEncoding != AudioEncoding::Float32LE);

    if (source.loop.enabled) {
        converted.loop.startFrame = std::min(scaleFrame(source.loop.startFrame, source.sampleRate, targetRate), targetFrames - 1U);
        converted.loop.endFrame = std::min(scaleFrame(source.loop.endFrame, source.sampleRate, targetRate), targetFrames);
        converted.loop.crossfadeFrames = static_cast<std::uint32_t>(std::min<std::uint64_t>(
            scaleFrame(source.loop.crossfadeFrames, source.sampleRate, targetRate),
            static_cast<std::uint64_t>(std::numeric_limits<std::uint32_t>::max())));
        if (converted.loop.startFrame >= converted.loop.endFrame) {
            converted.loop = LoopRegion{};
        }
    }

    if (!converted.valid()) {
        error = "Converted sample failed internal validation.";
        return false;
    }

    destination = std::move(converted);
    error.clear();
    return true;
}

} // namespace silveton::manager
