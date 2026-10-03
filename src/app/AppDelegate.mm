#import <AppKit/AppKit.h>

@interface SVMainWindowController : NSWindowController
@end

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation SVAppDelegate {
    SVMainWindowController* _mainWindowController;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
    (void)notification;
    _mainWindowController = [[SVMainWindowController alloc] init];
    [_mainWindowController showWindow:self];
    [_mainWindowController.window center];
    [_mainWindowController.window makeKeyAndOrderFront:self];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
    (void)sender;
    return YES;
}

@end
