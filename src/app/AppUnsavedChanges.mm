#import <AppKit/AppKit.h>

@interface SVAppDelegate : NSObject <NSApplicationDelegate>
- (BOOL)confirmSaveBeforeAction:(NSString*)action;
@end

@implementation SVAppDelegate (UnsavedChangesTermination)

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication*)sender {
    (void)sender;
    return [self confirmSaveBeforeAction:@"quitting SILVETON Manager"] ? NSTerminateNow : NSTerminateCancel;
}

@end
