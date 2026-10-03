#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace silveton::manager {

struct WaveformPoint {
    float minimum{0.0F};
    float maximum{0.0F};
};

struct SampleRegion {
    std::uint32_t sampleRate{0U};
    std::uint16_t channels{0U};
    AudioEncoding encoding{AudioEncoding::Pcm16LE};
    std::uint8_t bitsPerSample{0U};
    std::uint64_t frameCount{0U};
    std::vector<std::uint8_t> audioData;

    [[nodiscard]] bool empty() const noexcept { return frameCount == 0U || audioData.empty(); }
};

class SampleEditor final {
public:
    static bool trim(ImportedSample& sample,
                     std::uint64_t startFrame,
                     std::uint64_t endFrame,
                     std::string& error);

    static bool setLoop(ImportedSample& sample,
                        bool enabled,
                        std::uint64_t startFrame,
                        std::uint64_t endFrame,
                        std::uint32_t crossfadeFrames,
                        std::string& error);

    static bool applyLoopCrossfade(ImportedSample& sample,
                                   std::uint32_t crossfadeFrames,
                                   std::string& error);

    static bool reverse(ImportedSample& sample, std::string& error);

    static bool applyGainDb(ImportedSample& sample,
                            float gainDb,
                            std::string& error);

    static bool normalize(ImportedSample& sample,
                          float targetPeakDb,
                          std::string& error);

    static bool fadeIn(ImportedSample& sample,
                       std::uint64_t fadeFrames,
                       std::string& error);

    static bool fadeOut(ImportedSample& sample,
                        std::uint64_t fadeFrames,
                        std::string& error);

    static bool copyRegion(const ImportedSample& sample,
                           std::uint64_t startFrame,
                           std::uint64_t endFrame,
                           SampleRegion& region,
                           std::string& error);

    static bool deleteRegion(ImportedSample& sample,
                             std::uint64_t startFrame,
                             std::uint64_t endFrame,
                             std::string& error);

    static bool silenceRegion(ImportedSample& sample,
                              std::uint64_t startFrame,
                              std::uint64_t endFrame,
                              std::string& error);

    static bool insertRegion(ImportedSample& sample,
                             std::uint64_t atFrame,
                             const SampleRegion& region,
                             std::string& error);

    static bool reverseRegion(ImportedSample& sample,
                              std::uint64_t startFrame,
                              std::uint64_t endFrame,
                              std::string& error);

    static bool applyGainDbRegion(ImportedSample& sample,
                                  std::uint64_t startFrame,
                                  std::uint64_t endFrame,
                                  float gainDb,
                                  std::string& error);

    static bool normalizeRegion(ImportedSample& sample,
                                std::uint64_t startFrame,
                                std::uint64_t endFrame,
                                float targetPeakDb,
                                std::string& error);

    static bool fadeInRegion(ImportedSample& sample,
                             std::uint64_t startFrame,
                             std::uint64_t endFrame,
                             std::string& error);

    static bool fadeOutRegion(ImportedSample& sample,
                              std::uint64_t startFrame,
                              std::uint64_t endFrame,
                              std::string& error);

    static bool setRootKey(ImportedSample& sample,
                           std::uint8_t rootKey,
                           std::string& error) noexcept;

    static bool setFineTuneCents(ImportedSample& sample,
                                 float cents,
                                 std::string& error) noexcept;

    [[nodiscard]] static float peakLinear(const ImportedSample& sample) noexcept;

    [[nodiscard]] static std::uint64_t nearestZeroCrossing(const ImportedSample& sample,
                                                           std::uint64_t frame,
                                                           std::uint64_t searchRadiusFrames) noexcept;

    static bool buildWaveform(const ImportedSample& sample,
                              std::size_t pointCount,
                              std::vector<WaveformPoint>& points,
                              std::string& error);
};

} // namespace silveton::manager
