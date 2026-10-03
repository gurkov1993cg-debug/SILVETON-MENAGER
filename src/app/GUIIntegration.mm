#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
- (void)showMediaCommand:(id)sender;
- (void)showObjectManagerCommand:(id)sender;
- (void)showConverterCommand:(id)sender;
- (void)showMultisampleEditor:(id)sender;
- (void)showSoundEditor:(id)sender;
- (void)showBankOrganizer:(id)sender;
- (void)showWorkflowCommand:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)showSampleEditorCommand:(id)sender;
@end

@interface SVGUIBridge : NSObject <NSToolbarDelegate>
- (instancetype)initWithDelegate:(SVAppDelegate*)delegate;
- (void)installOnMainWindow;
@end

namespace {
static const void* kSVGUIBridgeKey = &kSVGUIBridgeKey;

NSString* const kSamplesItem = @"silveton.gui.samples";
NSString* const kMediaItem = @"silveton.gui.media";
NSString* const kMultisampleItem = @"silveton.gui.multisample";
NSString* const kSoundItem = @"silveton.gui.sound";
NSString* const kBankItem = @"silveton.gui.bank";
NSString* const kObjectsItem = @"silveton.gui.objects";
NSString* const kConverterItem = @"silveton.gui.converter";
NSString* const kWorkflowItem = @"silveton.gui.workflow";
NSString* const kSaveItem = @"silveton.gui.save";

NSButton* SVToolbarButton(NSString* title, id target, SEL action, CGFloat width) {
    NSButton* button = [[NSButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 26.0)];
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleTexturedRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightMedium];
    return button;
}

id SVMainController(SVAppDelegate* delegate) {
    return [delegate valueForKey:@"mainWindowController"];
}

void SVInstallGUIWhenReady(void) {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* note) {
        (void)note;
        id delegateObject = NSApp.delegate;
        if (delegateObject == nil || ![delegateObject isKindOfClass:NSClassFromString(@"SVAppDelegate")]) return;
        SVAppDelegate* delegate = (SVAppDelegate*)delegateObject;
        SVGUIBridge* bridge = [[SVGUIBridge alloc] initWithDelegate:delegate];
        objc_setAssociatedObject(delegate, kSVGUIBridgeKey, bridge, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [bridge installOnMainWindow];
    }];
}
}

@implementation SVGUIBridge {
    __weak SVAppDelegate* _delegate;
}

- (instancetype)initWithDelegate:(SVAppDelegate*)delegate {
    self = [super init];
    if (self) _delegate = delegate;
    return self;
}

- (void)installOnMainWindow {
    id main = SVMainController(_delegate);
    if (main == nil || ![main respondsToSelector:@selector(window)]) return;
    NSWindow* window = [main window];
    if (window == nil) return;

    NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"SILVETONManagerWorkspaceToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.sizeMode = NSToolbarSizeModeSmall;
    window.toolbar = toolbar;
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarAllowedItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[kSamplesItem, kMediaItem, kMultisampleItem, kSoundItem, kBankItem,
             kObjectsItem, kConverterItem, kWorkflowItem, NSToolbarFlexibleSpaceItemIdentifier, kSaveItem];
}

- (NSArray<NSToolbarItemIdentifier>*)toolbarDefaultItemIdentifiers:(NSToolbar*)toolbar {
    (void)toolbar;
    return @[kSamplesItem, kMediaItem, kMultisampleItem, kSoundItem, kBankItem,
             NSToolbarFlexibleSpaceItemIdentifier, kObjectsItem, kConverterItem, kWorkflowItem,
             NSToolbarFlexibleSpaceItemIdentifier, kSaveItem];
}

- (NSToolbarItem*)toolbar:(NSToolbar*)toolbar
   itemForItemIdentifier:(NSToolbarItemIdentifier)itemIdentifier
willBeInsertedIntoToolbar:(BOOL)flag {
    (void)toolbar;
    (void)flag;
    NSToolbarItem* item = [[NSToolbarItem alloc] initWithItemIdentifier:itemIdentifier];

    if ([itemIdentifier isEqualToString:kSamplesItem]) {
        item.view = SVToolbarButton(@"SAMPLES", self, @selector(samples:), 84.0);
        item.label = @"Samples";
    } else if ([itemIdentifier isEqualToString:kMediaItem]) {
        item.view = SVToolbarButton(@"MEDIA", self, @selector(media:), 72.0);
        item.label = @"MEDIA";
    } else if ([itemIdentifier isEqualToString:kMultisampleItem]) {
        item.view = SVToolbarButton(@"MULTISAMPLE", self, @selector(multisample:), 104.0);
        item.label = @"Multisample";
    } else if ([itemIdentifier isEqualToString:kSoundItem]) {
        item.view = SVToolbarButton(@"SOUND", self, @selector(sound:), 72.0);
        item.label = @"SOUND";
    } else if ([itemIdentifier isEqualToString:kBankItem]) {
        item.view = SVToolbarButton(@"BANK", self, @selector(bank:), 66.0);
        item.label = @"Bank";
    } else if ([itemIdentifier isEqualToString:kObjectsItem]) {
        item.view = SVToolbarButton(@"OBJECTS", self, @selector(objects:), 82.0);
        item.label = @"Objects";
    } else if ([itemIdentifier isEqualToString:kConverterItem]) {
        item.view = SVToolbarButton(@"CONVERTER", self, @selector(converter:), 94.0);
        item.label = @"Converter";
    } else if ([itemIdentifier isEqualToString:kWorkflowItem]) {
        item.view = SVToolbarButton(@"WORKFLOW", self, @selector(workflow:), 90.0);
        item.label = @"Workflow";
    } else if ([itemIdentifier isEqualToString:kSaveItem]) {
        item.view = SVToolbarButton(@"SAVE BANK", self, @selector(save:), 88.0);
        item.label = @"Save Bank";
    }
    return item;
}

- (void)samples:(id)sender { [_delegate showSampleEditorCommand:sender]; }
- (void)media:(id)sender { [_delegate showMediaCommand:sender]; }
- (void)multisample:(id)sender { [_delegate showMultisampleEditor:sender]; }
- (void)sound:(id)sender { [_delegate showSoundEditor:sender]; }
- (void)bank:(id)sender { [_delegate showBankOrganizer:sender]; }
- (void)objects:(id)sender { [_delegate showObjectManagerCommand:sender]; }
- (void)converter:(id)sender { [_delegate showConverterCommand:sender]; }
- (void)workflow:(id)sender { [_delegate showWorkflowCommand:sender]; }
- (void)save:(id)sender { [_delegate saveBankCommand:sender]; }

@end

@implementation SVAppDelegate (GUIIntegration)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ SVInstallGUIWhenReady(); });
}

- (void)showSampleEditorCommand:(id)sender {
    (void)sender;
    id main = SVMainController(self);
    if (main == nil || ![main respondsToSelector:@selector(showWindow:)]) return;
    [main showWindow:self];
    NSWindow* window = [main window];
    [window makeKeyAndOrderFront:self];
}

@end
