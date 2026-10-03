#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace silveton::manager {

enum class AudioEncoding : std::uint8_t {
    Pcm16LE = 1,
    Pcm24LE = 2,
    Float32LE = 3
};

struct LoopRegion {
    bool enabled{false};
    std::uint64_t startFrame{0};
    std::uint64_t endFrame{0};
    std::uint32_t crossfadeFrames{0};
};

struct ImportedSample {
    std::string name;
    std::string sourcePath;
    std::string sourceIdentity;
    std::uint32_t sampleRate{0};
    std::uint16_t channels{0};
    AudioEncoding encoding{AudioEncoding::Pcm16LE};
    std::uint8_t bitsPerSample{0};
    std::uint8_t rootKey{60};
    float fineTuneCents{0.0F};
    std::uint64_t totalFrames{0};
    LoopRegion loop{};
    std::vector<std::uint8_t> audioData;

    [[nodiscard]] bool valid() const noexcept {
        if (sampleRate == 0U || channels == 0U || channels > 2U || totalFrames == 0U) return false;
        std::uint32_t bytesPerSample = 0U;
        switch (encoding) {
            case AudioEncoding::Pcm16LE: bytesPerSample = 2U; break;
            case AudioEncoding::Pcm24LE: bytesPerSample = 3U; break;
            case AudioEncoding::Float32LE: bytesPerSample = 4U; break;
        }
        const std::uint64_t expected = totalFrames * static_cast<std::uint64_t>(channels) * bytesPerSample;
        return expected == audioData.size();
    }
};

struct ImportedZone {
    std::uint32_t sampleIndex{0};
    std::uint8_t keyLow{0};
    std::uint8_t keyHigh{127};
    std::uint8_t velocityLow{1};
    std::uint8_t velocityHigh{127};
    std::uint8_t rootKey{60};
    std::int8_t transposeSemitones{0};
    float tuneCents{0.0F};
    float gainDb{0.0F};
    float pan{0.0F};
    bool oneShot{false};
    bool reverse{false};
    bool nonTranspose{false};

    // Original Korg RLP1 values are retained exactly. These are source
    // metadata and are not replaced by guessed DSP transfer functions.
    std::uint8_t sourcePanRaw{64};
    std::int8_t sourceLevelRaw{0};
    std::int8_t sourceFilterRaw{0};
};

struct ImportedMultisample {
    std::string name;
    std::string sourceIdentity;
    std::vector<ImportedZone> zones;
};

struct SoundLayer {
    std::uint32_t multisampleIndex{0};
    bool enabled{true};
    std::uint8_t keyLow{0};
    std::uint8_t keyHigh{127};
    std::uint8_t velocityLow{1};
    std::uint8_t velocityHigh{127};
    std::int8_t transposeSemitones{0};
    float tuneCents{0.0F};
    float levelDb{0.0F};
    float pan{0.0F};
};

struct SoundDefinition {
    std::string name;
    std::uint16_t bank{0};
    std::uint16_t page{0};
    std::uint16_t slot{0};
    std::uint16_t category{0};
    std::vector<SoundLayer> layers;
};

struct BankProject {
    std::string name{"SILVETON BANK"};
    std::vector<ImportedSample> samples;
    std::vector<ImportedMultisample> multisamples;
    std::vector<SoundDefinition> sounds;
};

} // namespace silveton::manager
