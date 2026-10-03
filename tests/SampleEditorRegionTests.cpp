#include "silveton/manager/SampleEditor.h"

#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

namespace {

using silveton::manager::AudioEncoding;
using silveton::manager::ImportedSample;
using silveton::manager::SampleEditor;
using silveton::manager::SampleRegion;

[[noreturn]] void fail(const std::string& message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const std::string& message) {
    if (!condition) fail(message);
}

void appendPcm16(std::vector<std::uint8_t>& bytes, std::int16_t value) {
    const std::uint16_t raw = static_cast<std::uint16_t>(value);
    bytes.push_back(static_cast<std::uint8_t>(raw & 0xFFU));
    bytes.push_back(static_cast<std::uint8_t>((raw >> 8U) & 0xFFU));
}

std::int16_t pcm16At(const ImportedSample& sample, std::uint64_t frame) {
    require(frame < sample.totalFrames, "PCM frame out of range");
    const std::size_t offset = static_cast<std::size_t>(frame) * 2U;
    const std::uint16_t raw = static_cast<std::uint16_t>(sample.audioData[offset]) |
                              static_cast<std::uint16_t>(static_cast<std::uint16_t>(sample.audioData[offset + 1U]) << 8U);
    return static_cast<std::int16_t>(raw);
}

ImportedSample makeSample() {
    ImportedSample sample{};
    sample.name = "region-test";
    sample.sampleRate = 48000U;
    sample.channels = 1U;
    sample.encoding = AudioEncoding::Pcm16LE;
    sample.bitsPerSample = 16U;
    sample.totalFrames = 8U;
    const std::int16_t values[] = {-30000, -20000, -10000, -5000, 5000, 10000, 20000, 30000};
    for (const std::int16_t value : values) appendPcm16(sample.audioData, value);
    sample.loop.enabled = true;
    sample.loop.startFrame = 2U;
    sample.loop.endFrame = 6U;
    return sample;
}

} // namespace

int main() {
    std::string error;
    const ImportedSample original = makeSample();
    require(original.valid(), "fixture sample must be valid");

    SampleRegion copied{};
    require(SampleEditor::copyRegion(original, 2U, 5U, copied, error), "copy region");
    require(copied.frameCount == 3U && copied.audioData.size() == 6U, "copy preserves exact selected frame count");

    ImportedSample silenced = original;
    require(SampleEditor::silenceRegion(silenced, 2U, 4U, error), "silence region");
    require(pcm16At(silenced, 1U) == -20000 && pcm16At(silenced, 2U) == 0 && pcm16At(silenced, 3U) == 0 && pcm16At(silenced, 4U) == 5000,
            "silence changes only selected frames");

    ImportedSample deletedBeforeLoop = original;
    require(SampleEditor::deleteRegion(deletedBeforeLoop, 0U, 2U, error), "delete before loop");
    require(deletedBeforeLoop.totalFrames == 6U, "delete reduces frame count");
    require(deletedBeforeLoop.loop.enabled && deletedBeforeLoop.loop.startFrame == 0U && deletedBeforeLoop.loop.endFrame == 4U,
            "delete before loop remaps loop without guessing");

    ImportedSample deletedAcrossLoop = original;
    require(SampleEditor::deleteRegion(deletedAcrossLoop, 3U, 4U, error), "delete overlapping loop");
    require(!deletedAcrossLoop.loop.enabled, "delete overlapping loop clears unsafe loop metadata");

    ImportedSample rejectWholeDelete = original;
    const auto wholeDeleteBefore = rejectWholeDelete.audioData;
    require(!SampleEditor::deleteRegion(rejectWholeDelete, 0U, rejectWholeDelete.totalFrames, error), "whole sample delete must be rejected");
    require(rejectWholeDelete.audioData == wholeDeleteBefore && rejectWholeDelete.totalFrames == original.totalFrames,
            "rejected whole sample delete is atomic");

    ImportedSample pasted = original;
    require(SampleEditor::insertRegion(pasted, 1U, copied, error), "paste compatible region");
    require(pasted.totalFrames == 11U, "paste increases frame count");
    require(pasted.loop.enabled && pasted.loop.startFrame == 5U && pasted.loop.endFrame == 9U,
            "paste before loop shifts loop endpoints");
    require(pcm16At(pasted, 1U) == -10000 && pcm16At(pasted, 2U) == -5000 && pcm16At(pasted, 3U) == 5000,
            "paste inserts copied PCM in order");

    ImportedSample incompatible = original;
    SampleRegion wrongFormat = copied;
    wrongFormat.sampleRate = 44100U;
    const auto incompatibleBefore = incompatible.audioData;
    require(!SampleEditor::insertRegion(incompatible, 1U, wrongFormat, error), "paste mismatched sample rate must fail");
    require(incompatible.audioData == incompatibleBefore && incompatible.totalFrames == original.totalFrames,
            "rejected paste is atomic");

    ImportedSample reversed = original;
    require(SampleEditor::reverseRegion(reversed, 2U, 6U, error), "reverse selected range");
    require(pcm16At(reversed, 1U) == -20000 && pcm16At(reversed, 2U) == 10000 && pcm16At(reversed, 3U) == 5000 &&
            pcm16At(reversed, 4U) == -5000 && pcm16At(reversed, 5U) == -10000 && pcm16At(reversed, 6U) == 20000,
            "reverse changes only selected range");
    require(reversed.loop.enabled && reversed.loop.startFrame == 2U && reversed.loop.endFrame == 6U,
            "reverse remaps contained loop");

    ImportedSample gained = original;
    require(SampleEditor::applyGainDbRegion(gained, 2U, 4U, -6.0F, error), "range gain");
    require(pcm16At(gained, 1U) == -20000 && pcm16At(gained, 4U) == 5000, "range gain leaves outside frames untouched");
    require(std::abs(static_cast<int>(pcm16At(gained, 2U))) < 6000, "range gain attenuates selected PCM");

    ImportedSample normalized = original;
    require(SampleEditor::normalizeRegion(normalized, 2U, 4U, 0.0F, error), "range normalize");
    require(std::abs(static_cast<int>(pcm16At(normalized, 2U))) >= 32766, "range normalize reaches requested peak");
    require(pcm16At(normalized, 1U) == -20000 && pcm16At(normalized, 4U) == 5000, "range normalize leaves outside frames untouched");

    ImportedSample fadedIn = original;
    require(SampleEditor::fadeInRegion(fadedIn, 2U, 5U, error), "range fade in");
    require(pcm16At(fadedIn, 2U) == 0 && pcm16At(fadedIn, 4U) == 5000, "range fade in spans exact selection");
    require(pcm16At(fadedIn, 1U) == -20000 && pcm16At(fadedIn, 5U) == 10000, "range fade in preserves outside frames");

    ImportedSample fadedOut = original;
    require(SampleEditor::fadeOutRegion(fadedOut, 3U, 6U, error), "range fade out");
    require(pcm16At(fadedOut, 3U) == -5000 && pcm16At(fadedOut, 5U) == 0, "range fade out spans exact selection");
    require(pcm16At(fadedOut, 2U) == -10000 && pcm16At(fadedOut, 6U) == 20000, "range fade out preserves outside frames");

    std::cout << "Sample editor region tests passed\n";
    return 0;
}
