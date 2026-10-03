#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include "silveton/manager/AudioExporter.h"
#include "silveton/manager/ManagerTypes.h"
#include "silveton/manager/SampleConverter.h"

#include <cstddef>
#include <string>
#include <utility>
#include <vector>

using silveton::manager::AudioEncoding;
using silveton::manager::AudioExporter;
using silveton::manager::BankProject;
using silveton::manager::ExportAudioFormat;
using silveton::manager::ImportedSample;
using silveton::manager::SampleConversionOptions;
using silveton::manager::SampleConverter;

@interface SVManagerDocument : NSObject
- (void)clearProject;
@end

@interface SVManagerDocument (Converter)
- (BOOL)convertSamplesAtIndexes:(NSIndexSet*)indexes
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error;
- (BOOL)exportSamplesAtIndexes:(NSIndexSet*)indexes
                     directory:(NSString*)directory
                    formatChoice:(NSInteger)formatChoice
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error;
@end

namespace {

BankProject* converterProject(SVManagerDocument* document) noexcept {
    if (document == nil) return nullptr;
    Ivar ivar = class_getInstanceVariable([SVManagerDocument class], "_project");
    if (ivar == nullptr) return nullptr;
    const ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0) return nullptr;
    auto* base = reinterpret_cast<unsigned char*>((__bridge void*)document);
    return reinterpret_cast<BankProject*>(base + offset);
}

void setConverterError(NSString** error, const std::string& text) {
    if (error != nullptr) *error = [NSString stringWithUTF8String:text.c_str()] ?: @"Converter operation failed.";
}

bool configureOptions(const ImportedSample& sample,
                      NSUInteger sampleRate,
                      NSUInteger channels,
                      NSInteger encodingChoice,
                      BOOL dither,
                      SampleConversionOptions& options,
                      std::string& error) {
    if (sampleRate > static_cast<NSUInteger>(UINT32_MAX)) {
        error = "Target sample rate is out of range.";
        return false;
    }
    if (channels > static_cast<NSUInteger>(UINT16_MAX)) {
        error = "Target channel count is out of range.";
        return false;
    }
    options.sampleRate = static_cast<std::uint32_t>(sampleRate);
    options.channels = static_cast<std::uint16_t>(channels);
    options.dither = dither == YES;
    options.changeEncoding = encodingChoice != 0;
    if (encodingChoice == 0) options.encoding = sample.encoding;
    else if (encodingChoice == 1) options.encoding = AudioEncoding::Pcm16LE;
    else if (encodingChoice == 2) options.encoding = AudioEncoding::Pcm24LE;
    else if (encodingChoice == 3) options.encoding = AudioEncoding::Float32LE;
    else {
        error = "Invalid target encoding.";
        return false;
    }
    error.clear();
    return true;
}

bool resetTransientStatePreservingProject(SVManagerDocument* document) {
    BankProject* project = converterProject(document);
    if (project == nullptr) return false;
    BankProject saved = std::move(*project);
    [document clearProject];
    project = converterProject(document);
    if (project == nullptr) return false;
    *project = std::move(saved);
    return true;
}

NSString* safeStem(NSString* input, NSUInteger index) {
    NSString* value = [input stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0U) value = @"Sample";
    NSCharacterSet* forbidden = [NSCharacterSet characterSetWithCharactersInString:@"/:\\"];
    NSArray<NSString*>* pieces = [value componentsSeparatedByCharactersInSet:forbidden];
    value = [pieces componentsJoinedByString:@"_"];
    return [NSString stringWithFormat:@"%03lu_%@", (unsigned long)(index + 1U), value];
}

} // namespace

@implementation SVManagerDocument (Converter)

