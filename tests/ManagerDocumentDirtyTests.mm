#import <Foundation/Foundation.h>

#include <cstdlib>
#include <iostream>

@interface SVManagerDocument : NSObject
- (BOOL)hasUnsavedChanges;
- (void)markCurrentStateSaved;
- (void)markCurrentStateChanged;
- (void)clearProject;
@end

namespace {
void require(bool condition, const char* message) {
    if (!condition) {
        std::cerr << "FAIL: " << message << '\n';
        std::exit(1);
    }
}
}

int main() {
    @autoreleasepool {
        SVManagerDocument* document = [[SVManagerDocument alloc] init];
        require(![document hasUnsavedChanges], "new document must start clean");

        [document markCurrentStateChanged];
        require([document hasUnsavedChanges], "explicit change must mark document dirty");

        [document markCurrentStateSaved];
        require(![document hasUnsavedChanges], "mark saved must clear dirty state");

        [document clearProject];
        require([document hasUnsavedChanges], "clearing/replacing a project must mark it dirty");

        [document markCurrentStateSaved];
        require(![document hasUnsavedChanges], "new/open workflows can establish a clean baseline");
    }
    std::cout << "Unsaved-change regression tests passed\n";
    return 0;
}
