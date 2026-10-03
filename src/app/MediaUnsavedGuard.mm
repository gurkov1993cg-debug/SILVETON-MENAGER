#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVAppDelegate : NSObject
- (BOOL)confirmSaveBeforeAction:(NSString*)action;
@end

@interface SVMediaWindowController : NSWindowController
@end

namespace {
void SVMediaGuardSwizzle(Class cls, SEL originalSelector, SEL replacementSelector) {
    Method original = class_getInstanceMethod(cls, originalSelector);
    Method replacement = class_getInstanceMethod(cls, replacementSelector);
    if (original != nullptr && replacement != nullptr) method_exchangeImplementations(original, replacement);
}
}

@implementation SVMediaWindowController (UnsavedGuard)

+ (void)load {
    SVMediaGuardSwizzle(self, @selector(loadBankPressed:), @selector(sv_guarded_loadBankPressed:));
}

- (void)sv_guarded_loadBankPressed:(id)sender {
    id delegate = [self valueForKey:@"delegate"];
    if ([delegate respondsToSelector:@selector(confirmSaveBeforeAction:)] &&
        ![(SVAppDelegate*)delegate confirmSaveBeforeAction:@"loading another bank from MEDIA"]) return;
    [self sv_guarded_loadBankPressed:sender];
}

@end
