#include "silveton/manager/SoundEditor.h"
#include "silveton/manager/SvBankBuilder.h"
#include "silveton/manager/SvBankReader.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <string>

namespace {

[[noreturn]] void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

silveton::manager::ImportedSample makeSample(const std::string& name) {
    using namespace silveton::manager;
    ImportedSample sample{};
    sample.name = name;
    sample.sourceIdentity = "test:" + name;
    sample.sampleRate = 48000U;
    sample.channels = 1U;
    sample.encoding = AudioEncoding::Pcm16LE;
    sample.bitsPerSample = 16U;
    sample.rootKey = 60U;
    sample.totalFrames = 4U;
    sample.audioData = {0U, 0U, 1U, 0U, 255U, 255U, 0U, 0U};
    return sample;
}

silveton::manager::ImportedMultisample makeMultisample(const std::string& name, std::uint32_t sampleIndex) {
    using namespace silveton::manager;
    ImportedMultisample multisample{};
    multisample.name = name;
    multisample.sourceIdentity = "test-ms:" + name;
    ImportedZone zone{};
    zone.sampleIndex = sampleIndex;
    zone.keyLow = 0U;
    zone.keyHigh = 127U;
    zone.velocityLow = 1U;
    zone.velocityHigh = 127U;
    zone.rootKey = 60U;
    multisample.zones.push_back(zone);
    return multisample;
}

} // namespace

int main() {
    using namespace silveton::manager;

    BankProject project{};
    project.name = "SOUND EDITOR TEST";
    project.samples.push_back(makeSample("A"));
    project.samples.push_back(makeSample("B"));
    project.multisamples.push_back(makeMultisample("MS A", 0U));
    project.multisamples.push_back(makeMultisample("MS B", 1U));

    SoundDefinition sound{};
    sound.name = "Layered Sound";
    SoundLayer initial{};
    initial.multisampleIndex = 0U;
    sound.layers.push_back(initial);
    project.sounds.push_back(sound);

    std::string error;
    require(SoundEditor::addLayer(project, 0U, 1U, error), "add second layer");
    require(project.sounds[0].layers.size() == 2U, "layer count after add");

    require(SoundEditor::updateLayer(project, 0U, 1U, 1U, true,
                                     48U, 84U, 20U, 110U,
                                     static_cast<std::int8_t>(-12), 17.5F, -6.0F, 0.35F, error),
            "update layer parameters");

    const auto& edited = project.sounds[0].layers[1];
    require(edited.multisampleIndex == 1U, "multisample assignment");
    require(edited.keyLow == 48U && edited.keyHigh == 84U, "key range");
    require(edited.velocityLow == 20U && edited.velocityHigh == 110U, "velocity range");
    require(edited.transposeSemitones == -12, "transpose");
    require(std::fabs(edited.tuneCents - 17.5F) < 1.0e-6F, "fine tune");
    require(std::fabs(edited.levelDb + 6.0F) < 1.0e-6F, "level");
    require(std::fabs(edited.pan - 0.35F) < 1.0e-6F, "pan");

    const SoundLayer beforeInvalid = project.sounds[0].layers[1];
    require(!SoundEditor::updateLayer(project, 0U, 1U, 1U, true,
                                      100U, 20U, 1U, 127U,
                                      0, 0.0F, 0.0F, 0.0F, error),
            "reject reversed key range");
    const auto& afterInvalid = project.sounds[0].layers[1];
    require(afterInvalid.keyLow == beforeInvalid.keyLow && afterInvalid.keyHigh == beforeInvalid.keyHigh,
            "rejected update must not mutate layer");

    require(!SoundEditor::removeLayer(project, 9U, 0U, error), "reject invalid sound index");
    require(SoundEditor::removeLayer(project, 0U, 0U, error), "remove first layer");
    require(project.sounds[0].layers.size() == 1U, "one layer remains");
    require(!SoundEditor::removeLayer(project, 0U, 0U, error), "reject removal of last layer");

    auto built = SvBankBuilder::build(project);
    require(built.ok(), "build layered sound bank");
    auto round = SvBankReader::read(built.bytes, true);
    require(round.ok(), "read layered sound bank");
    require(round.project.sounds.size() == 1U && round.project.sounds[0].layers.size() == 1U,
            "round-trip layer count");
    const auto& restored = round.project.sounds[0].layers[0];
    require(restored.multisampleIndex == 1U, "round-trip multisample assignment");
    require(restored.keyLow == 48U && restored.keyHigh == 84U, "round-trip key range");
    require(restored.velocityLow == 20U && restored.velocityHigh == 110U, "round-trip velocity range");
    require(restored.transposeSemitones == -12, "round-trip transpose");
    require(std::fabs(restored.tuneCents - 17.5F) < 1.0e-6F, "round-trip tune");
    require(std::fabs(restored.levelDb + 6.0F) < 1.0e-6F, "round-trip level");
    require(std::fabs(restored.pan - 0.35F) < 1.0e-6F, "round-trip pan");

    std::cout << "SILVETON Sound Editor tests PASS\n";
    return 0;
}
