#include "silveton/manager/SampleHash.h"

#include <array>

namespace silveton::manager {
namespace {

void mixU64(std::uint64_t& hash, std::uint64_t value) noexcept {
    std::array<std::uint8_t, 8> bytes{};
    for (std::size_t i = 0; i < bytes.size(); ++i) {
        bytes[i] = static_cast<std::uint8_t>((value >> (i * 8U)) & 0xFFU);
    }
    hash = fnv1a64(bytes.data(), bytes.size(), hash);
}

} // namespace

std::uint64_t fnv1a64(const void* data, std::size_t size, std::uint64_t seed) noexcept {
    const auto* bytes = static_cast<const std::uint8_t*>(data);
    std::uint64_t hash = seed;
    for (std::size_t i = 0; i < size; ++i) {
        hash ^= bytes[i];
        hash *= 1099511628211ULL;
    }
    return hash;
}

std::uint64_t hashSampleAudio(const ImportedSample& sample) noexcept {
    std::uint64_t hash = 14695981039346656037ULL;
    mixU64(hash, sample.sampleRate);
    mixU64(hash, sample.channels);
    mixU64(hash, static_cast<std::uint8_t>(sample.encoding));
    mixU64(hash, sample.bitsPerSample);
    mixU64(hash, sample.totalFrames);
    if (!sample.audioData.empty()) hash = fnv1a64(sample.audioData.data(), sample.audioData.size(), hash);
    return hash;
}

} // namespace silveton::manager
