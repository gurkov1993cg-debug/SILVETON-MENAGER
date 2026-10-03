#import <AppKit/AppKit.h>

#include <cmath>
#include <cstdint>

@interface SVMainWindowController : NSWindowController
- (NSUInteger)selectedSampleIndex;
- (void)refreshProjectView;
@end

@interface SVManagerDocument : NSObject
- (NSDictionary<NSString*, id>*)auditionStateAtIndex:(NSUInteger)index error:(NSString**)error;
- (BOOL)canUndoSampleEdit;
- (BOOL)canRedoSampleEdit;
- (BOOL)undoSampleEdit:(NSString**)error;
- (BOOL)redoSampleEdit:(NSString**)error;
- (BOOL)copySampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)cutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)deleteSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)silenceSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)pasteSampleRangeAtIndex:(NSUInteger)index atFrame:(uint64_t)atFrame error:(NSString**)error;
- (BOOL)reverseSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)applyGainForSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame gainDb:(float)gainDb error:(NSString**)error;
- (BOOL)normalizeSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame targetPeakDb:(float)targetPeakDb error:(NSString**)error;
- (BOOL)fadeInSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)fadeOutSampleRangeAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (NSString*)sampleClipboardSummary;
@end

@interface SVSampleAuditionPlayer : NSObject
- (BOOL)playState:(NSDictionary<NSString*, id>*)state loopOnly:(BOOL)loopOnly error:(NSString**)error;
- (void)stop;
@end

@interface SVMultisampleWindowController : NSWindowController
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@interface SVBankOrganizerWindowController : NSWindowController
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@interface SVSoundEditorWindowController : NSWindowController
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation SVAppDelegate {
    SVMainWindowController* _mainWindowController;
    SVMultisampleWindowController* _multisampleWindowController;
    SVBankOrganizerWindowController* _bankOrganizerWindowController;
    SVSoundEditorWindowController* _soundEditorWindowController;
    SVSampleAuditionPlayer* _auditionPlayer;
}

- (NSButton*)toolbarButtonWithFrame:(NSRect)frame title:(NSString*)title action:(SEL)action {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    button.target = self;
    button.action = action;
    button.autoresizingMask = NSViewMinYMargin;
    return button;
}

- (NSTextField*)smallLabelWithFrame:(NSRect)frame text:(NSString*)text {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:10.5 weight:NSFontWeightRegular];
    label.textColor = [NSColor colorWithCalibratedWhite:0.58 alpha:1.0];
    return label;
}

- (SVManagerDocument*)documentModel {
    return [_mainWindowController valueForKey:@"documentModel"];
}

- (void)showMessage:(NSString*)title text:(NSString*)text style:(NSAlertStyle)style {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Manager";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    if (_mainWindowController.window != nil) [alert beginSheetModalForWindow:_mainWindowController.window completionHandler:nil];
    else [alert runModal];
}

- (void)refreshAllEditors {
    [_mainWindowController refreshProjectView];
    [_multisampleWindowController refreshFromDocument];
    [_bankOrganizerWindowController refreshFromDocument];
    [_soundEditorWindowController refreshFromDocument];
}

- (BOOL)parseUnsignedField:(NSTextField*)field label:(NSString*)label value:(uint64_t*)valueOut {
    if (field == nil) return NO;
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0U || [text hasPrefix:@"-"]) {
        [self showMessage:@"Invalid edit range" text:[NSString stringWithFormat:@"%@ must be a non-negative whole number.", label] style:NSAlertStyleWarning];
        return NO;
    }
    NSScanner* scanner = [NSScanner scannerWithString:text];
    unsigned long long parsed = 0ULL;
    if (![scanner scanUnsignedLongLong:&parsed] || !scanner.isAtEnd) {
        [self showMessage:@"Invalid edit range" text:[NSString stringWithFormat:@"%@ must be a non-negative whole number.", label] style:NSAlertStyleWarning];
        return NO;
    }
    if (valueOut != nullptr) *valueOut = static_cast<uint64_t>(parsed);
    return YES;
}

- (BOOL)readEditRangeStart:(uint64_t*)startOut end:(uint64_t*)endOut {
    NSTextField* startField = [_mainWindowController valueForKey:@"trimStartField"];
    NSTextField* endField = [_mainWindowController valueForKey:@"trimEndField"];
    uint64_t startFrame = 0U;
    uint64_t endFrame = 0U;
    if (![self parseUnsignedField:startField label:@"Range Start" value:&startFrame] ||
        ![self parseUnsignedField:endField label:@"Range End" value:&endFrame]) return NO;
    if (startFrame >= endFrame) {
        [self showMessage:@"Invalid edit range" text:@"Range Start must be before Range End." style:NSAlertStyleWarning];
        return NO;
    }
    if (startOut != nullptr) *startOut = startFrame;
    if (endOut != nullptr) *endOut = endFrame;
    return YES;
}

