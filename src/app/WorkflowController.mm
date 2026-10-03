#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVManagerDocument : NSObject
- (NSUInteger)sampleCount;
- (NSUInteger)multisampleCount;
- (NSUInteger)soundCount;
- (BOOL)hasUnsavedChanges;
@end

@interface SVAppDelegate : NSObject
- (void)showMediaCommand:(id)sender;
- (void)showConverterCommand:(id)sender;
- (void)showObjectManagerCommand:(id)sender;
- (void)showMultisampleEditor:(id)sender;
- (void)showSoundEditor:(id)sender;
- (void)showBankOrganizer:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)newBankCommand:(id)sender;
- (void)openBankCommand:(id)sender;
- (void)refreshAllEditors;
@end

@interface SVWorkflowWindowController : NSWindowController
- (instancetype)initWithDelegate:(SVAppDelegate*)delegate;
- (void)refreshState;
@end

namespace {
static const void* kSVWorkflowControllerKey = &kSVWorkflowControllerKey;

void SVWorkflowSwizzle(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original != nullptr && replacement != nullptr) method_exchangeImplementations(original, replacement);
}

NSTextField* WorkflowLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

NSButton* WorkflowButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightSemibold];
    return button;
}

id WorkflowMainController(SVAppDelegate* delegate) {
    return [delegate valueForKey:@"mainWindowController"];
}

SVManagerDocument* WorkflowDocument(SVAppDelegate* delegate) {
    id main = WorkflowMainController(delegate);
    return [main valueForKey:@"documentModel"];
}
}

@implementation SVWorkflowWindowController {
    SVAppDelegate* _delegate;
    NSTextField* _statusLabel;
}

- (instancetype)initWithDelegate:(SVAppDelegate*)delegate {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 760.0, 520.0)
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Workflow";
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];
    self = [super initWithWindow:window];
    if (self) {
        _delegate = delegate;
        [self buildInterface];
        [self refreshState];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    NSColor* mainText = [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];
    NSColor* dimText = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
    NSColor* accent = [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0];

    [content addSubview:WorkflowLabel(NSMakeRect(28.0, 466.0, 520.0, 30.0), @"SILVETON WORKFLOW", 22.0, NSFontWeightSemibold, accent)];
    [content addSubview:WorkflowLabel(NSMakeRect(30.0, 442.0, 690.0, 20.0),
                                       @"Follow the six steps from source media to the final .sv bank. Every destructive action still requires an explicit command.",
                                       11.0, NSFontWeightRegular, dimText)];

    const CGFloat left = 30.0;
    const CGFloat width = 700.0;
    const CGFloat height = 48.0;
    const CGFloat gap = 10.0;
    CGFloat y = 378.0;

    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"1  MEDIA / IMPORT", self, @selector(mediaPressed:))];
    y -= height + gap;
    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"2  SAMPLE EDITOR", self, @selector(samplesPressed:))];
    y -= height + gap;
    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"3  MULTISAMPLE", self, @selector(multisamplePressed:))];
    y -= height + gap;
    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"4  SOUND", self, @selector(soundPressed:))];
    y -= height + gap;
    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"5  BANK / CATEGORY / SLOT", self, @selector(bankPressed:))];
    y -= height + gap;
    [content addSubview:WorkflowButton(NSMakeRect(left, y, width, height), @"6  SAVE SILVETON BANK", self, @selector(savePressed:))];

    [content addSubview:WorkflowLabel(NSMakeRect(30.0, 36.0, 90.0, 20.0), @"Tools", 12.0, NSFontWeightSemibold, mainText)];
    [content addSubview:WorkflowButton(NSMakeRect(118.0, 28.0, 150.0, 30.0), @"Object Manager", self, @selector(objectsPressed:))];
    [content addSubview:WorkflowButton(NSMakeRect(278.0, 28.0, 150.0, 30.0), @"Sample Converter", self, @selector(converterPressed:))];
    [content addSubview:WorkflowButton(NSMakeRect(438.0, 28.0, 92.0, 30.0), @"New Bank", self, @selector(newPressed:))];
    [content addSubview:WorkflowButton(NSMakeRect(540.0, 28.0, 92.0, 30.0), @"Open Bank", self, @selector(openPressed:))];

    _statusLabel = WorkflowLabel(NSMakeRect(30.0, 6.0, 700.0, 18.0), @"", 10.5, NSFontWeightMedium, accent);
    [content addSubview:_statusLabel];
}

