#import <AppKit/AppKit.h>

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
- (void)newBankCommand:(id)sender;
- (void)openBankCommand:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)saveBankAsCommand:(id)sender;
- (void)showMediaCommand:(id)sender;
- (void)showObjectManagerCommand:(id)sender;
- (void)showConverterCommand:(id)sender;
@end

namespace {

void InstallMainMenu(NSApplication* app, SVAppDelegate* delegate) {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];
    app.mainMenu = mainMenu;

    NSMenuItem* applicationItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:applicationItem];
    NSMenu* applicationMenu = [[NSMenu alloc] initWithTitle:@"SILVETON Manager"];
    applicationItem.submenu = applicationMenu;
    NSMenuItem* quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit SILVETON Manager"
                                                     action:@selector(terminate:)
                                              keyEquivalent:@"q"];
    quitItem.target = app;
    [applicationMenu addItem:quitItem];

    NSMenuItem* fileItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:fileItem];
    NSMenu* fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    fileItem.submenu = fileMenu;

    NSMenuItem* newItem = [[NSMenuItem alloc] initWithTitle:@"New SILVETON Bank"
                                                    action:@selector(newBankCommand:)
                                             keyEquivalent:@"n"];
    newItem.target = delegate;
    [fileMenu addItem:newItem];

    NSMenuItem* openItem = [[NSMenuItem alloc] initWithTitle:@"Open SILVETON Bank…"
                                                     action:@selector(openBankCommand:)
                                              keyEquivalent:@"o"];
    openItem.target = delegate;
    [fileMenu addItem:openItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* saveItem = [[NSMenuItem alloc] initWithTitle:@"Save Bank"
                                                     action:@selector(saveBankCommand:)
                                              keyEquivalent:@"s"];
    saveItem.target = delegate;
    [fileMenu addItem:saveItem];

    NSMenuItem* saveAsItem = [[NSMenuItem alloc] initWithTitle:@"Save Bank As…"
                                                       action:@selector(saveBankAsCommand:)
                                                keyEquivalent:@"S"];
    saveAsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    saveAsItem.target = delegate;
    [fileMenu addItem:saveAsItem];

    [fileMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* mediaItem = [[NSMenuItem alloc] initWithTitle:@"MEDIA Browser…"
                                                      action:@selector(showMediaCommand:)
                                               keyEquivalent:@"M"];
    mediaItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    mediaItem.target = delegate;
    [fileMenu addItem:mediaItem];

    NSMenuItem* objectItem = [[NSMenuItem alloc] initWithTitle:@"Object Manager…"
                                                       action:@selector(showObjectManagerCommand:)
                                                keyEquivalent:@"J"];
    objectItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    objectItem.target = delegate;
    [fileMenu addItem:objectItem];

    NSMenuItem* converterItem = [[NSMenuItem alloc] initWithTitle:@"Sample Converter…"
                                                          action:@selector(showConverterCommand:)
                                                   keyEquivalent:@"K"];
    converterItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    converterItem.target = delegate;
    [fileMenu addItem:converterItem];
}

} // namespace

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        SVAppDelegate* delegate = [[SVAppDelegate alloc] init];
        app.delegate = delegate;
        InstallMainMenu(app, delegate);

        [app run];
        app.delegate = nil;
        (void)delegate;
    }
    return 0;
}