- (BOOL)readFloatFieldKey:(NSString*)key label:(NSString*)label value:(float*)valueOut {
    NSTextField* field = [_mainWindowController valueForKey:key];
    if (field == nil) return NO;
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSScanner* scanner = [NSScanner scannerWithString:text];
    double parsed = 0.0;
    if (text.length == 0U || ![scanner scanDouble:&parsed] || !scanner.isAtEnd || !std::isfinite(parsed)) {
        [self showMessage:@"Invalid value" text:[NSString stringWithFormat:@"%@ must be a valid number.", label] style:NSAlertStyleWarning];
        return NO;
    }
    if (valueOut != nullptr) *valueOut = static_cast<float>(parsed);
    return YES;
}

- (BOOL)selectedSampleIndex:(NSUInteger*)indexOut {
    const NSUInteger index = [_mainWindowController selectedSampleIndex];
    if (index == NSNotFound) {
        [self showMessage:@"No sample selected" text:@"Select a sample first." style:NSAlertStyleWarning];
        return NO;
    }
    if (indexOut != nullptr) *indexOut = index;
    return YES;
}

- (void)finishRangeMutation:(BOOL)ok error:(NSString*)error title:(NSString*)title {
    if (ok != YES) {
        [self showMessage:title text:error ?: @"Sample edit failed." style:NSAlertStyleWarning];
        return;
    }
    [_auditionPlayer stop];
    [self refreshAllEditors];
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _mainWindowController = [[SVMainWindowController alloc] init];
    _auditionPlayer = [[SVSampleAuditionPlayer alloc] init];
    [_mainWindowController showWindow:self];
    [_mainWindowController.window center];
    [_mainWindowController.window makeKeyAndOrderFront:self];

    NSView* content = _mainWindowController.window.contentView;
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(300.0, 696.0, 70.0, 32.0) title:@"Play" action:@selector(playSample:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(378.0, 696.0, 94.0, 32.0) title:@"Play Loop" action:@selector(playLoop:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(480.0, 696.0, 70.0, 32.0) title:@"Stop" action:@selector(stopAudition:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(558.0, 696.0, 74.0, 32.0) title:@"Undo" action:@selector(undoSampleEdit:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(640.0, 696.0, 74.0, 32.0) title:@"Redo" action:@selector(redoSampleEdit:)]];

    NSButton* bankButton = [self toolbarButtonWithFrame:NSMakeRect(720.0, 696.0, 78.0, 32.0) title:@"Bank…" action:@selector(showBankOrganizer:)];
    bankButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:bankButton];

    NSButton* soundButton = [self toolbarButtonWithFrame:NSMakeRect(802.0, 696.0, 96.0, 32.0) title:@"SOUND…" action:@selector(showSoundEditor:)];
    soundButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:soundButton];

    NSButton* multisampleButton = [self toolbarButtonWithFrame:NSMakeRect(902.0, 696.0, 126.0, 32.0) title:@"Multisample…" action:@selector(showMultisampleEditor:)];
    multisampleButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:multisampleButton];

    [content addSubview:[self smallLabelWithFrame:NSMakeRect(382.0, 136.0, 840.0, 18.0)
                                                  text:@"EDIT RANGE = TRIM Start/End (Option-drag waveform sets it). Paste inserts at Range Start; nothing runs without a button press."]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(382.0, 108.0, 88.0, 26.0) title:@"Play Range" action:@selector(playRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(474.0, 108.0, 58.0, 26.0) title:@"Copy" action:@selector(copyRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(536.0, 108.0, 52.0, 26.0) title:@"Cut" action:@selector(cutRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(592.0, 108.0, 92.0, 26.0) title:@"Paste @ Start" action:@selector(pasteRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(688.0, 108.0, 64.0, 26.0) title:@"Delete" action:@selector(deleteRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(756.0, 108.0, 70.0, 26.0) title:@"Silence" action:@selector(silenceRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(830.0, 108.0, 76.0, 26.0) title:@"Reverse" action:@selector(reverseRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(910.0, 108.0, 70.0, 26.0) title:@"Fade In" action:@selector(fadeInRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(984.0, 108.0, 76.0, 26.0) title:@"Fade Out" action:@selector(fadeOutRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(1064.0, 108.0, 76.0, 26.0) title:@"Gain Rng" action:@selector(gainRange:)]];
    [content addSubview:[self toolbarButtonWithFrame:NSMakeRect(1144.0, 108.0, 88.0, 26.0) title:@"Normalize Rng" action:@selector(normalizeRange:)]];

    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)selectedSampleState:(NSDictionary<NSString*, id>**)stateOut {
    NSUInteger index = 0U;
    if (![self selectedSampleIndex:&index]) return NO;
    NSString* error = nil;
    NSDictionary<NSString*, id>* state = [[self documentModel] auditionStateAtIndex:index error:&error];
    if (state == nil) {
        [self showMessage:@"Audition unavailable" text:error style:NSAlertStyleCritical];
        return NO;
    }
    if (stateOut != nullptr) *stateOut = state;
    return YES;
}

- (void)playSample:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* state = nil;
    if (![self selectedSampleState:&state]) return;
    NSString* error = nil;
    if (![_auditionPlayer playState:state loopOnly:NO error:&error]) [self showMessage:@"Playback failed" text:error style:NSAlertStyleCritical];
}

- (void)playLoop:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* state = nil;
    if (![self selectedSampleState:&state]) return;
    NSString* error = nil;
    if (![_auditionPlayer playState:state loopOnly:YES error:&error]) [self showMessage:@"Loop playback failed" text:error style:NSAlertStyleWarning];
}

- (void)playRange:(id)sender {
    (void)sender;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSDictionary<NSString*, id>* state = nil;
    if (![self selectedSampleState:&state]) return;
    const uint64_t totalFrames = [state[@"totalFrames"] unsignedLongLongValue];
    if (endFrame > totalFrames) {
        [self showMessage:@"Play Range" text:@"Range End is beyond the sample length." style:NSAlertStyleWarning];
        return;
    }
    const unsigned int channels = [state[@"channels"] unsignedIntValue];
    const unsigned int encoding = [state[@"encoding"] unsignedIntValue];
    const NSUInteger bytesPerSample = encoding == 1U ? 2U : (encoding == 2U ? 3U : (encoding == 3U ? 4U : 0U));
    NSData* audio = state[@"audioData"];
    if (bytesPerSample == 0U || audio == nil) {
        [self showMessage:@"Play Range" text:@"Unsupported sample encoding." style:NSAlertStyleWarning];
        return;
    }
    const NSUInteger bytesPerFrame = bytesPerSample * static_cast<NSUInteger>(channels);
    const uint64_t frameCount = endFrame - startFrame;
    const uint64_t byteStart64 = startFrame * static_cast<uint64_t>(bytesPerFrame);
    const uint64_t byteCount64 = frameCount * static_cast<uint64_t>(bytesPerFrame);
    if (byteStart64 + byteCount64 > static_cast<uint64_t>(audio.length)) {
        [self showMessage:@"Play Range" text:@"Selected audio range is invalid." style:NSAlertStyleWarning];
        return;
    }
    NSData* sliced = [audio subdataWithRange:NSMakeRange(static_cast<NSUInteger>(byteStart64), static_cast<NSUInteger>(byteCount64))];
    NSMutableDictionary<NSString*, id>* ranged = [state mutableCopy];
    ranged[@"audioData"] = sliced;
    ranged[@"totalFrames"] = @(frameCount);
    ranged[@"loopEnabled"] = @NO;
    ranged[@"loopStart"] = @0ULL;
    ranged[@"loopEnd"] = @0ULL;
    NSString* error = nil;
    if (![_auditionPlayer playState:ranged loopOnly:NO error:&error]) [self showMessage:@"Play Range failed" text:error style:NSAlertStyleWarning];
}

- (void)stopAudition:(id)sender { (void)sender; [_auditionPlayer stop]; }

- (void)copyRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    if (![[self documentModel] copySampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error]) {
        [self showMessage:@"Copy Range" text:error style:NSAlertStyleWarning];
        return;
    }
    NSTextField* status = [_mainWindowController valueForKey:@"statusLabel"];
    if (status != nil) status.stringValue = [[self documentModel] sampleClipboardSummary];
}

- (void)cutRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] cutSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Cut Range"];
}

- (void)pasteRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    (void)endFrame;
    NSString* error = nil;
    BOOL ok = [[self documentModel] pasteSampleRangeAtIndex:index atFrame:startFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Paste Range"];
}

- (void)deleteRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] deleteSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Delete Range"];
}

