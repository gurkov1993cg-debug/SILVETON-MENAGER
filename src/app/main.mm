#import <AppKit/AppKit.h>

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
- (void)newBankCommand:(id)sender;
- (void)openBankCommand:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)saveBankAsCommand:(id)sender;
- (void)showSampleEditorCommand:(id)sender;
- (void)showMediaCommand:(id)sender;
- (void)showMultisampleEditor:(id)sender;
- (void)showSoundEditor:(id)sender;
- (void)showBankOrganizer:(id)sender;
- (void)showObjectManagerCommand:(id)sender;
- (void)showConverterCommand:(id)sender;
- (void)showWorkflowCommand:(id)sender;
@end

namespace {

NSMenuItem* AddMenuCommand(NSMenu* menu,
                           NSString* title,
                           SEL action,
                           NSString* keyEquivalent,
                           NSEventModifierFlags modifiers,
                           id target) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:keyEquivalent ?: @""];
    item.target = target;
    if (keyEquivalent.length > 0U) item.keyEquivalentModifierMask = modifiers;
    [menu addItem:item];
    return item;
}

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

    AddMenuCommand(fileMenu, @"New SILVETON Bank", @selector(newBankCommand:), @"n", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(fileMenu, @"Open SILVETON Bank…", @selector(openBankCommand:), @"o", NSEventModifierFlagCommand, delegate);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(fileMenu, @"Save Bank", @selector(saveBankCommand:), @"s", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(fileMenu, @"Save Bank As…", @selector(saveBankAsCommand:), @"S", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(fileMenu, @"MEDIA Browser…", @selector(showMediaCommand:), @"M", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    AddMenuCommand(fileMenu, @"Object Manager…", @selector(showObjectManagerCommand:), @"J", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    AddMenuCommand(fileMenu, @"Sample Converter…", @selector(showConverterCommand:), @"K", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);

    NSMenuItem* workspaceItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:workspaceItem];
    NSMenu* workspaceMenu = [[NSMenu alloc] initWithTitle:@"Workspace"];
    workspaceItem.submenu = workspaceMenu;

    AddMenuCommand(workspaceMenu, @"Samples / Sample Editor", @selector(showSampleEditorCommand:), @"1", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"MEDIA / Import", @selector(showMediaCommand:), @"2", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"Multisample Editor", @selector(showMultisampleEditor:), @"3", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"SOUND Editor", @selector(showSoundEditor:), @"4", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"Bank Organizer", @selector(showBankOrganizer:), @"5", NSEventModifierFlagCommand, delegate);
    [workspaceMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(workspaceMenu, @"Object Manager", @selector(showObjectManagerCommand:), @"", 0, delegate);
    AddMenuCommand(workspaceMenu, @"Sample Converter", @selector(showConverterCommand:), @"", 0, delegate);
    AddMenuCommand(workspaceMenu, @"Guided Workflow", @selector(showWorkflowCommand:), @"0", NSEventModifierFlagCommand, delegate);
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
