#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace silveton::manager {

constexpr std::uint16_t kSvBankVersionMajor = 1U;
constexpr std::uint16_t kSvBankVersionMinor = 0U;
constexpr std::uint32_t kSvBankHeaderSize = 256U;
constexpr std::size_t kSvSectionCount = 7U;
constexpr std::array<std::uint8_t, 8> kSvBankMagic{{'S','I','L','V','S','V','1',0}};

enum class SvSection : std::size_t {
    Sounds = 0,
    SoundLayers = 1,
    Multisamples = 2,
    Samples = 3,
    Zones = 4,
    Strings = 5,
    Audio = 6
};

struct SvSectionDesc {
    std::uint64_t offset{0};
    std::uint64_t size{0};
};

struct SvBankHeader {
    std::uint16_t versionMajor{kSvBankVersionMajor};
    std::uint16_t versionMinor{kSvBankVersionMinor};
    std::uint32_t flags{0};
    std::uint64_t fileSize{0};
    std::uint32_t bankNameOffset{0};
    std::uint32_t soundCount{0};
    std::uint32_t soundLayerCount{0};
    std::uint32_t multisampleCount{0};
    std::uint32_t sampleCount{0};
    std::uint32_t zoneCount{0};
    std::array<SvSectionDesc, kSvSectionCount> sections{};
    std::array<std::uint8_t, 32> payloadSha256{};
};

struct SvSoundRecord {
    std::uint32_t nameOffset{0};
    std::uint32_t firstLayer{0};
    std::uint32_t layerCount{0};
    std::uint16_t bank{0};
    std::uint16_t page{0};
    std::uint16_t slot{0};
    std::uint16_t category{0};
};

struct SvSoundLayerRecord {
    std::uint32_t multisampleIndex{0};
    std::uint8_t enabled{1};
    std::uint8_t keyLow{0};
    std::uint8_t keyHigh{127};
    std::uint8_t velocityLow{1};
    std::uint8_t velocityHigh{127};
    std::int8_t transposeSemitones{0};
    float tuneCents{0.0F};
    float levelDb{0.0F};
    float pan{0.0F};
};

struct SvMultisampleRecord {
    std::uint32_t nameOffset{0};
    std::uint32_t sourceIdentityOffset{0};
    std::uint32_t firstZone{0};
    std::uint32_t zoneCount{0};
};

struct SvSampleRecord {
    std::uint32_t nameOffset{0};
    std::uint32_t sourceIdentityOffset{0};
    std::uint32_t sampleRate{0};
    std::uint16_t channels{0};
    std::uint8_t encoding{0};
    std::uint8_t bitsPerSample{0};
    std::uint8_t rootKey{60};
    std::uint8_t loopEnabled{0};
    float fineTuneCents{0.0F};
    std::uint64_t totalFrames{0};
    std::uint64_t loopStart{0};
    std::uint64_t loopEnd{0};
    std::uint32_t loopCrossfadeFrames{0};
    std::uint64_t audioOffset{0};
    std::uint64_t audioSize{0};
    std::uint64_t audioHash{0};
};

struct SvZoneRecord {
    std::uint32_t sampleIndex{0};
    std::uint8_t keyLow{0};
    std::uint8_t keyHigh{127};
    std::uint8_t velocityLow{1};
    std::uint8_t velocityHigh{127};
    std::uint8_t rootKey{60};
    std::int8_t transposeSemitones{0};
    std::uint8_t flags{0};
    std::uint8_t sourcePanRaw{64};
    std::int8_t sourceLevelRaw{0};
    std::int8_t sourceFilterRaw{0};
    float tuneCents{0.0F};
    float gainDb{0.0F};
    float pan{0.0F};
};

constexpr std::size_t kSvSoundRecordSize = 32U;
constexpr std::size_t kSvSoundLayerRecordSize = 32U;
constexpr std::size_t kSvMultisampleRecordSize = 24U;
constexpr std::size_t kSvSampleRecordSize = 96U;
constexpr std::size_t kSvZoneRecordSize = 32U;

[[nodiscard]] std::vector<std::uint8_t> serializeHeader(const SvBankHeader& header);
[[nodiscard]] bool deserializeHeader(const std::uint8_t* data, std::size_t size, SvBankHeader& header, std::string& error);

void appendSoundRecord(std::vector<std::uint8_t>& out, const SvSoundRecord& record);
void appendSoundLayerRecord(std::vector<std::uint8_t>& out, const SvSoundLayerRecord& record);
void appendMultisampleRecord(std::vector<std::uint8_t>& out, const SvMultisampleRecord& record);
void appendSampleRecord(std::vector<std::uint8_t>& out, const SvSampleRecord& record);
void appendZoneRecord(std::vector<std::uint8_t>& out, const SvZoneRecord& record);

[[nodiscard]] bool readSoundRecord(const std::uint8_t* data, std::size_t size, SvSoundRecord& record);
[[nodiscard]] bool readSoundLayerRecord(const std::uint8_t* data, std::size_t size, SvSoundLayerRecord& record);
[[nodiscard]] bool readMultisampleRecord(const std::uint8_t* data, std::size_t size, SvMultisampleRecord& record);
[[nodiscard]] bool readSampleRecord(const std::uint8_t* data, std::size_t size, SvSampleRecord& record);
[[nodiscard]] bool readZoneRecord(const std::uint8_t* data, std::size_t size, SvZoneRecord& record);

[[nodiscard]] std::array<std::uint8_t, 32> sha256(const std::uint8_t* data, std::size_t size) noexcept;

} // namespace silveton::manager