- (void)silenceRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] silenceSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Silence Range"];
}

- (void)reverseRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] reverseSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Reverse Range"];
}

- (void)fadeInRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] fadeInSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Fade In Range"];
}

- (void)fadeOutRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] fadeOutSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishRangeMutation:ok error:error title:@"Fade Out Range"];
}

- (void)gainRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    float gainDb = 0.0F;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame] ||
        ![self readFloatFieldKey:@"gainField" label:@"Gain dB" value:&gainDb]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] applyGainForSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame gainDb:gainDb error:&error];
    [self finishRangeMutation:ok error:error title:@"Gain Range"];
}

- (void)normalizeRange:(id)sender {
    (void)sender;
    NSUInteger index = 0U;
    uint64_t startFrame = 0U, endFrame = 0U;
    float targetDb = 0.0F;
    if (![self selectedSampleIndex:&index] || ![self readEditRangeStart:&startFrame end:&endFrame] ||
        ![self readFloatFieldKey:@"normalizeField" label:@"Normalize dBFS" value:&targetDb]) return;
    NSString* error = nil;
    BOOL ok = [[self documentModel] normalizeSampleRangeAtIndex:index startFrame:startFrame endFrame:endFrame targetPeakDb:targetDb error:&error];
    [self finishRangeMutation:ok error:error title:@"Normalize Range"];
}

