#include "silveton/manager/MediaPathPolicy.h"

#include <cstdlib>
#include <iostream>

using namespace silveton::manager;

namespace {

[[noreturn]] void fail(const char* message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const char* message) {
    if (!condition) fail(message);
}

} // namespace

int main() {
    require(MediaPathPolicy::classify("/Volumes/USB/BANK.SV", false) == MediaEntryKind::SilvetonBank, "classify .sv");
    require(MediaPathPolicy::classify("/Volumes/USB/Piano.KMP", false) == MediaEntryKind::ImportableSamplerFile, "classify KMP");
    require(MediaPathPolicy::classify("/Volumes/USB/sample.WAV", false) == MediaEntryKind::ImportableSamplerFile, "classify WAV");
    require(MediaPathPolicy::classify("/Volumes/USB/Folder", true) == MediaEntryKind::Directory, "classify directory");
    require(MediaPathPolicy::classify("/Volumes/USB/readme.txt", false) == MediaEntryKind::Unsupported, "reject unsupported");

    require(MediaPathPolicy::normalizeAbsolutePath("/Volumes/USB/SET/../BANK") == "/Volumes/USB/BANK", "normalize parent component");
    require(MediaPathPolicy::normalizeAbsolutePath("/Volumes//USB/./BANK") == "/Volumes/USB/BANK", "normalize repeated slash and dot");
    require(MediaPathPolicy::normalizeAbsolutePath("relative/path").empty(), "reject relative path");

    require(MediaPathPolicy::isInsideRoot("/Volumes/USB", "/Volumes/USB"), "root contains itself");
    require(MediaPathPolicy::isInsideRoot("/Volumes/USB", "/Volumes/USB/SET/BANK.sv"), "root contains child");
    require(MediaPathPolicy::isInsideRoot("/Volumes/USB", "/Volumes/USB/SET/../BANK.sv"), "normalized child stays inside");
    require(!MediaPathPolicy::isInsideRoot("/Volumes/USB", "/Volumes/USB2/BANK.sv"), "prefix collision must not escape root");
    require(!MediaPathPolicy::isInsideRoot("/Volumes/USB", "/Volumes/USB/../Other/BANK.sv"), "parent traversal must escape root");
    require(MediaPathPolicy::isInsideRoot("/", "/Users/test/BANK.sv"), "filesystem root contains absolute child");

    std::cout << "SILVETON Manager MEDIA path policy tests PASS\n";
    return 0;
}