- (BOOL)convertSamplesAtIndexes:(NSIndexSet*)indexes
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error {
    BankProject* project = converterProject(self);
    if (project == nullptr) {
        if (error != nullptr) *error = @"Project storage is unavailable.";
        return NO;
    }
    if (indexes == nil || indexes.count == 0U) {
        if (error != nullptr) *error = @"Select one or more samples first.";
        return NO;
    }

    std::vector<std::pair<std::size_t, ImportedSample>> converted;
    converted.reserve(indexes.count);
    __block bool failed = false;
    __block std::string failure;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
        if (index >= project->samples.size()) {
            failed = true;
            failure = "A selected sample index is no longer valid.";
            *stop = YES;
            return;
        }
        SampleConversionOptions options{};
        std::string localError;
        if (!configureOptions(project->samples[index], sampleRate, channels, encodingChoice, dither, options, localError)) {
            failed = true;
            failure = localError;
            *stop = YES;
            return;
        }
        ImportedSample result{};
        if (!SampleConverter::convert(project->samples[index], options, result, localError)) {
            failed = true;
            failure = project->samples[index].name + ": " + localError;
            *stop = YES;
            return;
        }
        converted.emplace_back(static_cast<std::size_t>(index), std::move(result));
    }];

    if (failed) {
        setConverterError(error, failure);
        return NO;
    }

    for (auto& item : converted) project->samples[item.first] = std::move(item.second);
    if (!resetTransientStatePreservingProject(self)) {
        if (error != nullptr) *error = @"Samples were converted but editor history could not be reset safely.";
        return NO;
    }

    if (summary != nullptr) {
        *summary = [NSString stringWithFormat:@"Converted %lu sample%@. Sample Undo/Redo and clipboard were reset because audio format/frame indexes changed.",
                    (unsigned long)indexes.count, indexes.count == 1U ? @"" : @"s"];
    }
    if (error != nullptr) *error = nil;
    return YES;
}

- (BOOL)exportSamplesAtIndexes:(NSIndexSet*)indexes
                     directory:(NSString*)directory
                  formatChoice:(NSInteger)formatChoice
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error {
    BankProject* project = converterProject(self);
    if (project == nullptr) {
        if (error != nullptr) *error = @"Project storage is unavailable.";
        return NO;
    }
    if (indexes == nil || indexes.count == 0U) {
        if (error != nullptr) *error = @"Select one or more samples first.";
        return NO;
    }
    if (directory.length == 0U) {
        if (error != nullptr) *error = @"No export folder was selected.";
        return NO;
    }
    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&isDirectory] || !isDirectory) {
        if (error != nullptr) *error = @"The export destination is not a valid folder.";
        return NO;
    }
    if (formatChoice != 0 && formatChoice != 1) {
        if (error != nullptr) *error = @"Invalid export format.";
        return NO;
    }

    const ExportAudioFormat format = formatChoice == 0 ? ExportAudioFormat::Wav : ExportAudioFormat::Aiff;
    NSString* extension = formatChoice == 0 ? @"wav" : @"aiff";

    struct PendingExport {
        ImportedSample sample;
        std::string path;
    };
    std::vector<PendingExport> pending;
    pending.reserve(indexes.count);

    __block bool failed = false;
    __block std::string failure;
    [indexes enumerateIndexesUsingBlock:^(NSUInteger index, BOOL* stop) {
        if (index >= project->samples.size()) {
            failed = true;
            failure = "A selected sample index is no longer valid.";
            *stop = YES;
            return;
        }
        const ImportedSample& source = project->samples[index];
        SampleConversionOptions options{};
        std::string localError;
        if (!configureOptions(source, sampleRate, channels, encodingChoice, dither, options, localError)) {
            failed = true;
            failure = localError;
            *stop = YES;
            return;
        }
        ImportedSample converted{};
        if (!SampleConverter::convert(source, options, converted, localError)) {
            failed = true;
            failure = source.name + ": " + localError;
            *stop = YES;
            return;
        }
        NSString* stem = safeStem([NSString stringWithUTF8String:source.name.c_str()], index);
        NSString* filename = [stem stringByAppendingPathExtension:extension];
        NSString* path = [directory stringByAppendingPathComponent:filename];
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            failed = true;
            failure = "Export would overwrite an existing file: " + std::string(path.fileSystemRepresentation);
            *stop = YES;
            return;
        }
        pending.push_back(PendingExport{std::move(converted), std::string(path.fileSystemRepresentation)});
    }];

    if (failed) {
        setConverterError(error, failure);
        return NO;
    }

    for (const auto& item : pending) {
        std::string exportError;
        if (!AudioExporter::writeFile(item.path, item.sample, format, exportError)) {
            setConverterError(error, exportError);
            return NO;
        }
    }

    if (summary != nullptr) {
        *summary = [NSString stringWithFormat:@"Exported %lu sample%@ as %@ to %@.",
                    (unsigned long)pending.size(), pending.size() == 1U ? @"" : @"s",
                    formatChoice == 0 ? @"WAV" : @"AIFF/AIFC", directory];
    }
    if (error != nullptr) *error = nil;
    return YES;
}

@end
