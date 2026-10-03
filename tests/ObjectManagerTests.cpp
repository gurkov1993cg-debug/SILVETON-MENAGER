#include "silveton/manager/ObjectManager.h"

#include <cstdlib>
#include <iostream>
#include <string>

using namespace silveton::manager;

namespace {

[[noreturn]] void fail(const char* message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const char* message) {
    if (!condition) fail(message);
}

ImportedSample sample(const char* name) {
    ImportedSample s{};
    s.name = name;
    s.sourceIdentity = name;
    s.sampleRate = 48000U;
    s.channels = 1U;
    s.encoding = AudioEncoding::Pcm16LE;
    s.bitsPerSample = 16U;
    s.rootKey = 60U;
    s.totalFrames = 2U;
    s.audioData = {0U, 0U, 1U, 0U};
    return s;
}

BankProject makeProject() {
    BankProject p{};
    p.samples.push_back(sample("A"));
    p.samples.push_back(sample("B"));

    ImportedMultisample ms0{};
    ms0.name = "MS0";
    ImportedZone z0{}; z0.sampleIndex = 0U;
    ImportedZone z1{}; z1.sampleIndex = 1U;
    ms0.zones = {z0, z1};
    p.multisamples.push_back(ms0);

    ImportedMultisample ms1{};
    ms1.name = "MS1";
    ImportedZone z2{}; z2.sampleIndex = 1U;
    ms1.zones = {z2};
    p.multisamples.push_back(ms1);

    SoundDefinition s0{};
    s0.name = "S0";
    SoundLayer l0{}; l0.multisampleIndex = 0U;
    SoundLayer l1{}; l1.multisampleIndex = 1U;
    s0.layers = {l0, l1};
    p.sounds.push_back(s0);

    SoundDefinition s1{};
    s1.name = "S1";
    SoundLayer l2{}; l2.multisampleIndex = 1U;
    s1.layers = {l2};
    s1.slot = 1U;
    p.sounds.push_back(s1);
    return p;
}

} // namespace

int main() {
    {
        BankProject p = makeProject();
        std::string e;
        std::size_t created = 0U;
        require(ObjectManager::duplicateSample(p, 0U, created, e), "duplicate sample");
        require(created == 2U && p.samples.size() == 3U, "sample duplicate index");
        require(p.samples[2U].audioData == p.samples[0U].audioData, "sample duplicate PCM");
        require(p.samples[2U].name != p.samples[0U].name, "sample duplicate unique name");
        require(ObjectManager::renameSample(p, 2U, "Renamed", e), "rename sample");
        require(p.samples[2U].name == "Renamed", "renamed sample state");
    }

    {
        BankProject p = makeProject();
        std::string e;
        DeleteImpact impact{};
        require(ObjectManager::deleteSampleCascade(p, 0U, impact, e), "delete sample cascade");
        require(p.samples.size() == 1U, "one sample remains");
        require(p.multisamples.size() == 2U, "both multisamples remain");
        require(p.multisamples[0U].zones.size() == 1U, "referencing zone removed");
        require(p.multisamples[0U].zones[0U].sampleIndex == 0U, "sample index remapped");
        require(p.multisamples[1U].zones[0U].sampleIndex == 0U, "second sample index remapped");
        require(impact.samplesRemoved == 1U && impact.zonesRemoved == 1U, "sample delete impact");
    }

    {
        BankProject p = makeProject();
        std::string e;
        DeleteImpact impact{};
        require(ObjectManager::deleteSampleCascade(p, 1U, impact, e), "delete sample with cascading objects");
        require(p.samples.size() == 1U, "sample B removed");
        require(p.multisamples.size() == 1U, "empty multisample removed");
        require(p.sounds.size() == 1U, "empty SOUND removed");
        require(p.sounds[0U].layers.size() == 1U, "removed multisample layer removed");
        require(p.sounds[0U].layers[0U].multisampleIndex == 0U, "remaining multisample reference valid");
        require(impact.multisamplesRemoved == 1U && impact.soundsRemoved == 1U, "cascade impact counts");
    }

    {
        BankProject p = makeProject();
        std::string e;
        std::size_t created = 0U;
        require(ObjectManager::duplicateMultisample(p, 0U, created, e), "duplicate multisample");
        require(created == 2U && p.multisamples[2U].zones.size() == 2U, "multisample duplicate content");
        require(ObjectManager::renameMultisample(p, 2U, "MS Copy Renamed", e), "rename multisample");
        require(p.multisamples[2U].name == "MS Copy Renamed", "renamed multisample state");
    }

    {
        BankProject p = makeProject();
        std::string e;
        DeleteImpact impact{};
        require(ObjectManager::deleteMultisampleCascade(p, 0U, impact, e), "delete multisample cascade");
        require(p.multisamples.size() == 1U, "one multisample remains");
        require(p.sounds.size() == 2U, "sounds with valid remaining layer preserved");
        require(p.sounds[0U].layers.size() == 1U && p.sounds[0U].layers[0U].multisampleIndex == 0U, "sound layer remapped");
        require(p.sounds[1U].layers[0U].multisampleIndex == 0U, "second sound layer remapped");
        require(impact.layersRemoved == 1U, "multisample cascade removed layer");
    }

    {
        BankProject p = makeProject();
        std::string e;
        std::size_t created = 0U;
        require(ObjectManager::duplicateSound(p, 0U, created, e), "duplicate sound");
        require(created == 2U && p.sounds.size() == 3U, "sound duplicate count");
        require(!(p.sounds[2U].bank == p.sounds[0U].bank && p.sounds[2U].page == p.sounds[0U].page && p.sounds[2U].slot == p.sounds[0U].slot), "duplicate sound gets free address");
        require(ObjectManager::createSoundFromMultisample(p, 1U, "Fresh", created, e), "create sound from multisample");
        require(p.sounds[created].layers.size() == 1U && p.sounds[created].layers[0U].multisampleIndex == 1U, "new sound layer");
        DeleteImpact impact{};
        require(ObjectManager::deleteSound(p, 0U, impact, e), "delete sound");
        require(impact.soundsRemoved == 1U, "sound delete impact");
    }

    std::cout << "SILVETON ObjectManager tests PASS\n";
    return 0;
}
