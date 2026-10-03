#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <string>

namespace silveton::manager {

enum class ExportAudioFormat {
    Wav = 0,
    Aiff = 1
};

class AudioExporter final {
public:
    static bool writeFile(const std::string& path,
                          const ImportedSample& sample,
                          ExportAudioFormat format,
                          std::string& error);
};

} // namespace silveton::manager
