#include "silveton/manager/SoundEditor.h"

#include <cmath>

namespace silveton::manager {

bool SoundEditor::validateLayer(const BankProject& project,
                                const SoundLayer& layer,
                                std::string& error) noexcept {
    error.clear();
    if (layer.multisampleIndex >= project.multisamples.size()) {
        error = "Sound layer references an invalid multisample";
        return false;
    }
    if (layer.keyLow > 127U || layer.keyHigh > 127U || layer.keyLow > layer.keyHigh) {
        error = "Sound layer key range must be 0..127 and Low cannot exceed High";
        return false;
    }
    if (layer.velocityLow == 0U || layer.velocityLow > 127U ||
        layer.velocityHigh == 0U || layer.velocityHigh > 127U ||
        layer.velocityLow > layer.velocityHigh) {
        error = "Sound layer velocity range must be 1..127 and Low cannot exceed High";
        return false;
    }
    if (!std::isfinite(layer.tuneCents) || layer.tuneCents < -100.0F || layer.tuneCents > 100.0F) {
        error = "Sound layer tune must be between -100 and +100 cents";
        return false;
    }
    if (!std::isfinite(layer.levelDb) || layer.levelDb < -120.0F || layer.levelDb > 24.0F) {
        error = "Sound layer level must be between -120 dB and +24 dB";
        return false;
    }
    if (!std::isfinite(layer.pan) || layer.pan < -1.0F || layer.pan > 1.0F) {
        error = "Sound layer pan must be between -1.0 and +1.0";
        return false;
    }
    return true;
}

bool SoundEditor::addLayer(BankProject& project,
                           std::size_t soundIndex,
                           std::uint32_t multisampleIndex,
                           std::string& error) {
    error.clear();
    if (soundIndex >= project.sounds.size()) {
        error = "Sound index is invalid";
        return false;
    }
    if (multisampleIndex >= project.multisamples.size()) {
        error = "Multisample index is invalid";
        return false;
    }

    SoundLayer layer{};
    layer.multisampleIndex = multisampleIndex;
    if (!validateLayer(project, layer, error)) return false;
    project.sounds[soundIndex].layers.push_back(layer);
    return true;
}

bool SoundEditor::removeLayer(BankProject& project,
                              std::size_t soundIndex,
                              std::size_t layerIndex,
                              std::string& error) {
    error.clear();
    if (soundIndex >= project.sounds.size()) {
        error = "Sound index is invalid";
        return false;
    }
    auto& layers = project.sounds[soundIndex].layers;
    if (layerIndex >= layers.size()) {
        error = "Sound layer index is invalid";
        return false;
    }
    if (layers.size() <= 1U) {
        error = "A SOUND must contain at least one layer";
        return false;
    }
    layers.erase(layers.begin() + static_cast<std::ptrdiff_t>(layerIndex));
    return true;
}

bool SoundEditor::updateLayer(BankProject& project,
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
                              std::string& error) {
    error.clear();
    if (soundIndex >= project.sounds.size()) {
        error = "Sound index is invalid";
        return false;
    }
    if (layerIndex >= project.sounds[soundIndex].layers.size()) {
        error = "Sound layer index is invalid";
        return false;
    }

    SoundLayer candidate{};
    candidate.multisampleIndex = multisampleIndex;
    candidate.enabled = enabled;
    candidate.keyLow = keyLow;
    candidate.keyHigh = keyHigh;
    candidate.velocityLow = velocityLow;
    candidate.velocityHigh = velocityHigh;
    candidate.transposeSemitones = transposeSemitones;
    candidate.tuneCents = tuneCents;
    candidate.levelDb = levelDb;
    candidate.pan = pan;

    if (!validateLayer(project, candidate, error)) return false;
    project.sounds[soundIndex].layers[layerIndex] = candidate;
    return true;
}

} // namespace silveton::manager
