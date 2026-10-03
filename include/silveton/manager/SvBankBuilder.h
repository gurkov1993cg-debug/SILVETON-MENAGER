#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstdint>
#include <string>
#include <vector>

namespace silveton::manager {

struct SvBuildStats {
    std::uint32_t soundCount{0};
    std::uint32_t multisampleCount{0};
    std::uint32_t sampleCount{0};
    std::uint32_t zoneCount{0};
    std::uint32_t uniqueAudioPayloadCount{0};
    std::uint64_t audioBytesBeforeDedup{0};
    std::uint64_t audioBytesAfterDedup{0};
};

struct SvBuildResult {
    std::vector<std::uint8_t> bytes;
    SvBuildStats stats{};
    std::string error;
    [[nodiscard]] bool ok() const noexcept { return error.empty() && !bytes.empty(); }
};

class SvBankBuilder {
public:
    [[nodiscard]] static SvBuildResult build(const BankProject& project);
    [[nodiscard]] static bool writeAtomic(const std::string& path, const BankProject& project, SvBuildStats& stats, std::string& error);
};

} // namespace silveton::manager
