#import <AppKit/AppKit.h>

@interface SVMainWindowController : NSWindowController
@end

@interface SVManagerDocument : NSObject
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
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _mainWindowController = [[SVMainWindowController alloc] init];
    [_mainWindowController showWindow:self];
    [_mainWindowController.window center];
    [_mainWindowController.window makeKeyAndOrderFront:self];

    NSButton* multisampleButton = [[NSButton alloc] initWithFrame:NSMakeRect(840.0, 696.0, 182.0, 32.0)];
    multisampleButton.title = @"Multisample Editor…";
    multisampleButton.bezelStyle = NSBezelStyleRounded;
    multisampleButton.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    multisampleButton.target = self;
    multisampleButton.action = @selector(showMultisampleEditor:);
    multisampleButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [_mainWindowController.window.contentView addSubview:multisampleButton];

    [NSApp activateIgnoringOtherApps:YES];
}

- (void)showMultisampleEditor:(id)sender {
    (void)sender;
    if (_multisampleWindowController == nil) {
        SVManagerDocument* model = [_mainWindowController valueForKey:@"documentModel"];
        if (model == nil) {
            NSAlert* alert = [[NSAlert alloc] init];
            alert.messageText = @"Multisample Editor unavailable";
            alert.informativeText = @"The shared Manager document could not be accessed.";
            alert.alertStyle = NSAlertStyleCritical;
            [alert runModal];
            return;
        }
        _multisampleWindowController = [[SVMultisampleWindowController alloc] initWithDocumentModel:model];
    }
    [_multisampleWindowController refreshFromDocument];
    [_multisampleWindowController showWindow:self];
    [_multisampleWindowController.window center];
    [_multisampleWindowController.window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

@end