- (void)refreshState {
    SVManagerDocument* document = WorkflowDocument(_delegate);
    const NSUInteger samples = [document sampleCount];
    const NSUInteger multisamples = [document multisampleCount];
    const NSUInteger sounds = [document soundCount];
    const BOOL dirty = [document hasUnsavedChanges];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu samples · %lu multisamples · %lu SOUNDs · %@",
                                (unsigned long)samples,
                                (unsigned long)multisamples,
                                (unsigned long)sounds,
                                dirty ? @"UNSAVED CHANGES" : @"saved"];
}

- (void)mediaPressed:(id)sender { [_delegate showMediaCommand:sender]; }
- (void)samplesPressed:(id)sender {
    (void)sender;
    id main = WorkflowMainController(_delegate);
    [main showWindow:nil];
    [[main window] makeKeyAndOrderFront:nil];
}
- (void)multisamplePressed:(id)sender { [_delegate showMultisampleEditor:sender]; }
- (void)soundPressed:(id)sender { [_delegate showSoundEditor:sender]; }
- (void)bankPressed:(id)sender { [_delegate showBankOrganizer:sender]; }
- (void)savePressed:(id)sender { [_delegate saveBankCommand:sender]; [self refreshState]; }
- (void)objectsPressed:(id)sender { [_delegate showObjectManagerCommand:sender]; }
- (void)converterPressed:(id)sender { [_delegate showConverterCommand:sender]; }
- (void)newPressed:(id)sender { [_delegate newBankCommand:sender]; [self refreshState]; }
- (void)openPressed:(id)sender { [_delegate openBankCommand:sender]; [self refreshState]; }

@end

@implementation SVAppDelegate (Workflow)

+ (void)load {
    SVWorkflowSwizzle(self, @selector(applicationDidFinishLaunching:), @selector(sv_workflow_applicationDidFinishLaunching:));
    SVWorkflowSwizzle(self, @selector(refreshAllEditors), @selector(sv_workflow_refreshAllEditors));
}

- (void)sv_workflow_applicationDidFinishLaunching:(NSNotification*)notification {
    [self sv_workflow_applicationDidFinishLaunching:notification];
    id main = WorkflowMainController(self);
    NSWindow* mainWindow = [main window];
    NSView* content = mainWindow.contentView;
    if (content != nil) {
        NSButton* workflow = WorkflowButton(NSMakeRect(1080.0, 758.0, 168.0, 30.0), @"WORKFLOW…", self, @selector(showWorkflowCommand:));
        workflow.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
        [content addSubview:workflow];
    }
    mainWindow.documentEdited = [WorkflowDocument(self) hasUnsavedChanges];
}

- (void)sv_workflow_refreshAllEditors {
    [self sv_workflow_refreshAllEditors];
    id main = WorkflowMainController(self);
    [[main window] setDocumentEdited:[WorkflowDocument(self) hasUnsavedChanges]];
    SVWorkflowWindowController* controller = objc_getAssociatedObject(self, kSVWorkflowControllerKey);
    [controller refreshState];
}

- (void)showWorkflowCommand:(id)sender {
    (void)sender;
    SVWorkflowWindowController* controller = objc_getAssociatedObject(self, kSVWorkflowControllerKey);
    if (controller == nil) {
        controller = [[SVWorkflowWindowController alloc] initWithDelegate:self];
        objc_setAssociatedObject(self, kSVWorkflowControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [controller refreshState];
    [controller showWindow:nil];
    [controller.window center];
    [controller.window makeKeyAndOrderFront:nil];
}

@end
