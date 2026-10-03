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

@interface SVWorkspaceButton : NSButton
@property(nonatomic) BOOL workspaceSelected;
@property(nonatomic) BOOL accentAction;
@end

@implementation SVWorkspaceButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.buttonType = NSButtonTypeMomentaryChange;
        self.font = [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold];
        self.focusRingType = NSFocusRingTypeNone;
        self.wantsLayer = YES;
    }
    return self;
}

- (void)setWorkspaceSelected:(BOOL)workspaceSelected {
    _workspaceSelected = workspaceSelected;
    [self setNeedsDisplay:YES];
}

- (void)setAccentAction:(BOOL)accentAction {
    _accentAction = accentAction;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect rect = NSInsetRect(self.bounds, 1.0, 2.0);
    NSBezierPath* shape = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:6.0 yRadius:6.0];

    const BOOL highlighted = [(NSButtonCell*)self.cell isHighlighted];
    NSColor* fill = nil;
    NSColor* stroke = nil;
    NSColor* text = nil;

    if (self.accentAction) {
        fill = highlighted
            ? [NSColor colorWithCalibratedRed:0.20 green:0.50 blue:0.78 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.16 green:0.42 blue:0.70 alpha:1.0];
        stroke = [NSColor colorWithCalibratedRed:0.39 green:0.72 blue:1.0 alpha:0.95];
        text = [NSColor whiteColor];
    } else if (self.workspaceSelected) {
        fill = highlighted
            ? [NSColor colorWithCalibratedRed:0.14 green:0.30 blue:0.44 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.11 green:0.25 blue:0.37 alpha:1.0];
        stroke = [NSColor colorWithCalibratedRed:0.35 green:0.68 blue:0.96 alpha:0.90];
        text = [NSColor colorWithCalibratedRed:0.72 green:0.87 blue:1.0 alpha:1.0];
    } else {
        fill = highlighted
            ? [NSColor colorWithCalibratedRed:0.12 green:0.14 blue:0.17 alpha:1.0]
            : [NSColor colorWithCalibratedRed:0.075 green:0.088 blue:0.103 alpha:1.0];
        stroke = [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
        text = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    }

    [fill setFill];
    [shape fill];
    [stroke setStroke];
    shape.lineWidth = 1.0;
    [shape stroke];

    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    NSDictionary* attributes = @{
        NSForegroundColorAttributeName: text,
        NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:11.0 weight:NSFontWeightSemibold],
        NSParagraphStyleAttributeName: paragraph
    };
    NSAttributedString* title = [[NSAttributedString alloc] initWithString:self.title ?: @"" attributes:attributes];
    NSSize size = title.size;
    const CGFloat x = floor((NSWidth(self.bounds) - size.width) * 0.5);
    const CGFloat y = floor((NSHeight(self.bounds) - size.height) * 0.5) + 1.0;
    [title drawAtPoint:NSMakePoint(x, y)];
}

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

SVWorkspaceButton* SVToolbarButton(NSString* title, id target, SEL action, CGFloat width, BOOL accent) {
    SVWorkspaceButton* button = [[SVWorkspaceButton alloc] initWithFrame:NSMakeRect(0.0, 0.0, width, 32.0)];
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.accentAction = accent;
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
    NSMutableDictionary<NSString*, SVWorkspaceButton*>* _buttons;
}

- (instancetype)initWithDelegate:(SVAppDelegate*)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _buttons = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)installOnMainWindow {
    id main = SVMainController(_delegate);
    if (main == nil || ![main respondsToSelector:@selector(window)]) return;
    NSWindow* window = [main window];
    if (window == nil) return;

    window.title = @"SILVETON Manager";
    NSToolbar* toolbar = [[NSToolbar alloc] initWithIdentifier:@"SILVETONManagerWorkspaceToolbar"];
    toolbar.delegate = self;
    toolbar.allowsUserCustomization = NO;
    toolbar.autosavesConfiguration = NO;
    toolbar.displayMode = NSToolbarDisplayModeIconOnly;
    toolbar.sizeMode = NSToolbarSizeModeRegular;
    toolbar.showsBaselineSeparator = YES;
    window.toolbar = toolbar;
    [self selectWorkspace:kSamplesItem];
}

- (void)selectWorkspace:(NSString*)identifier {
    for (NSString* key in _buttons) _buttons[key].workspaceSelected = [key isEqualToString:identifier];
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
    SVWorkspaceButton* button = nil;

    if ([itemIdentifier isEqualToString:kSamplesItem]) {
        button = SVToolbarButton(@"SAMPLES", self, @selector(samples:), 86.0, NO);
        item.label = @"Samples";
    } else if ([itemIdentifier isEqualToString:kMediaItem]) {
        button = SVToolbarButton(@"MEDIA", self, @selector(media:), 72.0, NO);
        item.label = @"MEDIA";
    } else if ([itemIdentifier isEqualToString:kMultisampleItem]) {
        button = SVToolbarButton(@"MULTISAMPLE", self, @selector(multisample:), 112.0, NO);
        item.label = @"Multisample";
    } else if ([itemIdentifier isEqualToString:kSoundItem]) {
        button = SVToolbarButton(@"SOUND", self, @selector(sound:), 76.0, NO);
        item.label = @"SOUND";
    } else if ([itemIdentifier isEqualToString:kBankItem]) {
        button = SVToolbarButton(@"BANK", self, @selector(bank:), 68.0, NO);
        item.label = @"Bank";
    } else if ([itemIdentifier isEqualToString:kObjectsItem]) {
        button = SVToolbarButton(@"OBJECTS", self, @selector(objects:), 86.0, NO);
        item.label = @"Objects";
    } else if ([itemIdentifier isEqualToString:kConverterItem]) {
        button = SVToolbarButton(@"CONVERTER", self, @selector(converter:), 100.0, NO);
        item.label = @"Converter";
    } else if ([itemIdentifier isEqualToString:kWorkflowItem]) {
        button = SVToolbarButton(@"WORKFLOW", self, @selector(workflow:), 96.0, NO);
        item.label = @"Workflow";
    } else if ([itemIdentifier isEqualToString:kSaveItem]) {
        button = SVToolbarButton(@"SAVE BANK", self, @selector(save:), 96.0, YES);
        item.label = @"Save Bank";
    }

    if (button != nil) {
        item.view = button;
        _buttons[itemIdentifier] = button;
    }
    return item;
}

- (void)samples:(id)sender { [self selectWorkspace:kSamplesItem]; [_delegate showSampleEditorCommand:sender]; }
- (void)media:(id)sender { [self selectWorkspace:kMediaItem]; [_delegate showMediaCommand:sender]; }
- (void)multisample:(id)sender { [self selectWorkspace:kMultisampleItem]; [_delegate showMultisampleEditor:sender]; }
- (void)sound:(id)sender { [self selectWorkspace:kSoundItem]; [_delegate showSoundEditor:sender]; }
- (void)bank:(id)sender { [self selectWorkspace:kBankItem]; [_delegate showBankOrganizer:sender]; }
- (void)objects:(id)sender { [self selectWorkspace:kObjectsItem]; [_delegate showObjectManagerCommand:sender]; }
- (void)converter:(id)sender { [self selectWorkspace:kConverterItem]; [_delegate showConverterCommand:sender]; }
- (void)workflow:(id)sender { [self selectWorkspace:kWorkflowItem]; [_delegate showWorkflowCommand:sender]; }
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
