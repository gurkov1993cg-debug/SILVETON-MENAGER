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
- (void)undoSampleEdit:(id)sender;
- (void)redoSampleEdit:(id)sender;
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

NSMenu* AddTopLevelMenu(NSMenu* mainMenu, NSString* title) {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    [mainMenu addItem:item];
    NSMenu* menu = [[NSMenu alloc] initWithTitle:title ?: @""];
    item.submenu = menu;
    return menu;
}

void InstallMainMenu(NSApplication* app, SVAppDelegate* delegate) {
    NSMenu* mainMenu = [[NSMenu alloc] initWithTitle:@""];
    app.mainMenu = mainMenu;

    NSMenu* applicationMenu = AddTopLevelMenu(mainMenu, @"SILVETON Manager");
    AddMenuCommand(applicationMenu, @"About SILVETON Manager", @selector(orderFrontStandardAboutPanel:), @"", 0, app);
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(applicationMenu, @"Hide SILVETON Manager", @selector(hide:), @"h", NSEventModifierFlagCommand, app);
    AddMenuCommand(applicationMenu, @"Hide Others", @selector(hideOtherApplications:), @"h", NSEventModifierFlagCommand | NSEventModifierFlagOption, app);
    AddMenuCommand(applicationMenu, @"Show All", @selector(unhideAllApplications:), @"", 0, app);
    [applicationMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(applicationMenu, @"Quit SILVETON Manager", @selector(terminate:), @"q", NSEventModifierFlagCommand, app);

    NSMenu* fileMenu = AddTopLevelMenu(mainMenu, @"File");
    AddMenuCommand(fileMenu, @"New SILVETON Bank", @selector(newBankCommand:), @"n", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(fileMenu, @"Open SILVETON Bank…", @selector(openBankCommand:), @"o", NSEventModifierFlagCommand, delegate);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(fileMenu, @"Save Bank", @selector(saveBankCommand:), @"s", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(fileMenu, @"Save Bank As…", @selector(saveBankAsCommand:), @"S", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    [fileMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(fileMenu, @"MEDIA Browser…", @selector(showMediaCommand:), @"M", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);

    NSMenu* editMenu = AddTopLevelMenu(mainMenu, @"Edit");
    AddMenuCommand(editMenu, @"Undo Sample Edit", @selector(undoSampleEdit:), @"z", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(editMenu, @"Redo Sample Edit", @selector(redoSampleEdit:), @"Z", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    [editMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(editMenu, @"Cut", @selector(cut:), @"x", NSEventModifierFlagCommand, nil);
    AddMenuCommand(editMenu, @"Copy", @selector(copy:), @"c", NSEventModifierFlagCommand, nil);
    AddMenuCommand(editMenu, @"Paste", @selector(paste:), @"v", NSEventModifierFlagCommand, nil);
    AddMenuCommand(editMenu, @"Select All", @selector(selectAll:), @"a", NSEventModifierFlagCommand, nil);

    NSMenu* workspaceMenu = AddTopLevelMenu(mainMenu, @"Workspace");
    AddMenuCommand(workspaceMenu, @"Samples / Sample Editor", @selector(showSampleEditorCommand:), @"1", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"MEDIA / Import", @selector(showMediaCommand:), @"2", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"Multisample Editor", @selector(showMultisampleEditor:), @"3", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"SOUND Editor", @selector(showSoundEditor:), @"4", NSEventModifierFlagCommand, delegate);
    AddMenuCommand(workspaceMenu, @"Bank Organizer", @selector(showBankOrganizer:), @"5", NSEventModifierFlagCommand, delegate);
    [workspaceMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(workspaceMenu, @"Guided Workflow", @selector(showWorkflowCommand:), @"0", NSEventModifierFlagCommand, delegate);

    NSMenu* toolsMenu = AddTopLevelMenu(mainMenu, @"Tools");
    AddMenuCommand(toolsMenu, @"Object Manager…", @selector(showObjectManagerCommand:), @"J", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);
    AddMenuCommand(toolsMenu, @"Sample Converter…", @selector(showConverterCommand:), @"K", NSEventModifierFlagCommand | NSEventModifierFlagShift, delegate);

    NSMenu* windowMenu = AddTopLevelMenu(mainMenu, @"Window");
    AddMenuCommand(windowMenu, @"Minimize", @selector(performMiniaturize:), @"m", NSEventModifierFlagCommand, nil);
    AddMenuCommand(windowMenu, @"Zoom", @selector(performZoom:), @"", 0, nil);
    [windowMenu addItem:[NSMenuItem separatorItem]];
    AddMenuCommand(windowMenu, @"Bring All to Front", @selector(arrangeInFront:), @"", 0, app);
    app.windowsMenu = windowMenu;

    NSMenu* helpMenu = AddTopLevelMenu(mainMenu, @"Help");
    AddMenuCommand(helpMenu, @"SILVETON Workflow Help", @selector(showWorkflowCommand:), @"?", NSEventModifierFlagCommand, delegate);
    app.helpMenu = helpMenu;
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
