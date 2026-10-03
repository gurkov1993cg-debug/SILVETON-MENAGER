#include "silveton/manager/MediaPathPolicy.h"

#include <algorithm>
#include <cctype>
#include <string>
#include <vector>

namespace silveton::manager {
namespace {

std::string lowerExtension(const std::string& path) {
    const std::size_t slash = path.find_last_of("/\\");
    const std::size_t dot = path.find_last_of('.');
    if (dot == std::string::npos || (slash != std::string::npos && dot < slash)) return {};
    std::string ext = path.substr(dot);
    std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) {
        return static_cast<char>(std::tolower(c));
    });
    return ext;
}

} // namespace

MediaEntryKind MediaPathPolicy::classify(const std::string& path, bool isDirectory) noexcept {
    if (isDirectory) return MediaEntryKind::Directory;
    const std::string ext = lowerExtension(path);
    if (ext == ".sv") return MediaEntryKind::SilvetonBank;
    if (ext == ".kmp" || ext == ".ksc" || ext == ".ksf" ||
        ext == ".wav" || ext == ".wave" || ext == ".aif" || ext == ".aiff" || ext == ".aifc") {
        return MediaEntryKind::ImportableSamplerFile;
    }
    return MediaEntryKind::Unsupported;
}

bool MediaPathPolicy::isImportable(const std::string& path) noexcept {
    return classify(path, false) == MediaEntryKind::ImportableSamplerFile;
}

bool MediaPathPolicy::isSilvetonBank(const std::string& path) noexcept {
    return classify(path, false) == MediaEntryKind::SilvetonBank;
}

std::string MediaPathPolicy::normalizeAbsolutePath(const std::string& path) {
    if (path.empty() || path.front() != '/') return {};
    std::vector<std::string> parts;
    std::size_t start = 1U;
    while (start <= path.size()) {
        const std::size_t slash = path.find('/', start);
        const std::size_t end = slash == std::string::npos ? path.size() : slash;
        const std::string part = path.substr(start, end - start);
        if (!part.empty() && part != ".") {
            if (part == "..") {
                if (!parts.empty()) parts.pop_back();
            } else {
                parts.push_back(part);
            }
        }
        if (slash == std::string::npos) break;
        start = slash + 1U;
    }

    if (parts.empty()) return "/";
    std::string normalized;
    for (const auto& part : parts) {
        normalized.push_back('/');
        normalized += part;
    }
    return normalized;
}

bool MediaPathPolicy::isInsideRoot(const std::string& root, const std::string& candidate) {
    const std::string normalizedRoot = normalizeAbsolutePath(root);
    const std::string normalizedCandidate = normalizeAbsolutePath(candidate);
    if (normalizedRoot.empty() || normalizedCandidate.empty()) return false;
    if (normalizedRoot == "/") return true;
    if (normalizedCandidate == normalizedRoot) return true;
    if (normalizedCandidate.size() <= normalizedRoot.size()) return false;
    if (normalizedCandidate.compare(0U, normalizedRoot.size(), normalizedRoot) != 0) return false;
    return normalizedCandidate[normalizedRoot.size()] == '/';
}

} // namespace silveton::manager
