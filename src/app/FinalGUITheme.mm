#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

namespace {

static const void* kSVThemeAppliedKey = &kSVThemeAppliedKey;

NSColor* SVBackgroundColor() {
    return [NSColor colorWithCalibratedRed:0.050 green:0.061 blue:0.073 alpha:1.0];
}

NSColor* SVPanelColor() {
    return [NSColor colorWithCalibratedRed:0.070 green:0.082 blue:0.096 alpha:1.0];
}

NSColor* SVFieldColor() {
    return [NSColor colorWithCalibratedRed:0.086 green:0.101 blue:0.118 alpha:1.0];
}

NSColor* SVPrimaryTextColor() {
    return [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
}

NSColor* SVAccentColor() {
    return [NSColor colorWithCalibratedRed:0.35 green:0.68 blue:0.96 alpha:1.0];
}

NSColor* SVDangerColor() {
    return [NSColor colorWithCalibratedRed:0.95 green:0.38 blue:0.36 alpha:1.0];
}

BOOL SVTitleContains(NSString* title, NSArray<NSString*>* needles) {
    if (title.length == 0U) return NO;
    NSString* lower = title.lowercaseString;
    for (NSString* needle in needles) {
        if ([lower containsString:needle.lowercaseString]) return YES;
    }
    return NO;
}

void SVStyleButton(NSButton* button) {
    if (button == nil) return;
    button.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];

    const BOOL pushButton = button.bezelStyle == NSBezelStyleRounded ||
                            button.bezelStyle == NSBezelStyleTexturedRounded ||
                            button.bezelStyle == NSBezelStyleRecessed;
    if (!pushButton) return;

    NSColor* titleColor = SVPrimaryTextColor();
    NSFontWeight weight = NSFontWeightMedium;
    if (SVTitleContains(button.title, @[@"save", @"apply", @"import", @"build", @"create"])) {
        titleColor = SVAccentColor();
        weight = NSFontWeightSemibold;
    } else if (SVTitleContains(button.title, @[@"delete", @"clear", @"remove"])) {
        titleColor = SVDangerColor();
        weight = NSFontWeightSemibold;
    }

    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.alignment = NSTextAlignmentCenter;
    button.attributedTitle = [[NSAttributedString alloc] initWithString:button.title ?: @""
                                                            attributes:@{
        NSForegroundColorAttributeName: titleColor,
        NSFontAttributeName: [NSFont systemFontOfSize:11.5 weight:weight],
        NSParagraphStyleAttributeName: paragraph
    }];
}

void SVStyleTextField(NSTextField* field) {
    if (field == nil) return;
    if (field.editable || field.bezeled) {
        field.drawsBackground = YES;
        field.backgroundColor = SVFieldColor();
        field.textColor = SVPrimaryTextColor();
        if (field.font.pointSize < 11.0) field.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    } else if (field.textColor == nil || [field.textColor isEqual:[NSColor controlTextColor]]) {
        field.textColor = SVPrimaryTextColor();
    }
}

void SVStyleTable(NSTableView* table) {
    if (table == nil) return;
    table.backgroundColor = SVPanelColor();
    table.gridColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0];
    table.usesAlternatingRowBackgroundColors = NO;
    if (table.rowHeight < 28.0) table.rowHeight = 28.0;
    if (table.headerView != nil) {
        table.headerView.wantsLayer = YES;
        table.headerView.layer.backgroundColor = SVFieldColor().CGColor;
    }
}

void SVStyleScrollView(NSScrollView* scroll) {
    if (scroll == nil) return;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = SVPanelColor();
    scroll.borderType = NSBezelBorder;
}

void SVStyleViewTree(NSView* view) {
    if (view == nil) return;

    if ([view isKindOfClass:[NSTextField class]]) {
        SVStyleTextField((NSTextField*)view);
    } else if ([view isKindOfClass:[NSButton class]]) {
        SVStyleButton((NSButton*)view);
    } else if ([view isKindOfClass:[NSTableView class]]) {
        SVStyleTable((NSTableView*)view);
    } else if ([view isKindOfClass:[NSScrollView class]]) {
        SVStyleScrollView((NSScrollView*)view);
    } else if ([view isKindOfClass:[NSPopUpButton class]]) {
        ((NSPopUpButton*)view).font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    } else if ([view isKindOfClass:[NSSegmentedControl class]]) {
        ((NSSegmentedControl*)view).font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightMedium];
    }

    for (NSView* child in view.subviews) SVStyleViewTree(child);
}

void SVApplyWindowTheme(NSWindow* window) {
    if (window == nil) return;

    NSNumber* applied = objc_getAssociatedObject(window, kSVThemeAppliedKey);
    if (applied.boolValue) {
        SVStyleViewTree(window.contentView);
        return;
    }

    objc_setAssociatedObject(window, kSVThemeAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    window.backgroundColor = SVBackgroundColor();
    window.opaque = YES;
    window.hasShadow = YES;
    window.titlebarAppearsTransparent = NO;
    window.movableByWindowBackground = NO;
    window.releasedWhenClosed = NO;
    window.titleVisibility = NSWindowTitleVisible;

    if (window.contentView != nil) {
        window.contentView.wantsLayer = YES;
        window.contentView.layer.backgroundColor = SVBackgroundColor().CGColor;
    }
    SVStyleViewTree(window.contentView);
}

void SVThemeAllWindows(void) {
    for (NSWindow* window in NSApp.windows) SVApplyWindowTheme(window);
}

} // namespace

@interface SVFinalGUITheme : NSObject
@end

@implementation SVFinalGUITheme

+ (void)load {
    [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* note) {
        (void)note;
        SVThemeAllWindows();
    }];

    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowDidBecomeKeyNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification* note) {
        NSWindow* window = [note.object isKindOfClass:[NSWindow class]] ? (NSWindow*)note.object : nil;
        SVApplyWindowTheme(window);
    }];
}

@end
