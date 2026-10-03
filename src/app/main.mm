#import <AppKit/AppKit.h>

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
@end

int main(int argc, const char* argv[]) {
    (void)argc;
    (void)argv;

    @autoreleasepool {
        NSApplication* app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];

        SVAppDelegate* delegate = [[SVAppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
        app.delegate = nil;
        (void)delegate;
    }
    return 0;
}
