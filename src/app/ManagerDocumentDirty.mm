#import <Foundation/Foundation.h>
#import <objc/runtime.h>

#include <cstdint>

@interface SVManagerDocument : NSObject
- (BOOL)hasUnsavedChanges;
- (void)markCurrentStateSaved;
- (void)markCurrentStateChanged;
@end

namespace {
static const void* kSVDocumentDirtyKey = &kSVDocumentDirtyKey;

void SVSwizzle(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original != nullptr && replacement != nullptr) method_exchangeImplementations(original, replacement);
}
}

@implementation SVManagerDocument (DirtyTracking)

+ (void)load {
    Class cls = self;
    SVSwizzle(cls, @selector(clearProject), @selector(sv_dirty_clearProject));
    SVSwizzle(cls, @selector(importPaths:error:), @selector(sv_dirty_importPaths:error:));
    SVSwizzle(cls, @selector(buildBankAtPath:error:summary:), @selector(sv_dirty_buildBankAtPath:error:summary:));
    SVSwizzle(cls, @selector(loadBankAtPath:error:summary:), @selector(sv_dirty_loadBankAtPath:error:summary:));

    SVSwizzle(cls, @selector(trimSampleAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_trimSampleAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(setLoopForSampleAtIndex:enabled:startFrame:endFrame:error:), @selector(sv_dirty_setLoopForSampleAtIndex:enabled:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(applyLoopCrossfadeForSampleAtIndex:frames:error:), @selector(sv_dirty_applyLoopCrossfadeForSampleAtIndex:frames:error:));
    SVSwizzle(cls, @selector(reverseSampleAtIndex:error:), @selector(sv_dirty_reverseSampleAtIndex:error:));
    SVSwizzle(cls, @selector(applyGainForSampleAtIndex:gainDb:error:), @selector(sv_dirty_applyGainForSampleAtIndex:gainDb:error:));
    SVSwizzle(cls, @selector(normalizeSampleAtIndex:targetPeakDb:error:), @selector(sv_dirty_normalizeSampleAtIndex:targetPeakDb:error:));
    SVSwizzle(cls, @selector(fadeInSampleAtIndex:frames:error:), @selector(sv_dirty_fadeInSampleAtIndex:frames:error:));
    SVSwizzle(cls, @selector(fadeOutSampleAtIndex:frames:error:), @selector(sv_dirty_fadeOutSampleAtIndex:frames:error:));
    SVSwizzle(cls, @selector(setRootKeyForSampleAtIndex:rootKey:error:), @selector(sv_dirty_setRootKeyForSampleAtIndex:rootKey:error:));
    SVSwizzle(cls, @selector(setFineTuneForSampleAtIndex:cents:error:), @selector(sv_dirty_setFineTuneForSampleAtIndex:cents:error:));
    SVSwizzle(cls, @selector(setTuningForSampleAtIndex:rootKey:cents:error:), @selector(sv_dirty_setTuningForSampleAtIndex:rootKey:cents:error:));
    SVSwizzle(cls, @selector(undoSampleEdit:), @selector(sv_dirty_undoSampleEdit:));
    SVSwizzle(cls, @selector(redoSampleEdit:), @selector(sv_dirty_redoSampleEdit:));

    SVSwizzle(cls, @selector(cutSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_cutSampleRangeAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(deleteSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_deleteSampleRangeAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(silenceSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_silenceSampleRangeAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(pasteSampleRangeAtIndex:atFrame:error:), @selector(sv_dirty_pasteSampleRangeAtIndex:atFrame:error:));
    SVSwizzle(cls, @selector(reverseSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_reverseSampleRangeAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(applyGainForSampleRangeAtIndex:startFrame:endFrame:gainDb:error:), @selector(sv_dirty_applyGainForSampleRangeAtIndex:startFrame:endFrame:gainDb:error:));
    SVSwizzle(cls, @selector(normalizeSampleRangeAtIndex:startFrame:endFrame:targetPeakDb:error:), @selector(sv_dirty_normalizeSampleRangeAtIndex:startFrame:endFrame:targetPeakDb:error:));
    SVSwizzle(cls, @selector(fadeInSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_fadeInSampleRangeAtIndex:startFrame:endFrame:error:));
    SVSwizzle(cls, @selector(fadeOutSampleRangeAtIndex:startFrame:endFrame:error:), @selector(sv_dirty_fadeOutSampleRangeAtIndex:startFrame:endFrame:error:));

    SVSwizzle(cls, @selector(createMultisampleNamed:sampleIndexes:error:createdIndex:), @selector(sv_dirty_createMultisampleNamed:sampleIndexes:error:createdIndex:));
    SVSwizzle(cls, @selector(renameMultisampleAtIndex:name:error:), @selector(sv_dirty_renameMultisampleAtIndex:name:error:));
    SVSwizzle(cls, @selector(addZoneToMultisampleAtIndex:sampleIndex:error:), @selector(sv_dirty_addZoneToMultisampleAtIndex:sampleIndex:error:));
    SVSwizzle(cls, @selector(removeZoneFromMultisampleAtIndex:zoneIndex:error:), @selector(sv_dirty_removeZoneFromMultisampleAtIndex:zoneIndex:error:));
    SVSwizzle(cls, @selector(updateZoneAtMultisampleIndex:zoneIndex:sampleIndex:keyLow:keyHigh:velocityLow:velocityHigh:rootKey:transposeSemitones:tuneCents:gainDb:pan:error:), @selector(sv_dirty_updateZoneAtMultisampleIndex:zoneIndex:sampleIndex:keyLow:keyHigh:velocityLow:velocityHigh:rootKey:transposeSemitones:tuneCents:gainDb:pan:error:));

    SVSwizzle(cls, @selector(addSoundLayerAtIndex:multisampleIndex:error:), @selector(sv_dirty_addSoundLayerAtIndex:multisampleIndex:error:));
    SVSwizzle(cls, @selector(removeSoundLayerAtIndex:layerIndex:error:), @selector(sv_dirty_removeSoundLayerAtIndex:layerIndex:error:));
    SVSwizzle(cls, @selector(updateSoundLayerAtIndex:layerIndex:multisampleIndex:enabled:keyLow:keyHigh:velocityLow:velocityHigh:transposeSemitones:tuneCents:levelDb:pan:error:), @selector(sv_dirty_updateSoundLayerAtIndex:layerIndex:multisampleIndex:enabled:keyLow:keyHigh:velocityLow:velocityHigh:transposeSemitones:tuneCents:levelDb:pan:error:));
    SVSwizzle(cls, @selector(updateSoundAtIndex:name:bank:page:slot:category:error:), @selector(sv_dirty_updateSoundAtIndex:name:bank:page:slot:category:error:));
    SVSwizzle(cls, @selector(autoPackSoundAddressesFromBank:page:slot:error:), @selector(sv_dirty_autoPackSoundAddressesFromBank:page:slot:error:));

    SVSwizzle(cls, @selector(renameObjectKind:index:name:error:), @selector(sv_dirty_renameObjectKind:index:name:error:));
    SVSwizzle(cls, @selector(duplicateObjectKind:index:createdIndex:error:), @selector(sv_dirty_duplicateObjectKind:index:createdIndex:error:));
    SVSwizzle(cls, @selector(deleteObjectKind:index:summary:error:), @selector(sv_dirty_deleteObjectKind:index:summary:error:));
    SVSwizzle(cls, @selector(createSoundFromMultisampleIndex:name:createdIndex:error:), @selector(sv_dirty_createSoundFromMultisampleIndex:name:createdIndex:error:));

    SVSwizzle(cls, @selector(convertSamplesAtIndexes:sampleRate:channels:encodingChoice:dither:summary:error:), @selector(sv_dirty_convertSamplesAtIndexes:sampleRate:channels:encodingChoice:dither:summary:error:));
}

- (BOOL)hasUnsavedChanges {
    NSNumber* value = objc_getAssociatedObject(self, kSVDocumentDirtyKey);
    return value.boolValue ? YES : NO;
}

- (void)markCurrentStateSaved {
    objc_setAssociatedObject(self, kSVDocumentDirtyKey, @NO, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)markCurrentStateChanged {
    objc_setAssociatedObject(self, kSVDocumentDirtyKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sv_dirty_clearProject {
    [self sv_dirty_clearProject];
    [self markCurrentStateChanged];
}

- (BOOL)sv_dirty_importPaths:(NSArray<NSString*>*)paths error:(NSString**)error {
    BOOL ok = [self sv_dirty_importPaths:paths error:error]; if (ok) [self markCurrentStateChanged]; return ok;
}
- (BOOL)sv_dirty_buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary {
    BOOL ok = [self sv_dirty_buildBankAtPath:path error:error summary:summary]; if (ok) [self markCurrentStateSaved]; return ok;
}
- (BOOL)sv_dirty_loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary {
    BOOL ok = [self sv_dirty_loadBankAtPath:path error:error summary:summary]; if (ok) [self markCurrentStateSaved]; return ok;
}

#define SV_DIRTY_BOOL_CALL(call) do { BOOL ok = (call); if (ok) [self markCurrentStateChanged]; return ok; } while (0)

- (BOOL)sv_dirty_trimSampleAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_trimSampleAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_setLoopForSampleAtIndex:(NSUInteger)i enabled:(BOOL)enabled startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_setLoopForSampleAtIndex:i enabled:enabled startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_applyLoopCrossfadeForSampleAtIndex:(NSUInteger)i frames:(uint32_t)frames error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_applyLoopCrossfadeForSampleAtIndex:i frames:frames error:error]); }
- (BOOL)sv_dirty_reverseSampleAtIndex:(NSUInteger)i error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_reverseSampleAtIndex:i error:error]); }
- (BOOL)sv_dirty_applyGainForSampleAtIndex:(NSUInteger)i gainDb:(float)gain error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_applyGainForSampleAtIndex:i gainDb:gain error:error]); }
- (BOOL)sv_dirty_normalizeSampleAtIndex:(NSUInteger)i targetPeakDb:(float)peak error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_normalizeSampleAtIndex:i targetPeakDb:peak error:error]); }
- (BOOL)sv_dirty_fadeInSampleAtIndex:(NSUInteger)i frames:(uint64_t)frames error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_fadeInSampleAtIndex:i frames:frames error:error]); }
- (BOOL)sv_dirty_fadeOutSampleAtIndex:(NSUInteger)i frames:(uint64_t)frames error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_fadeOutSampleAtIndex:i frames:frames error:error]); }
- (BOOL)sv_dirty_setRootKeyForSampleAtIndex:(NSUInteger)i rootKey:(uint8_t)root error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_setRootKeyForSampleAtIndex:i rootKey:root error:error]); }
- (BOOL)sv_dirty_setFineTuneForSampleAtIndex:(NSUInteger)i cents:(float)cents error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_setFineTuneForSampleAtIndex:i cents:cents error:error]); }
- (BOOL)sv_dirty_setTuningForSampleAtIndex:(NSUInteger)i rootKey:(uint8_t)root cents:(float)cents error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_setTuningForSampleAtIndex:i rootKey:root cents:cents error:error]); }
- (BOOL)sv_dirty_undoSampleEdit:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_undoSampleEdit:error]); }
- (BOOL)sv_dirty_redoSampleEdit:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_redoSampleEdit:error]); }
- (BOOL)sv_dirty_cutSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_cutSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_deleteSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_deleteSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_silenceSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_silenceSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_pasteSampleRangeAtIndex:(NSUInteger)i atFrame:(uint64_t)frame error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_pasteSampleRangeAtIndex:i atFrame:frame error:error]); }
- (BOOL)sv_dirty_reverseSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_reverseSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_applyGainForSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e gainDb:(float)gain error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_applyGainForSampleRangeAtIndex:i startFrame:s endFrame:e gainDb:gain error:error]); }
- (BOOL)sv_dirty_normalizeSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e targetPeakDb:(float)peak error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_normalizeSampleRangeAtIndex:i startFrame:s endFrame:e targetPeakDb:peak error:error]); }
- (BOOL)sv_dirty_fadeInSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_fadeInSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }
- (BOOL)sv_dirty_fadeOutSampleRangeAtIndex:(NSUInteger)i startFrame:(uint64_t)s endFrame:(uint64_t)e error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_fadeOutSampleRangeAtIndex:i startFrame:s endFrame:e error:error]); }

