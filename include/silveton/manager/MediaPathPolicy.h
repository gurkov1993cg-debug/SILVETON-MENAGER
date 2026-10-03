#pragma once

#include <string>

namespace silveton::manager {

enum class MediaEntryKind {
    Unsupported = 0,
    Directory,
    SilvetonBank,
    ImportableSamplerFile
};

class MediaPathPolicy final {
public:
    [[nodiscard]] static MediaEntryKind classify(const std::string& path, bool isDirectory) noexcept;
    [[nodiscard]] static bool isImportable(const std::string& path) noexcept;
    [[nodiscard]] static bool isSilvetonBank(const std::string& path) noexcept;
    [[nodiscard]] static std::string normalizeAbsolutePath(const std::string& path);
    [[nodiscard]] static bool isInsideRoot(const std::string& root, const std::string& candidate);
};

} // namespace silveton::manager
