#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include "silveton/manager/ManagerTypes.h"
#include "silveton/manager/ObjectManager.h"

#include <cstddef>
#include <string>
#include <utility>

using silveton::manager::BankProject;
using silveton::manager::DeleteImpact;
using silveton::manager::ObjectManager;

@interface SVManagerDocument : NSObject
- (void)clearProject;
@end

@interface SVManagerDocument (Objects)
- (BOOL)renameObjectKind:(NSInteger)kind index:(NSUInteger)index name:(NSString*)name error:(NSString**)error;
- (BOOL)duplicateObjectKind:(NSInteger)kind index:(NSUInteger)index createdIndex:(NSUInteger*)createdIndex error:(NSString**)error;
- (BOOL)deleteObjectKind:(NSInteger)kind index:(NSUInteger)index summary:(NSString**)summary error:(NSString**)error;
- (BOOL)createSoundFromMultisampleIndex:(NSUInteger)multisampleIndex name:(NSString*)name createdIndex:(NSUInteger*)createdIndex error:(NSString**)error;
@end

namespace {

BankProject* SVObjectsProject(SVManagerDocument* document) noexcept {
    if (document == nil) return nullptr;
    Ivar ivar = class_getInstanceVariable([SVManagerDocument class], "_project");
    if (ivar == nullptr) return nullptr;
    const ptrdiff_t offset = ivar_getOffset(ivar);
    if (offset <= 0) return nullptr;
    auto* base = reinterpret_cast<unsigned char*>((__bridge void*)document);
    return reinterpret_cast<BankProject*>(base + offset);
}

std::string SVObjectName(NSString* name) {
    NSString* trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.length == 0U ? std::string() : std::string(trimmed.UTF8String);
}

void SVObjectError(NSString** error, const std::string& text) {
    if (error != nullptr) *error = [NSString stringWithUTF8String:text.c_str()] ?: @"Object operation failed.";
}

NSString* SVImpactSummary(const DeleteImpact& impact) {
    return [NSString stringWithFormat:@"Removed: %zu sample%@, %zu zone%@, %zu multisample%@, %zu layer%@, %zu SOUND%@.",
            impact.samplesRemoved, impact.samplesRemoved == 1U ? @"" : @"s",
            impact.zonesRemoved, impact.zonesRemoved == 1U ? @"" : @"s",
            impact.multisamplesRemoved, impact.multisamplesRemoved == 1U ? @"" : @"s",
            impact.layersRemoved, impact.layersRemoved == 1U ? @"" : @"s",
            impact.soundsRemoved, impact.soundsRemoved == 1U ? @"" : @"s"];
}

bool SVResetTransientStatePreservingProject(SVManagerDocument* document) {
    BankProject* project = SVObjectsProject(document);
    if (project == nullptr) return false;
    BankProject saved = std::move(*project);
    [document clearProject];
    project = SVObjectsProject(document);
    if (project == nullptr) return false;
    *project = std::move(saved);
    return true;
}

} // namespace

@implementation SVManagerDocument (Objects)

- (BOOL)renameObjectKind:(NSInteger)kind index:(NSUInteger)index name:(NSString*)name error:(NSString**)error {
    BankProject* project = SVObjectsProject(self);
    if (project == nullptr) { if (error != nullptr) *error = @"Project storage is unavailable."; return NO; }
    const std::string objectName = SVObjectName(name);
    std::string e;
    bool ok = false;
    if (kind == 0) ok = ObjectManager::renameSample(*project, static_cast<std::size_t>(index), objectName, e);
    else if (kind == 1) ok = ObjectManager::renameMultisample(*project, static_cast<std::size_t>(index), objectName, e);
    else if (kind == 2) ok = ObjectManager::renameSound(*project, static_cast<std::size_t>(index), objectName, e);
    else e = "Invalid object kind.";
    if (!ok) { SVObjectError(error, e); return NO; }
    if (error != nullptr) *error = nil;
    return YES;
}

- (BOOL)duplicateObjectKind:(NSInteger)kind index:(NSUInteger)index createdIndex:(NSUInteger*)createdIndex error:(NSString**)error {
    BankProject* project = SVObjectsProject(self);
    if (project == nullptr) { if (error != nullptr) *error = @"Project storage is unavailable."; return NO; }
    std::size_t created = 0U;
    std::string e;
    bool ok = false;
    if (kind == 0) ok = ObjectManager::duplicateSample(*project, static_cast<std::size_t>(index), created, e);
    else if (kind == 1) ok = ObjectManager::duplicateMultisample(*project, static_cast<std::size_t>(index), created, e);
    else if (kind == 2) ok = ObjectManager::duplicateSound(*project, static_cast<std::size_t>(index), created, e);
    else e = "Invalid object kind.";
    if (!ok) { SVObjectError(error, e); return NO; }
    if (createdIndex != nullptr) *createdIndex = static_cast<NSUInteger>(created);
    if (error != nullptr) *error = nil;
    return YES;
}

- (BOOL)deleteObjectKind:(NSInteger)kind index:(NSUInteger)index summary:(NSString**)summary error:(NSString**)error {
    BankProject* project = SVObjectsProject(self);
    if (project == nullptr) { if (error != nullptr) *error = @"Project storage is unavailable."; return NO; }
    DeleteImpact impact{};
    std::string e;
    bool ok = false;
    if (kind == 0) ok = ObjectManager::deleteSampleCascade(*project, static_cast<std::size_t>(index), impact, e);
    else if (kind == 1) ok = ObjectManager::deleteMultisampleCascade(*project, static_cast<std::size_t>(index), impact, e);
    else if (kind == 2) ok = ObjectManager::deleteSound(*project, static_cast<std::size_t>(index), impact, e);
    else e = "Invalid object kind.";
    if (!ok) { SVObjectError(error, e); return NO; }

    // Deleting a sample changes sample indexes. Clear sample edit Undo/Redo and
    // clipboard while preserving the fully remapped project so stale history
    // can never restore audio into the wrong sample.
    if (kind == 0 && !SVResetTransientStatePreservingProject(self)) {
        if (error != nullptr) *error = @"Object deletion succeeded but transient editor state could not be reset safely.";
        return NO;
    }

    if (summary != nullptr) *summary = SVImpactSummary(impact);
    if (error != nullptr) *error = nil;
    return YES;
}

- (BOOL)createSoundFromMultisampleIndex:(NSUInteger)multisampleIndex name:(NSString*)name createdIndex:(NSUInteger*)createdIndex error:(NSString**)error {
    BankProject* project = SVObjectsProject(self);
    if (project == nullptr) { if (error != nullptr) *error = @"Project storage is unavailable."; return NO; }
    std::size_t created = 0U;
    std::string e;
    if (!ObjectManager::createSoundFromMultisample(*project, static_cast<std::size_t>(multisampleIndex), SVObjectName(name), created, e)) {
        SVObjectError(error, e);
        return NO;
    }
    if (createdIndex != nullptr) *createdIndex = static_cast<NSUInteger>(created);
    if (error != nullptr) *error = nil;
    return YES;
}

@end