- (BOOL)sv_dirty_createMultisampleNamed:(NSString*)name sampleIndexes:(NSIndexSet*)indexes error:(NSString**)error createdIndex:(NSUInteger*)created { SV_DIRTY_BOOL_CALL([self sv_dirty_createMultisampleNamed:name sampleIndexes:indexes error:error createdIndex:created]); }
- (BOOL)sv_dirty_renameMultisampleAtIndex:(NSUInteger)i name:(NSString*)name error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_renameMultisampleAtIndex:i name:name error:error]); }
- (BOOL)sv_dirty_addZoneToMultisampleAtIndex:(NSUInteger)m sampleIndex:(NSUInteger)s error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_addZoneToMultisampleAtIndex:m sampleIndex:s error:error]); }
- (BOOL)sv_dirty_removeZoneFromMultisampleAtIndex:(NSUInteger)m zoneIndex:(NSUInteger)z error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_removeZoneFromMultisampleAtIndex:m zoneIndex:z error:error]); }
- (BOOL)sv_dirty_updateZoneAtMultisampleIndex:(NSUInteger)m zoneIndex:(NSUInteger)z sampleIndex:(NSUInteger)s keyLow:(NSUInteger)kl keyHigh:(NSUInteger)kh velocityLow:(NSUInteger)vl velocityHigh:(NSUInteger)vh rootKey:(NSUInteger)root transposeSemitones:(NSInteger)transpose tuneCents:(float)tune gainDb:(float)gain pan:(float)pan error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_updateZoneAtMultisampleIndex:m zoneIndex:z sampleIndex:s keyLow:kl keyHigh:kh velocityLow:vl velocityHigh:vh rootKey:root transposeSemitones:transpose tuneCents:tune gainDb:gain pan:pan error:error]); }

