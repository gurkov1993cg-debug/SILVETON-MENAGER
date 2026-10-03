#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace silveton::manager {

struct DeleteImpact {
    std::size_t samplesRemoved{0U};
    std::size_t zonesRemoved{0U};
    std::size_t multisamplesRemoved{0U};
    std::size_t layersRemoved{0U};
    std::size_t soundsRemoved{0U};
};

class ObjectManager final {
public:
    static bool renameSample(BankProject& project, std::size_t sampleIndex, const std::string& name, std::string& error);
    static bool duplicateSample(BankProject& project, std::size_t sampleIndex, std::size_t& createdIndex, std::string& error);
    static bool deleteSampleCascade(BankProject& project, std::size_t sampleIndex, DeleteImpact& impact, std::string& error);

    static bool renameMultisample(BankProject& project, std::size_t multisampleIndex, const std::string& name, std::string& error);
    static bool duplicateMultisample(BankProject& project, std::size_t multisampleIndex, std::size_t& createdIndex, std::string& error);
    static bool deleteMultisampleCascade(BankProject& project, std::size_t multisampleIndex, DeleteImpact& impact, std::string& error);

    static bool renameSound(BankProject& project, std::size_t soundIndex, const std::string& name, std::string& error);
    static bool createSoundFromMultisample(BankProject& project, std::size_t multisampleIndex, const std::string& name, std::size_t& createdIndex, std::string& error);
    static bool duplicateSound(BankProject& project, std::size_t soundIndex, std::size_t& createdIndex, std::string& error);
    static bool deleteSound(BankProject& project, std::size_t soundIndex, DeleteImpact& impact, std::string& error);

private:
    static bool validName(const std::string& name) noexcept;
    static std::string uniqueName(const std::string& base, const BankProject& project, int kind);
    static bool assignNextFreeSoundAddress(BankProject& project, SoundDefinition& sound, std::string& error);
};

} // namespace silveton::manager
