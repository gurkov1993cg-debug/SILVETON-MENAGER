#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <string>
#include <vector>

namespace silveton::manager {

struct KorgSampleResult {
    ImportedSample sample{};
    std::string error;
    [[nodiscard]] bool ok() const noexcept { return error.empty() && sample.valid(); }
};

struct KorgImportResult {
    ImportedMultisample multisample{};
    std::vector<ImportedSample> samples;
    std::string error;
    std::vector<std::string> warnings;
    [[nodiscard]] bool ok() const noexcept { return error.empty() && !multisample.zones.empty(); }
};

struct KorgCollectionResult {
    std::vector<ImportedMultisample> multisamples;
    std::vector<ImportedSample> samples;
    std::string error;
    std::vector<std::string> warnings;
    [[nodiscard]] bool ok() const noexcept { return error.empty() && !multisamples.empty(); }
};

class KorgImporter {
public:
    [[nodiscard]] static KorgSampleResult loadKsf(const std::string& path);
    [[nodiscard]] static KorgImportResult loadKmp(const std::string& path);
    [[nodiscard]] static std::vector<std::string> parseKsc(const std::string& path, std::string& error);
    [[nodiscard]] static KorgCollectionResult loadKsc(const std::string& path);

    // Real SALEAS-GRK RLP1 data uses raw value 64 for centred regions.
    // The raw value is always preserved in ImportedZone::sourcePanRaw.
    [[nodiscard]] static float normalizedPan(std::uint8_t raw) noexcept;
};

} // namespace silveton::manager
