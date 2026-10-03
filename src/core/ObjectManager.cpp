#include "silveton/manager/ObjectManager.h"

#include <algorithm>
#include <limits>
#include <sstream>
#include <unordered_set>
#include <vector>

namespace silveton::manager {
namespace {

bool addressUsed(const BankProject& project, std::uint16_t bank, std::uint16_t page, std::uint16_t slot) noexcept {
    for (const auto& sound : project.sounds) {
        if (sound.bank == bank && sound.page == page && sound.slot == slot) return true;
    }
    return false;
}

bool nextAddress(std::uint16_t& bank, std::uint16_t& page, std::uint16_t& slot) noexcept {
    if (slot < 127U) { ++slot; return true; }
    slot = 0U;
    if (page < 127U) { ++page; return true; }
    page = 0U;
    if (bank < 127U) { ++bank; return true; }
    return false;
}

template <typename Container>
bool nameExists(const Container& container, const std::string& name) {
    return std::any_of(container.begin(), container.end(), [&](const auto& item) { return item.name == name; });
}

} // namespace

bool ObjectManager::validName(const std::string& name) noexcept {
    return std::any_of(name.begin(), name.end(), [](unsigned char c) { return c > 32U; });
}

std::string ObjectManager::uniqueName(const std::string& base, const BankProject& project, int kind) {
    const std::string stem = validName(base) ? base : std::string("Copy");
    auto exists = [&](const std::string& candidate) {
        if (kind == 0) return nameExists(project.samples, candidate);
        if (kind == 1) return nameExists(project.multisamples, candidate);
        return nameExists(project.sounds, candidate);
    };
    std::string candidate = stem + " Copy";
    if (!exists(candidate)) return candidate;
    for (std::size_t i = 2U; i < 100000U; ++i) {
        candidate = stem + " Copy " + std::to_string(i);
        if (!exists(candidate)) return candidate;
    }
    return stem + " Copy Unique";
}

bool ObjectManager::assignNextFreeSoundAddress(BankProject& project, SoundDefinition& sound, std::string& error) {
    std::uint16_t bank = sound.bank;
    std::uint16_t page = sound.page;
    std::uint16_t slot = sound.slot;
    do {
        if (!addressUsed(project, bank, page, slot)) {
            sound.bank = bank;
            sound.page = page;
            sound.slot = slot;
            error.clear();
            return true;
        }
    } while (nextAddress(bank, page, slot));
    error = "No free Bank/Page/Slot address is available.";
    return false;
}

bool ObjectManager::renameSample(BankProject& project, std::size_t sampleIndex, const std::string& name, std::string& error) {
    if (sampleIndex >= project.samples.size()) { error = "Invalid sample index."; return false; }
    if (!validName(name)) { error = "Sample name cannot be empty."; return false; }
    project.samples[sampleIndex].name = name;
    error.clear();
    return true;
}

bool ObjectManager::duplicateSample(BankProject& project, std::size_t sampleIndex, std::size_t& createdIndex, std::string& error) {
    if (sampleIndex >= project.samples.size()) { error = "Invalid sample index."; return false; }
    ImportedSample copy = project.samples[sampleIndex];
    copy.name = uniqueName(copy.name, project, 0);
    copy.sourceIdentity += ":copy:" + std::to_string(project.samples.size());
    createdIndex = project.samples.size();
    project.samples.push_back(std::move(copy));
    error.clear();
    return true;
}

bool ObjectManager::deleteSampleCascade(BankProject& project, std::size_t sampleIndex, DeleteImpact& impact, std::string& error) {
    impact = DeleteImpact{};
    if (sampleIndex >= project.samples.size()) { error = "Invalid sample index."; return false; }

    project.samples.erase(project.samples.begin() + static_cast<std::ptrdiff_t>(sampleIndex));
    impact.samplesRemoved = 1U;

    std::vector<bool> removeMultisample(project.multisamples.size(), false);
    for (std::size_t m = 0U; m < project.multisamples.size(); ++m) {
        auto& zones = project.multisamples[m].zones;
        const std::size_t before = zones.size();
        zones.erase(std::remove_if(zones.begin(), zones.end(), [sampleIndex](const ImportedZone& zone) {
            return zone.sampleIndex == sampleIndex;
        }), zones.end());
        impact.zonesRemoved += before - zones.size();
        for (auto& zone : zones) {
            if (zone.sampleIndex > sampleIndex) --zone.sampleIndex;
        }
        if (zones.empty()) removeMultisample[m] = true;
    }

    std::vector<std::uint32_t> map(project.multisamples.size(), std::numeric_limits<std::uint32_t>::max());
    std::vector<ImportedMultisample> kept;
    kept.reserve(project.multisamples.size());
    for (std::size_t old = 0U; old < project.multisamples.size(); ++old) {
        if (removeMultisample[old]) { ++impact.multisamplesRemoved; continue; }
        map[old] = static_cast<std::uint32_t>(kept.size());
        kept.push_back(std::move(project.multisamples[old]));
    }
    project.multisamples = std::move(kept);

    std::vector<SoundDefinition> keptSounds;
    keptSounds.reserve(project.sounds.size());
    for (auto& sound : project.sounds) {
        const std::size_t before = sound.layers.size();
        sound.layers.erase(std::remove_if(sound.layers.begin(), sound.layers.end(), [&](SoundLayer& layer) {
            if (layer.multisampleIndex >= map.size()) return true;
            const std::uint32_t mapped = map[layer.multisampleIndex];
            if (mapped == std::numeric_limits<std::uint32_t>::max()) return true;
            layer.multisampleIndex = mapped;
            return false;
        }), sound.layers.end());
        impact.layersRemoved += before - sound.layers.size();
        if (sound.layers.empty()) { ++impact.soundsRemoved; continue; }
        keptSounds.push_back(std::move(sound));
    }
    project.sounds = std::move(keptSounds);
    error.clear();
    return true;
}

bool ObjectManager::renameMultisample(BankProject& project, std::size_t multisampleIndex, const std::string& name, std::string& error) {
    if (multisampleIndex >= project.multisamples.size()) { error = "Invalid multisample index."; return false; }
    if (!validName(name)) { error = "Multisample name cannot be empty."; return false; }
    project.multisamples[multisampleIndex].name = name;
    error.clear();
    return true;
}

bool ObjectManager::duplicateMultisample(BankProject& project, std::size_t multisampleIndex, std::size_t& createdIndex, std::string& error) {
    if (multisampleIndex >= project.multisamples.size()) { error = "Invalid multisample index."; return false; }
    ImportedMultisample copy = project.multisamples[multisampleIndex];
    copy.name = uniqueName(copy.name, project, 1);
    copy.sourceIdentity += ":copy:" + std::to_string(project.multisamples.size());
    createdIndex = project.multisamples.size();
    project.multisamples.push_back(std::move(copy));
    error.clear();
    return true;
}

bool ObjectManager::deleteMultisampleCascade(BankProject& project, std::size_t multisampleIndex, DeleteImpact& impact, std::string& error) {
    impact = DeleteImpact{};
    if (multisampleIndex >= project.multisamples.size()) { error = "Invalid multisample index."; return false; }
    project.multisamples.erase(project.multisamples.begin() + static_cast<std::ptrdiff_t>(multisampleIndex));
    impact.multisamplesRemoved = 1U;

    std::vector<SoundDefinition> keptSounds;
    keptSounds.reserve(project.sounds.size());
    for (auto& sound : project.sounds) {
        const std::size_t before = sound.layers.size();
        sound.layers.erase(std::remove_if(sound.layers.begin(), sound.layers.end(), [multisampleIndex](const SoundLayer& layer) {
            return layer.multisampleIndex == multisampleIndex;
        }), sound.layers.end());
        impact.layersRemoved += before - sound.layers.size();
        for (auto& layer : sound.layers) {
            if (layer.multisampleIndex > multisampleIndex) --layer.multisampleIndex;
        }
        if (sound.layers.empty()) { ++impact.soundsRemoved; continue; }
        keptSounds.push_back(std::move(sound));
    }
    project.sounds = std::move(keptSounds);
    error.clear();
    return true;
}

bool ObjectManager::renameSound(BankProject& project, std::size_t soundIndex, const std::string& name, std::string& error) {
    if (soundIndex >= project.sounds.size()) { error = "Invalid SOUND index."; return false; }
    if (!validName(name)) { error = "SOUND name cannot be empty."; return false; }
    project.sounds[soundIndex].name = name;
    error.clear();
    return true;
}

bool ObjectManager::createSoundFromMultisample(BankProject& project, std::size_t multisampleIndex, const std::string& name, std::size_t& createdIndex, std::string& error) {
    if (multisampleIndex >= project.multisamples.size()) { error = "Invalid multisample index."; return false; }
    SoundDefinition sound{};
    sound.name = validName(name) ? name : project.multisamples[multisampleIndex].name;
    SoundLayer layer{};
    layer.multisampleIndex = static_cast<std::uint32_t>(multisampleIndex);
    sound.layers.push_back(layer);
    if (!assignNextFreeSoundAddress(project, sound, error)) return false;
    createdIndex = project.sounds.size();
    project.sounds.push_back(std::move(sound));
    error.clear();
    return true;
}

bool ObjectManager::duplicateSound(BankProject& project, std::size_t soundIndex, std::size_t& createdIndex, std::string& error) {
    if (soundIndex >= project.sounds.size()) { error = "Invalid SOUND index."; return false; }
    SoundDefinition copy = project.sounds[soundIndex];
    copy.name = uniqueName(copy.name, project, 2);
    if (!nextAddress(copy.bank, copy.page, copy.slot)) {
        copy.bank = 0U; copy.page = 0U; copy.slot = 0U;
    }
    if (!assignNextFreeSoundAddress(project, copy, error)) return false;
    createdIndex = project.sounds.size();
    project.sounds.push_back(std::move(copy));
    error.clear();
    return true;
}

bool ObjectManager::deleteSound(BankProject& project, std::size_t soundIndex, DeleteImpact& impact, std::string& error) {
    impact = DeleteImpact{};
    if (soundIndex >= project.sounds.size()) { error = "Invalid SOUND index."; return false; }
    project.sounds.erase(project.sounds.begin() + static_cast<std::ptrdiff_t>(soundIndex));
    impact.soundsRemoved = 1U;
    error.clear();
    return true;
}

} // namespace silveton::manager
