#include "silveton/manager/AudioExporter.h"
#include "silveton/manager/AudioFileLoader.h"
#include "silveton/manager/SampleConverter.h"

#include <cmath>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

using namespace silveton::manager;

namespace {

void require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}

ImportedSample makePcm16Sine(std::uint32_t rate, std::uint64_t frames, std::uint16_t channels) {
    ImportedSample sample{};
    sample.name = "Converter Test";
    sample.sourceIdentity = "converter-test";
    sample.sampleRate = rate;
    sample.channels = channels;
    sample.encoding = AudioEncoding::Pcm16LE;
    sample.bitsPerSample = 16U;
    sample.totalFrames = frames;
    sample.rootKey = 64U;
    sample.fineTuneCents = 12.0F;
    sample.loop.enabled = true;
    sample.loop.startFrame = frames / 4U;
    sample.loop.endFrame = (frames * 3U) / 4U;
    sample.loop.crossfadeFrames = 16U;
    sample.audioData.reserve(static_cast<std::size_t>(frames) * static_cast<std::size_t>(channels) * 2U);
    for (std::uint64_t frame = 0U; frame < frames; ++frame) {
        const double phase = 2.0 * 3.14159265358979323846 * 440.0 * static_cast<double>(frame) / static_cast<double>(rate);
        const double value = std::sin(phase) * 0.5;
        const auto quantized = static_cast<std::int16_t>(std::lround(value * 32767.0));
        const auto u = static_cast<std::uint16_t>(quantized);
        for (std::uint16_t channel = 0U; channel < channels; ++channel) {
            sample.audioData.push_back(static_cast<std::uint8_t>(u & 0xFFU));
            sample.audioData.push_back(static_cast<std::uint8_t>((u >> 8U) & 0xFFU));
        }
    }
    return sample;
}

std::vector<char> readPrefix(const std::string& path, std::size_t count) {
    std::ifstream input(path, std::ios::binary);
    std::vector<char> bytes(count, '\0');
    input.read(bytes.data(), static_cast<std::streamsize>(bytes.size()));
    bytes.resize(static_cast<std::size_t>(input.gcount()));
    return bytes;
}

void testNoOpIsBitPerfect() {
    ImportedSample source = makePcm16Sine(48000U, 1024U, 2U);
    SampleConversionOptions options{};
    options.sampleRate = 0U;
    options.channels = 0U;
    options.changeEncoding = false;
    options.dither = true;

    ImportedSample converted{};
    std::string error;
    require(SampleConverter::convert(source, options, converted, error), "no-op conversion must succeed");
    require(converted.audioData == source.audioData, "no-op conversion must preserve audio bytes exactly");
    require(converted.sampleRate == source.sampleRate && converted.channels == source.channels, "no-op conversion must preserve format");
    require(converted.encoding == source.encoding && converted.bitsPerSample == source.bitsPerSample, "no-op conversion must preserve encoding");
    require(converted.totalFrames == source.totalFrames, "no-op conversion must preserve frame count");
    require(converted.rootKey == source.rootKey && converted.fineTuneCents == source.fineTuneCents, "no-op conversion must preserve tuning metadata");
    require(converted.loop.enabled == source.loop.enabled && converted.loop.startFrame == source.loop.startFrame && converted.loop.endFrame == source.loop.endFrame,
            "no-op conversion must preserve loop metadata");
}

void testConversion() {
    ImportedSample source = makePcm16Sine(48000U, 4800U, 1U);
    require(source.valid(), "source sample must be valid");

    SampleConversionOptions options{};
    options.sampleRate = 96000U;
    options.channels = 2U;
    options.encoding = AudioEncoding::Pcm24LE;
    options.changeEncoding = true;
    options.dither = true;

    ImportedSample converted{};
    std::string error;
    require(SampleConverter::convert(source, options, converted, error), "96 kHz stereo 24-bit conversion must succeed");
    require(error.empty(), "successful conversion must not return an error");
    require(converted.valid(), "converted sample must remain valid");
    require(converted.sampleRate == 96000U, "sample rate must change to 96 kHz");
    require(converted.channels == 2U, "mono to stereo conversion must produce two channels");
    require(converted.encoding == AudioEncoding::Pcm24LE && converted.bitsPerSample == 24U, "encoding must become 24-bit PCM");
    require(converted.totalFrames == 9600U, "doubling sample rate must double frame count");
    require(converted.loop.enabled, "valid source loop must survive conversion");
    require(converted.loop.startFrame == 2400U && converted.loop.endFrame == 7200U, "loop points must scale with sample rate");
    require(converted.rootKey == source.rootKey && converted.fineTuneCents == source.fineTuneCents, "conversion must preserve tuning metadata");
}

void testDownmixAndKeepEncoding() {
    ImportedSample source = makePcm16Sine(48000U, 4800U, 2U);
    SampleConversionOptions options{};
    options.sampleRate = 24000U;
    options.channels = 1U;
    options.changeEncoding = false;
    options.dither = false;

    ImportedSample converted{};
    std::string error;
    require(SampleConverter::convert(source, options, converted, error), "stereo downmix/downsample must succeed");
    require(converted.sampleRate == 24000U, "downsample rate must be applied");
    require(converted.channels == 1U, "stereo downmix must become mono");
    require(converted.encoding == AudioEncoding::Pcm16LE, "keep encoding must preserve PCM16");
    require(converted.totalFrames == 2400U, "half sample rate must halve frame count");
}