- (BOOL)sv_dirty_addSoundLayerAtIndex:(NSUInteger)s multisampleIndex:(NSUInteger)m error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_addSoundLayerAtIndex:s multisampleIndex:m error:error]); }
- (BOOL)sv_dirty_removeSoundLayerAtIndex:(NSUInteger)s layerIndex:(NSUInteger)l error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_removeSoundLayerAtIndex:s layerIndex:l error:error]); }
- (BOOL)sv_dirty_updateSoundLayerAtIndex:(NSUInteger)s layerIndex:(NSUInteger)l multisampleIndex:(NSUInteger)m enabled:(BOOL)enabled keyLow:(NSUInteger)kl keyHigh:(NSUInteger)kh velocityLow:(NSUInteger)vl velocityHigh:(NSUInteger)vh transposeSemitones:(NSInteger)transpose tuneCents:(float)tune levelDb:(float)level pan:(float)pan error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_updateSoundLayerAtIndex:s layerIndex:l multisampleIndex:m enabled:enabled keyLow:kl keyHigh:kh velocityLow:vl velocityHigh:vh transposeSemitones:transpose tuneCents:tune levelDb:level pan:pan error:error]); }
- (BOOL)sv_dirty_updateSoundAtIndex:(NSUInteger)i name:(NSString*)name bank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot category:(NSUInteger)category error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_updateSoundAtIndex:i name:name bank:bank page:page slot:slot category:category error:error]); }
- (BOOL)sv_dirty_autoPackSoundAddressesFromBank:(NSUInteger)bank page:(NSUInteger)page slot:(NSUInteger)slot error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_autoPackSoundAddressesFromBank:bank page:page slot:slot error:error]); }

