#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <string>

namespace silveton::manager {

struct AudioLoadResult {
    ImportedSample sample{};
    std::string error;
    [[nodiscard]] bool ok() const noexcept { return error.empty() && sample.valid(); }
};

class AudioFileLoader {
public:
    [[nodiscard]] static AudioLoadResult load(const std::string& path);
    [[nodiscard]] static AudioLoadResult loadWav(const std::string& path);
    [[nodiscard]] static AudioLoadResult loadAiff(const std::string& path);
};

} // namespace silveton::manager
