#import <AppKit/AppKit.h>

#include <algorithm>
#include <cmath>
#include <cstdint>

@interface SVWaveformView : NSView
@property(nonatomic, copy) NSArray<NSNumber*>* points;
@property(nonatomic) uint64_t totalFrames;
@property(nonatomic) BOOL loopEnabled;
@property(nonatomic) uint64_t loopStart;
@property(nonatomic) uint64_t loopEnd;
@end

namespace {

std::uint64_t SVFrameForPoint(SVWaveformView* view, NSPoint point) noexcept {
    const CGFloat width = NSWidth(view.bounds);
    if (width <= 0.0 || view.totalFrames == 0U) return 0U;
    const double normalized = std::max(0.0, std::min(1.0, static_cast<double>(point.x / width)));
    const long double frame = static_cast<long double>(normalized) * static_cast<long double>(view.totalFrames);
    return static_cast<std::uint64_t>(std::llround(frame));
}

NSTextField* SVFieldFromController(NSWindowController* controller, NSString* key) {
    if (controller == nil || key.length == 0U) return nil;
    id value = [controller valueForKey:key];
    return [value isKindOfClass:[NSTextField class]] ? static_cast<NSTextField*>(value) : nil;
}

void SVStageRange(SVWaveformView* view, std::uint64_t a, std::uint64_t b, BOOL trimMode) {
    if (view.window == nil || view.window.windowController == nil) return;
    const std::uint64_t low = std::min(a, b);
    const std::uint64_t high = std::max(a, b);
    NSWindowController* controller = view.window.windowController;
    NSTextField* startField = SVFieldFromController(controller, trimMode ? @"trimStartField" : @"loopStartField");
    NSTextField* endField = SVFieldFromController(controller, trimMode ? @"trimEndField" : @"loopEndField");
    if (startField == nil || endField == nil) return;
    startField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(low)];
    endField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(high)];
}

} // namespace

@implementation SVWaveformView (InteractiveRangeEditing)

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    self.toolTip = @"Drag: prepare Loop Start/End. Option-drag: prepare Trim Start/End. Nothing is applied until Set Loop / Apply Trim.";
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self addCursorRect:self.bounds cursor:[NSCursor crosshairCursor]];
}

- (void)mouseDown:(NSEvent*)event {
    if (self.totalFrames == 0U || self.window == nil) {
        [super mouseDown:event];
        return;
    }

    const BOOL trimMode = (event.modifierFlags & NSEventModifierFlagOption) != 0U;
    NSPoint startPoint = [self convertPoint:event.locationInWindow fromView:nil];
    std::uint64_t startFrame = SVFrameForPoint(self, startPoint);
    std::uint64_t endFrame = startFrame;
    SVStageRange(self, startFrame, endFrame, trimMode);

    const NSEventMask mask = NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp;
    while (true) {
        NSEvent* next = [self.window nextEventMatchingMask:mask
                                                untilDate:[NSDate distantFuture]
                                                   inMode:NSEventTrackingRunLoopMode
                                                  dequeue:YES];
        if (next == nil) break;
        NSPoint currentPoint = [self convertPoint:next.locationInWindow fromView:nil];
        endFrame = SVFrameForPoint(self, currentPoint);
        SVStageRange(self, startFrame, endFrame, trimMode);
        if (next.type == NSEventTypeLeftMouseUp) break;
    }
}

@end