- (BOOL)sv_dirty_renameObjectKind:(NSInteger)kind index:(NSUInteger)i name:(NSString*)name error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_renameObjectKind:kind index:i name:name error:error]); }
- (BOOL)sv_dirty_duplicateObjectKind:(NSInteger)kind index:(NSUInteger)i createdIndex:(NSUInteger*)created error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_duplicateObjectKind:kind index:i createdIndex:created error:error]); }
- (BOOL)sv_dirty_deleteObjectKind:(NSInteger)kind index:(NSUInteger)i summary:(NSString**)summary error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_deleteObjectKind:kind index:i summary:summary error:error]); }
- (BOOL)sv_dirty_createSoundFromMultisampleIndex:(NSUInteger)m name:(NSString*)name createdIndex:(NSUInteger*)created error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_createSoundFromMultisampleIndex:m name:name createdIndex:created error:error]); }

- (BOOL)sv_dirty_convertSamplesAtIndexes:(NSIndexSet*)indexes sampleRate:(NSUInteger)rate channels:(NSUInteger)channels encodingChoice:(NSInteger)encoding dither:(BOOL)dither summary:(NSString**)summary error:(NSString**)error { SV_DIRTY_BOOL_CALL([self sv_dirty_convertSamplesAtIndexes:indexes sampleRate:rate channels:channels encodingChoice:encoding dither:dither summary:summary error:error]); }

#undef SV_DIRTY_BOOL_CALL

@end
