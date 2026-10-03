#import <Foundation/Foundation.h>

#include "silveton/manager/ManagerTypes.h"
#include "silveton/manager/SvBankBuilder.h"

#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

using namespace silveton::manager;

@interface SVManagerDocument : NSObject
- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (NSUInteger)sampleCount;
- (NSUInteger)multisampleCount;
- (NSUInteger)soundCount;
@end

namespace {

[[noreturn]] void fail(const char* message) {
    std::cerr << "FAIL: " << message << '\n';
    std::exit(1);
}

void require(bool condition, const char* message) {
    if (!condition) fail(message);
}

ImportedSample makeSample() {
    ImportedSample sample{};
    sample.name = "Round Trip Sample";
    sample.sourceIdentity = "test:roundtrip";
    sample.sampleRate = 48000U;
    sample.channels = 1U;
    sample.encoding = AudioEncoding::Pcm16LE;
    sample.bitsPerSample = 16U;
    sample.rootKey = 60U;
    sample.totalFrames = 4U;
    sample.audioData = {0x00U, 0x00U, 0x10U, 0x00U, 0xF0U, 0xFFU, 0x00U, 0x00U};
    return sample;
}

BankProject makeProject() {
    BankProject project{};
    project.name = "OPEN SAVE TEST";
    project.samples.push_back(makeSample());

    ImportedMultisample multisample{};
    multisample.name = "Round Trip MS";
    multisample.sourceIdentity = "test:ms";
    ImportedZone zone{};
    zone.sampleIndex = 0U;
    zone.keyLow = 0U;
    zone.keyHigh = 127U;
    zone.velocityLow = 1U;
    zone.velocityHigh = 127U;
    zone.rootKey = 60U;
    multisample.zones.push_back(zone);
    project.multisamples.push_back(multisample);

    SoundDefinition sound{};
    sound.name = "Round Trip SOUND";
    sound.bank = 2U;
    sound.page = 3U;
    sound.slot = 4U;
    sound.category = 5U;
    SoundLayer layer{};
    layer.multisampleIndex = 0U;
    sound.layers.push_back(layer);
    project.sounds.push_back(sound);
    return project;
}

} // namespace

int main() {
    @autoreleasepool {
        NSString* tempRoot = NSTemporaryDirectory();
        NSString* inputPath = [tempRoot stringByAppendingPathComponent:@"silveton_manager_bankio_input.sv"];
        NSString* outputPath = [tempRoot stringByAppendingPathComponent:@"silveton_manager_bankio_output.sv"];

        SvBuildStats stats{};
        std::string error;
        require(SvBankBuilder::writeAtomic([inputPath fileSystemRepresentation], makeProject(), stats, error), "write input bank");

        SVManagerDocument* document = [[SVManagerDocument alloc] init];
        NSString* openError = nil;
        NSString* openSummary = nil;
        require([document loadBankAtPath:inputPath error:&openError summary:&openSummary] == YES, "open verified bank");
        require(openError == nil, "open error must be nil");
        require(openSummary.length > 0U, "open summary must be populated");
        require([document sampleCount] == 1U, "opened sample count");
        require([document multisampleCount] == 1U, "opened multisample count");
        require([document soundCount] == 1U, "opened sound count");

        NSString* saveError = nil;
        NSString* saveSummary = nil;
        require([document buildBankAtPath:outputPath error:&saveError summary:&saveSummary] == YES, "save opened bank");
        require(saveError == nil, "save error must be nil");
        require(saveSummary.length > 0U, "save summary must be populated");

        FILE* corrupt = std::fopen([inputPath fileSystemRepresentation], "r+b");
        require(corrupt != nullptr, "open bank for corruption");
        require(std::fseek(corrupt, -1L, SEEK_END) == 0, "seek bank tail");
        const int original = std::fgetc(corrupt);
        require(original != EOF, "read bank tail");
        require(std::fseek(corrupt, -1L, SEEK_END) == 0, "seek bank tail for write");
        require(std::fputc(original ^ 0x01, corrupt) != EOF, "corrupt bank tail");
        std::fclose(corrupt);

        NSString* corruptError = nil;
        require([document loadBankAtPath:inputPath error:&corruptError summary:nullptr] == NO, "reject corrupted bank");
        require(corruptError.length > 0U, "corrupt bank error must be populated");
        require([document sampleCount] == 1U && [document multisampleCount] == 1U && [document soundCount] == 1U,
                "failed open must preserve live document");

        std::remove([inputPath fileSystemRepresentation]);
        std::remove([outputPath fileSystemRepresentation]);
        std::cout << "SILVETON Manager bank I/O tests PASS\n";
    }
    return 0;
}
