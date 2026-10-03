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