- (void)undoSampleEdit:(id)sender {
    (void)sender;
    [_auditionPlayer stop];
    SVManagerDocument* model = [self documentModel];
    NSString* error = nil;
    if (![model undoSampleEdit:&error]) {
        [self showMessage:@"Undo" text:error style:NSAlertStyleInformational];
        return;
    }
    [self refreshAllEditors];
}

- (void)redoSampleEdit:(id)sender {
    (void)sender;
    [_auditionPlayer stop];
    SVManagerDocument* model = [self documentModel];
    NSString* error = nil;
    if (![model redoSampleEdit:&error]) {
        [self showMessage:@"Redo" text:error style:NSAlertStyleInformational];
        return;
    }
    [self refreshAllEditors];
}

- (void)showBankOrganizer:(id)sender {
    (void)sender;
    if (_bankOrganizerWindowController == nil) {
        SVManagerDocument* model = [self documentModel];
        if (model == nil) {
            [self showMessage:@"Bank Organizer unavailable" text:@"The shared Manager document could not be accessed." style:NSAlertStyleCritical];
            return;
        }
        _bankOrganizerWindowController = [[SVBankOrganizerWindowController alloc] initWithDocumentModel:model];
    }
    [_bankOrganizerWindowController refreshFromDocument];
    [_bankOrganizerWindowController showWindow:self];
    [_bankOrganizerWindowController.window center];
    [_bankOrganizerWindowController.window makeKeyAndOrderFront:self];
}

- (void)showSoundEditor:(id)sender {
    (void)sender;
    if (_soundEditorWindowController == nil) {
        SVManagerDocument* model = [self documentModel];
        if (model == nil) {
            [self showMessage:@"SOUND Editor unavailable" text:@"The shared Manager document could not be accessed." style:NSAlertStyleCritical];
            return;
        }
        _soundEditorWindowController = [[SVSoundEditorWindowController alloc] initWithDocumentModel:model];
    }
    [_soundEditorWindowController refreshFromDocument];
    [_soundEditorWindowController showWindow:self];
    [_soundEditorWindowController.window center];
    [_soundEditorWindowController.window makeKeyAndOrderFront:self];
}

- (void)showMultisampleEditor:(id)sender {
    (void)sender;
    if (_multisampleWindowController == nil) {
        SVManagerDocument* model = [self documentModel];
        if (model == nil) {
            [self showMessage:@"Multisample Editor unavailable" text:@"The shared Manager document could not be accessed." style:NSAlertStyleCritical];
            return;
        }
        _multisampleWindowController = [[SVMultisampleWindowController alloc] initWithDocumentModel:model];
    }
    [_multisampleWindowController refreshFromDocument];
    [_multisampleWindowController showWindow:self];
    [_multisampleWindowController.window center];
    [_multisampleWindowController.window makeKeyAndOrderFront:self];
}

- (void)applicationWillTerminate:(NSNotification*)notification {
    (void)notification;
    [_auditionPlayer stop];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

@end
