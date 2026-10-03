#pragma once

#include "silveton/manager/ManagerTypes.h"
#include "silveton/manager/SvBankFormat.h"

#include <string>
#include <vector>

namespace silveton::manager {

struct SvReadResult {
    BankProject project{};
    SvBankHeader header{};
    std::string error;
    [[nodiscard]] bool ok() const noexcept { return error.empty(); }
};

class SvBankReader {
public:
    [[nodiscard]] static SvReadResult read(const std::vector<std::uint8_t>& bytes, bool verifyIntegrity = true);
    [[nodiscard]] static SvReadResult readFile(const std::string& path, bool verifyIntegrity = true);
};

} // namespace silveton::manager
