#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstddef>
#include <cstdint>
#include <string>

namespace silveton::manager {

class SoundEditor final {
public:
    static bool addLayer(BankProject& project,
                         std::size_t soundIndex,
                         std::uint32_t multisampleIndex,
                         std::string& error);

    static bool removeLayer(BankProject& project,
                            std::size_t soundIndex,
                            std::size_t layerIndex,
                            std::string& error);

    static bool updateLayer(BankProject& project,
                            std::size_t soundIndex,
                            std::size_t layerIndex,
                            std::uint32_t multisampleIndex,
                            bool enabled,
                            std::uint8_t keyLow,
                            std::uint8_t keyHigh,
                            std::uint8_t velocityLow,
                            std::uint8_t velocityHigh,
                            std::int8_t transposeSemitones,
                            float tuneCents,
                            float levelDb,
                            float pan,
                            std::string& error);

    [[nodiscard]] static bool validateLayer(const BankProject& project,
                                            const SoundLayer& layer,
                                            std::string& error) noexcept;
};

} // namespace silveton::manager
