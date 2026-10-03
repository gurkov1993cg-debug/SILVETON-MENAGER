#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstdint>
#include <string>

namespace silveton::manager {

struct SampleConversionOptions {
    std::uint32_t sampleRate{0U};      // 0 = keep source rate
    std::uint16_t channels{0U};        // 0 = keep source channel count
    AudioEncoding encoding{AudioEncoding::Pcm24LE};
    bool changeEncoding{false};
    bool dither{true};
};

class SampleConverter final {
public:
    static bool convert(const ImportedSample& source,
                        const SampleConversionOptions& options,
                        ImportedSample& destination,
                        std::string& error);
};

} // namespace silveton::manager
