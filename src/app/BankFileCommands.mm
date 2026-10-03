#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVManagerDocument : NSObject
- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (void)clearProject;
- (BOOL)hasUnsavedChanges;
- (void)markCurrentStateSaved;
@end

@interface SVMainWindowController : NSWindowController
- (void)refreshProjectView;
@end

@interface SVAppDelegate : NSObject
- (void)refreshAllEditors;
@end

@interface SVAppDelegate (BankFileCommands)
- (void)newBankCommand:(id)sender;
- (void)openBankCommand:(id)sender;
- (void)saveBankCommand:(id)sender;
- (void)saveBankAsCommand:(id)sender;
- (BOOL)confirmSaveBeforeAction:(NSString*)action;
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
        ((NSTextField*)label).stringValue = path.length == 0U
            ? (prefix ?: @"Bank")
            : [NSString stringWithFormat:@"%@: %@", prefix ?: @"Bank", path];
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
    [document markCurrentStateSaved];
    SVSetCurrentBankPath(delegate, path);
    SVSetPathLabel(delegate, @"Saved", path);
    SVShowBankMessage(delegate, @"SILVETON bank saved", summary ?: @"Bank save completed.", NSAlertStyleInformational);
    return YES;
}

BOOL SVSaveBankAs(SVAppDelegate* delegate) {
    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Save SILVETON bank";
    panel.prompt = @"Save";
    NSString* currentPath = SVCurrentBankPath(delegate);
    panel.nameFieldStringValue = currentPath.length == 0U ? @"SILVETON_BANK.sv" : currentPath.lastPathComponent;
    panel.allowedFileTypes = @[@"sv"];
    panel.allowsOtherFileTypes = NO;
    panel.canCreateDirectories = YES;
    if ([panel runModal] != NSModalResponseOK || panel.URL.path.length == 0U) return NO;
    return SVWriteBank(delegate, panel.URL.path);
}

} // namespace

@implementation SVAppDelegate (BankFileCommands)

- (BOOL)confirmSaveBeforeAction:(NSString*)action {
    SVManagerDocument* document = SVDocument(self);
    if (document == nil || ![document hasUnsavedChanges]) return YES;

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Save changes to the current SILVETON bank?";
    alert.informativeText = [NSString stringWithFormat:@"The current bank has unsaved changes. Save before %@?", action.length == 0U ? @"continuing" : action];
    alert.alertStyle = NSAlertStyleWarning;
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];

    const NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn) return YES;
    if (response != NSAlertFirstButtonReturn) return NO;

    NSString* path = SVCurrentBankPath(self);
    return path.length == 0U ? SVSaveBankAs(self) : SVWriteBank(self, path);
}

- (void)newBankCommand:(id)sender {
    (void)sender;
    if (![self confirmSaveBeforeAction:@"creating a new bank"]) return;
    SVManagerDocument* document = SVDocument(self);
    if (document == nil) {
        SVShowBankMessage(self, @"New Bank unavailable", @"The Manager document is unavailable.", NSAlertStyleCritical);
        return;
    }
    SVStopAudition(self);
    [document clearProject];
    [document markCurrentStateSaved];
    SVSetCurrentBankPath(self, nil);
    SVSetPathLabel(self, @"New SILVETON bank", nil);
    [self refreshAllEditors];
}

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

    if ([panel runModal] != NSModalResponseOK || panel.URL.path.length == 0U) return;
    if (![self confirmSaveBeforeAction:@"opening another bank"]) return;

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

    [document markCurrentStateSaved];
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
        (void)SVSaveBankAs(self);
        return;
    }
    (void)SVWriteBank(self, path);
}

- (void)saveBankAsCommand:(id)sender {
    (void)sender;
    (void)SVSaveBankAs(self);
}

@end
