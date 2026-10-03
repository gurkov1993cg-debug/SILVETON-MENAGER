#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include "silveton/manager/ManagerTypes.h"
#include "silveton/manager/SvBankReader.h"

#include <cstddef>
#include <string>
#include <utility>

using silveton::manager::BankProject;
using silveton::manager::SvBankReader;

@interface SVManagerDocument : NSObject
- (void)clearProject;
@end

@interface SVManagerDocument (BankIO)
- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
@end

namespace {

BankProject* SVProjectPointer(SVManagerDocument* document) noexcept {
    if (document == nil) return nullptr;
    Ivar projectIvar = class_getInstanceVariable([SVManagerDocument class], "_project");
    if (projectIvar == nullptr) return nullptr;
    const ptrdiff_t offset = ivar_getOffset(projectIvar);
    if (offset <= 0) return nullptr;
    auto* base = reinterpret_cast<unsigned char*>((__bridge void*)document);
    return reinterpret_cast<BankProject*>(base + offset);
}

NSString* SVString(const std::string& text) {
    return [NSString stringWithUTF8String:text.c_str()] ?: @"";
}

} // namespace

@implementation SVManagerDocument (BankIO)

- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary {
    if (path.length == 0U) {
        if (error != nullptr) *error = @"No SILVETON bank path was selected.";
        return NO;
    }

    BankProject* destination = SVProjectPointer(self);
    if (destination == nullptr) {
        if (error != nullptr) *error = @"The Manager project storage is unavailable.";
        return NO;
    }

    const char* fileSystemPath = [path fileSystemRepresentation];
    if (fileSystemPath == nullptr || *fileSystemPath == '\0') {
        if (error != nullptr) *error = @"The selected SILVETON bank path is invalid.";
        return NO;
    }

    auto loaded = SvBankReader::readFile(std::string(fileSystemPath), true);
    if (!loaded.ok()) {
        if (error != nullptr) *error = SVString(loaded.error);
        return NO;
    }

    // Only replace the live document after the complete bank has passed
    // format, bounds, reference and SHA-256 integrity validation.
    [self clearProject];
    destination = SVProjectPointer(self);
    if (destination == nullptr) {
        if (error != nullptr) *error = @"The Manager project storage became unavailable.";
        return NO;
    }
    *destination = std::move(loaded.project);

    if (summary != nullptr) {
        *summary = [NSString stringWithFormat:@"Opened %@ · %zu SOUNDs · %zu multisamples · %zu samples",
                    SVString(destination->name), destination->sounds.size(), destination->multisamples.size(), destination->samples.size()];
    }
    if (error != nullptr) *error = nil;
    return YES;
}

@end
