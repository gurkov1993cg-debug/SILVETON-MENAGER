#pragma once

#include "silveton/manager/ManagerTypes.h"

#include <cstddef>
#include <cstdint>

namespace silveton::manager {

[[nodiscard]] std::uint64_t fnv1a64(const void* data, std::size_t size, std::uint64_t seed = 14695981039346656037ULL) noexcept;
[[nodiscard]] std::uint64_t hashSampleAudio(const ImportedSample& sample) noexcept;

} // namespace silveton::manager