void testWavAndAiffRoundTrip() {
    ImportedSample source = makePcm16Sine(44100U, 441U, 2U);
    const std::string wavPath = "/tmp/silveton_sample_converter_test.wav";
    const std::string aiffPath = "/tmp/silveton_sample_converter_test.aiff";
    (void)std::remove(wavPath.c_str());
    (void)std::remove(aiffPath.c_str());

    std::string error;
    require(AudioExporter::writeFile(wavPath, source, ExportAudioFormat::Wav, error), "WAV export must succeed");
    require(AudioExporter::writeFile(aiffPath, source, ExportAudioFormat::Aiff, error), "AIFF export must succeed");

    const auto wavPrefix = readPrefix(wavPath, 12U);
    require(wavPrefix.size() == 12U, "WAV header must exist");
    require(std::string(wavPrefix.data(), 4U) == "RIFF" && std::string(wavPrefix.data() + 8, 4U) == "WAVE", "WAV header must be RIFF/WAVE");

    const auto wavLoaded = AudioFileLoader::load(wavPath);
    require(wavLoaded.ok(), "exported WAV must be readable by Manager loader");
    require(wavLoaded.sample.sampleRate == source.sampleRate && wavLoaded.sample.channels == source.channels && wavLoaded.sample.totalFrames == source.totalFrames,
            "WAV round trip must preserve basic format");
    require(wavLoaded.sample.rootKey == source.rootKey, "WAV round trip must preserve root key");
    require(wavLoaded.sample.loop.enabled && wavLoaded.sample.loop.startFrame == source.loop.startFrame && wavLoaded.sample.loop.endFrame == source.loop.endFrame,
            "WAV round trip must preserve loop points");

    const auto aiffPrefix = readPrefix(aiffPath, 12U);
    require(aiffPrefix.size() == 12U, "AIFF header must exist");
    require(std::string(aiffPrefix.data(), 4U) == "FORM" && std::string(aiffPrefix.data() + 8, 4U) == "AIFF", "AIFF header must be FORM/AIFF");

    const auto aiffLoaded = AudioFileLoader::load(aiffPath);
    require(aiffLoaded.ok(), "exported AIFF must be readable by Manager loader");
    require(aiffLoaded.sample.sampleRate == source.sampleRate && aiffLoaded.sample.channels == source.channels && aiffLoaded.sample.totalFrames == source.totalFrames,
            "AIFF round trip must preserve basic format");
    require(aiffLoaded.sample.rootKey == source.rootKey, "AIFF round trip must preserve root key");
    require(std::abs(aiffLoaded.sample.fineTuneCents - source.fineTuneCents) < 0.1F, "AIFF round trip must preserve fine tuning");
    require(aiffLoaded.sample.loop.enabled && aiffLoaded.sample.loop.startFrame == source.loop.startFrame && aiffLoaded.sample.loop.endFrame == source.loop.endFrame,
            "AIFF round trip must preserve loop points");

    (void)std::remove(wavPath.c_str());
    (void)std::remove(aiffPath.c_str());
}

void testFloatAifcRoundTrip() {
    ImportedSample source = makePcm16Sine(48000U, 480U, 1U);
    SampleConversionOptions options{};
    options.encoding = AudioEncoding::Float32LE;
    options.changeEncoding = true;
    options.dither = false;
    ImportedSample converted{};
    std::string error;
    require(SampleConverter::convert(source, options, converted, error), "float conversion must succeed");

    const std::string path = "/tmp/silveton_sample_converter_float.aifc";
    (void)std::remove(path.c_str());
    require(AudioExporter::writeFile(path, converted, ExportAudioFormat::Aiff, error), "float AIFC export must succeed");
    const auto prefix = readPrefix(path, 12U);
    require(prefix.size() == 12U && std::string(prefix.data() + 8, 4U) == "AIFC", "float AIFF export must use AIFC container");

    const auto loaded = AudioFileLoader::load(path);
    require(loaded.ok(), "exported float AIFC must be readable by Manager loader");
    require(loaded.sample.encoding == AudioEncoding::Float32LE && loaded.sample.bitsPerSample == 32U, "float AIFC round trip must preserve Float32 encoding");
    require(loaded.sample.sampleRate == converted.sampleRate && loaded.sample.channels == converted.channels && loaded.sample.totalFrames == converted.totalFrames,
            "float AIFC round trip must preserve basic format");
    require(loaded.sample.rootKey == converted.rootKey, "float AIFC round trip must preserve root key");
    require(loaded.sample.loop.enabled && loaded.sample.loop.startFrame == converted.loop.startFrame && loaded.sample.loop.endFrame == converted.loop.endFrame,
            "float AIFC round trip must preserve loop points");
    (void)std::remove(path.c_str());
}

} // namespace

int main() {
    testNoOpIsBitPerfect();
    testConversion();
    testDownmixAndKeepEncoding();
    testWavAndAiffRoundTrip();
    testFloatAifcRoundTrip();
    std::cout << "Sample converter regression tests passed\n";
    return 0;
}
