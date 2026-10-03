#include "silveton/manager/AudioExporter.h"
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
    sample.rootKey = 60U;
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

void testWavAndAiffExport() {
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

    const auto aiffPrefix = readPrefix(aiffPath, 12U);
    require(aiffPrefix.size() == 12U, "AIFF header must exist");
    require(std::string(aiffPrefix.data(), 4U) == "FORM" && std::string(aiffPrefix.data() + 8, 4U) == "AIFF", "AIFF header must be FORM/AIFF");

    (void)std::remove(wavPath.c_str());
    (void)std::remove(aiffPath.c_str());
}

void testFloatAifcExport() {
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
    (void)std::remove(path.c_str());
}

} // namespace

int main() {
    testConversion();
    testDownmixAndKeepEncoding();
    testWavAndAiffExport();
    testFloatAifcExport();
    std::cout << "Sample converter regression tests passed\n";
    return 0;
}
