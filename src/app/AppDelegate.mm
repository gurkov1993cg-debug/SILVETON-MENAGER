#import <AppKit/AppKit.h>

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
@end

@interface SVSampleAuditionPlayer : NSObject
- (BOOL)playState:(NSDictionary<NSString*, id>*)state loopOnly:(BOOL)loopOnly error:(NSString**)error;
- (void)stop;
@end

@interface SVMultisampleWindowController : NSWindowController
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation SVAppDelegate {
    SVMainWindowController* _mainWindowController;
    SVMultisampleWindowController* _multisampleWindowController;
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

- (SVManagerDocument*)documentModel {
    return [_mainWindowController valueForKey:@"documentModel"];
}

- (void)showMessage:(NSString*)title text:(NSString*)text style:(NSAlertStyle)style {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Manager";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    if (_mainWindowController.window != nil) {
        [alert beginSheetModalForWindow:_mainWindowController.window completionHandler:nil];
    } else {
        [alert runModal];
    }
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

    NSButton* multisampleButton = [self toolbarButtonWithFrame:NSMakeRect(840.0, 696.0, 182.0, 32.0)
                                                          title:@"Multisample Editor…"
                                                         action:@selector(showMultisampleEditor:)];
    multisampleButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:multisampleButton];

    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)selectedSampleState:(NSDictionary<NSString*, id>**)stateOut {
    const NSUInteger index = [_mainWindowController selectedSampleIndex];
    if (index == NSNotFound) {
        [self showMessage:@"No sample selected" text:@"Select a sample first." style:NSAlertStyleWarning];
        return NO;
    }
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
    if (![_auditionPlayer playState:state loopOnly:NO error:&error]) {
        [self showMessage:@"Playback failed" text:error style:NSAlertStyleCritical];
    }
}

- (void)playLoop:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* state = nil;
    if (![self selectedSampleState:&state]) return;
    NSString* error = nil;
    if (![_auditionPlayer playState:state loopOnly:YES error:&error]) {
        [self showMessage:@"Loop playback failed" text:error style:NSAlertStyleWarning];
    }
}

- (void)stopAudition:(id)sender {
    (void)sender;
    [_auditionPlayer stop];
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
    [_mainWindowController refreshProjectView];
    [_multisampleWindowController refreshFromDocument];
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
    [_mainWindowController refreshProjectView];
    [_multisampleWindowController refreshFromDocument];
}

- (void)showMultisampleEditor:(id)sender {
    (void)sender;
    if (_multisampleWindowController == nil) {
        SVManagerDocument* model = [self documentModel];
        if (model == nil) {
            [self showMessage:@"Multisample Editor unavailable"
                         text:@"The shared Manager document could not be accessed."
                        style:NSAlertStyleCritical];
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
