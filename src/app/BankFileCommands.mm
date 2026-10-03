#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVManagerDocument : NSObject
- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
@end

@interface SVMainWindowController : NSWindowController
- (void)refreshProjectView;
@end

@interface SVAppDelegate : NSObject
- (void)refreshAllEditors;
@end

@interface SVAppDelegate (BankFileCommands)
- (void)openBankCommand:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)saveBankAsCommand:(id)sender;
@end

namespace {

static const void* kSVCurrentBankPathKey = &kSVCurrentBankPathKey;

SVMainWindowController* SVMainController(SVAppDelegate* delegate) {
    id controller = [delegate valueForKey:@"mainWindowController"];
    return [controller isKindOfClass:[NSWindowController class]] ? controller : nil;
}

SVManagerDocument* SVDocument(SVAppDelegate* delegate) {
    SVMainWindowController* controller = SVMainController(delegate);
    if (controller == nil) return nil;
    id document = [controller valueForKey:@"documentModel"];
    return document;
}

void SVStopAudition(SVAppDelegate* delegate) {
    id player = [delegate valueForKey:@"auditionPlayer"];
    if (player != nil && [player respondsToSelector:@selector(stop)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [player performSelector:@selector(stop)];
#pragma clang diagnostic pop
    }
}

void SVSetPathLabel(SVAppDelegate* delegate, NSString* prefix, NSString* path) {
    SVMainWindowController* controller = SVMainController(delegate);
    if (controller == nil) return;
    id label = [controller valueForKey:@"pathLabel"];
    if ([label isKindOfClass:[NSTextField class]]) {
        ((NSTextField*)label).stringValue = [NSString stringWithFormat:@"%@: %@", prefix ?: @"Bank", path ?: @""];
    }
}

void SVShowBankMessage(SVAppDelegate* delegate, NSString* title, NSString* text, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Manager";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    NSWindow* window = SVMainController(delegate).window;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

NSString* SVCurrentBankPath(SVAppDelegate* delegate) {
    return objc_getAssociatedObject(delegate, kSVCurrentBankPathKey);
}

void SVSetCurrentBankPath(SVAppDelegate* delegate, NSString* path) {
    objc_setAssociatedObject(delegate, kSVCurrentBankPathKey, [path copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
}

BOOL SVWriteBank(SVAppDelegate* delegate, NSString* path) {
    SVManagerDocument* document = SVDocument(delegate);
    if (document == nil) {
        SVShowBankMessage(delegate, @"Save unavailable", @"The Manager document is unavailable.", NSAlertStyleCritical);
        return NO;
    }
    NSString* error = nil;
    NSString* summary = nil;
    if (![document buildBankAtPath:path error:&error summary:&summary]) {
        SVShowBankMessage(delegate, @"Bank save failed", error ?: @"Unknown bank save error.", NSAlertStyleCritical);
        return NO;
    }
    SVSetCurrentBankPath(delegate, path);
    SVSetPathLabel(delegate, @"Saved", path);
    SVShowBankMessage(delegate, @"SILVETON bank saved", summary ?: @"Bank save completed.", NSAlertStyleInformational);
    return YES;
}

} // namespace

@implementation SVAppDelegate (BankFileCommands)

- (void)openBankCommand:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Open SILVETON bank";
    panel.prompt = @"Open";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    panel.allowedFileTypes = @[@"sv"];

    if ([panel runModal] != NSModalResponseOK || panel.URL.path == nil) return;

    SVManagerDocument* document = SVDocument(self);
    if (document == nil) {
        SVShowBankMessage(self, @"Open unavailable", @"The Manager document is unavailable.", NSAlertStyleCritical);
        return;
    }

    NSString* error = nil;
    NSString* summary = nil;
    if (![document loadBankAtPath:panel.URL.path error:&error summary:&summary]) {
        SVShowBankMessage(self, @"Bank open failed", error ?: @"The selected bank could not be opened.", NSAlertStyleCritical);
        return;
    }

    SVStopAudition(self);
    SVSetCurrentBankPath(self, panel.URL.path);
    SVSetPathLabel(self, @"Opened", panel.URL.path);
    [self refreshAllEditors];
    SVShowBankMessage(self, @"SILVETON bank opened", summary ?: @"Bank loaded successfully.", NSAlertStyleInformational);
}

- (void)saveBankCommand:(id)sender {
    (void)sender;
    NSString* path = SVCurrentBankPath(self);
    if (path.length == 0U) {
        [self saveBankAsCommand:self];
        return;
    }
    (void)SVWriteBank(self, path);
}

- (void)saveBankAsCommand:(id)sender {
    (void)sender;
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Save SILVETON bank";
    panel.prompt = @"Save";
    NSString* currentPath = SVCurrentBankPath(self);
    panel.nameFieldStringValue = currentPath.length == 0U ? @"SILVETON_BANK.sv" : currentPath.lastPathComponent;
    panel.allowedFileTypes = @[@"sv"];
    panel.allowsOtherFileTypes = NO;
    panel.canCreateDirectories = YES;
    if ([panel runModal] != NSModalResponseOK || panel.URL.path == nil) return;
    (void)SVWriteBank(self, panel.URL.path);
}

@end
