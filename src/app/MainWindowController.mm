#import <AppKit/AppKit.h>

#include <cerrno>
#include <cstdint>
#include <cstdlib>

@interface SVManagerDocument : NSObject
- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (NSString*)statusSummary;
- (void)clearProject;
- (NSUInteger)sampleCount;
- (NSArray<NSString*>*)sampleDisplayRows;
- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index;
- (NSArray<NSNumber*>*)waveformAtIndex:(NSUInteger)index pointCount:(NSUInteger)pointCount error:(NSString**)error;
- (BOOL)trimSampleAtIndex:(NSUInteger)index startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)setLoopForSampleAtIndex:(NSUInteger)index enabled:(BOOL)enabled startFrame:(uint64_t)startFrame endFrame:(uint64_t)endFrame error:(NSString**)error;
- (BOOL)applyLoopCrossfadeForSampleAtIndex:(NSUInteger)index frames:(uint32_t)frames error:(NSString**)error;
- (BOOL)reverseSampleAtIndex:(NSUInteger)index error:(NSString**)error;
- (BOOL)applyGainForSampleAtIndex:(NSUInteger)index gainDb:(float)gainDb error:(NSString**)error;
- (BOOL)normalizeSampleAtIndex:(NSUInteger)index targetPeakDb:(float)targetPeakDb error:(NSString**)error;
- (BOOL)fadeInSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error;
- (BOOL)fadeOutSampleAtIndex:(NSUInteger)index frames:(uint64_t)frames error:(NSString**)error;
- (BOOL)setRootKeyForSampleAtIndex:(NSUInteger)index rootKey:(uint8_t)rootKey error:(NSString**)error;
- (BOOL)setFineTuneForSampleAtIndex:(NSUInteger)index cents:(float)cents error:(NSString**)error;
- (uint64_t)nearestZeroCrossingForSampleAtIndex:(NSUInteger)index frame:(uint64_t)frame radius:(uint64_t)radius;
@end

@interface SVWaveformView : NSView
@property(nonatomic, copy) NSArray<NSNumber*>* points;
@property(nonatomic) uint64_t totalFrames;
@property(nonatomic) BOOL loopEnabled;
@property(nonatomic) uint64_t loopStart;
@property(nonatomic) uint64_t loopEnd;
@end

@implementation SVWaveformView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithCalibratedRed:0.042 green:0.050 blue:0.060 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    const CGFloat width = NSWidth(self.bounds);
    const CGFloat height = NSHeight(self.bounds);
    const CGFloat middle = height * 0.5;

    [[NSColor colorWithCalibratedWhite:0.20 alpha:1.0] setStroke];
    NSBezierPath* centre = [NSBezierPath bezierPath];
    [centre moveToPoint:NSMakePoint(0.0, middle)];
    [centre lineToPoint:NSMakePoint(width, middle)];
    centre.lineWidth = 1.0;
    [centre stroke];

    const NSUInteger pairCount = self.points.count / 2U;
    if (pairCount > 0U) {
        NSBezierPath* waveform = [NSBezierPath bezierPath];
        waveform.lineWidth = 1.0;
        for (NSUInteger i = 0U; i < pairCount; ++i) {
            const float minimum = self.points[i * 2U].floatValue;
            const float maximum = self.points[i * 2U + 1U].floatValue;
            const CGFloat x = pairCount <= 1U ? 0.0 : (static_cast<CGFloat>(i) / static_cast<CGFloat>(pairCount - 1U)) * width;
            const CGFloat yMin = middle - static_cast<CGFloat>(maximum) * middle;
            const CGFloat yMax = middle - static_cast<CGFloat>(minimum) * middle;
            [waveform moveToPoint:NSMakePoint(x, yMin)];
            [waveform lineToPoint:NSMakePoint(x, yMax)];
        }
        [[NSColor colorWithCalibratedRed:0.38 green:0.72 blue:0.98 alpha:1.0] setStroke];
        [waveform stroke];
    }

    if (self.loopEnabled && self.totalFrames > 0U && self.loopStart < self.loopEnd) {
        const CGFloat xStart = static_cast<CGFloat>(static_cast<long double>(self.loopStart) / static_cast<long double>(self.totalFrames)) * width;
        const CGFloat xEnd = static_cast<CGFloat>(static_cast<long double>(self.loopEnd) / static_cast<long double>(self.totalFrames)) * width;
        [[NSColor colorWithCalibratedRed:0.34 green:0.88 blue:0.64 alpha:0.95] setStroke];
        NSBezierPath* markers = [NSBezierPath bezierPath];
        markers.lineWidth = 1.5;
        [markers moveToPoint:NSMakePoint(xStart, 0.0)];
        [markers lineToPoint:NSMakePoint(xStart, height)];
        [markers moveToPoint:NSMakePoint(xEnd, 0.0)];
        [markers lineToPoint:NSMakePoint(xEnd, height)];
        [markers stroke];
    }

    [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] setStroke];
    NSFrameRect(self.bounds);
}

@end

@interface SVMainWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@end

namespace {

NSTextField* makeLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

NSTextField* makeNumericField(NSRect frame, NSString* text) {
    NSTextField* field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = text;
    field.bezeled = YES;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.backgroundColor = [NSColor colorWithCalibratedRed:0.085 green:0.098 blue:0.112 alpha:1.0];
    field.textColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    field.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    field.alignment = NSTextAlignmentRight;
    return field;
}

NSButton* makeButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void showMessage(NSWindow* window, NSString* title, NSString* message, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Manager";
    alert.informativeText = message ?: @"";
    alert.alertStyle = style;
    [alert beginSheetModalForWindow:window completionHandler:nil];
}

bool parseUnsignedField(NSTextField* field, std::uint64_t& value) noexcept {
    if (field == nil) return false;
    NSString* trimmed = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0U || [trimmed hasPrefix:@"-"]) return false;
    const char* text = trimmed.UTF8String;
    if (text == nullptr || *text == '\0') return false;

    errno = 0;
    char* end = nullptr;
    const unsigned long long parsed = std::strtoull(text, &end, 10);
    if (errno == ERANGE || end == text || end == nullptr || *end != '\0') return false;
    value = static_cast<std::uint64_t>(parsed);
    return true;
}

} // namespace

@implementation SVMainWindowController {
    SVManagerDocument* _documentModel;
    NSTableView* _sampleTable;
    SVWaveformView* _waveformView;
    NSTextField* _sampleTitleLabel;
    NSTextField* _sampleInfoLabel;
    NSTextField* _statusLabel;
    NSTextField* _pathLabel;
    NSArray<NSString*>* _sampleRows;

    NSTextField* _trimStartField;
    NSTextField* _trimEndField;
    NSTextField* _loopStartField;
    NSTextField* _loopEndField;
    NSTextField* _crossfadeField;
    NSTextField* _fadeInField;
    NSTextField* _fadeOutField;
    NSTextField* _gainField;
    NSTextField* _normalizeField;
    NSTextField* _rootKeyField;
    NSTextField* _fineTuneField;
    NSTextField* _zeroRadiusField;
}

- (instancetype)init {
    const NSRect rect = NSMakeRect(0.0, 0.0, 1280.0, 820.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:rect
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Manager";
    window.minSize = NSMakeSize(1100.0, 700.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        _documentModel = [[SVManagerDocument alloc] init];
        _sampleRows = @[];
        [self buildInterface];
        [self refreshProjectView];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    content.autoresizesSubviews = YES;

    NSTextField* title = makeLabel(NSMakeRect(28.0, 762.0, 460.0, 32.0), @"SILVETON MANAGER", 24.0, NSFontWeightSemibold,
                                   [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0]);
    title.autoresizingMask = NSViewMinYMargin;
    [content addSubview:title];

    NSTextField* subtitle = makeLabel(NSMakeRect(30.0, 738.0, 780.0, 22.0),
                                      @"Sample + multisample preparation for SILVETON_BANK.sv — all edits require explicit Apply",
                                      12.0, NSFontWeightRegular,
                                      [NSColor colorWithCalibratedWhite:0.62 alpha:1.0]);
    subtitle.autoresizingMask = NSViewMinYMargin;
    [content addSubview:subtitle];

    NSButton* importButton = makeButton(NSMakeRect(30.0, 696.0, 150.0, 32.0), @"Import Samples…", self, @selector(importPressed:));
    importButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:importButton];

    NSButton* clearButton = makeButton(NSMakeRect(190.0, 696.0, 90.0, 32.0), @"Clear", self, @selector(clearPressed:));
    clearButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:clearButton];

    NSButton* buildButton = makeButton(NSMakeRect(1040.0, 696.0, 208.0, 32.0), @"Build SILVETON_BANK.sv…", self, @selector(buildPressed:));
    buildButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:buildButton];

    NSTextField* sampleSection = makeLabel(NSMakeRect(30.0, 660.0, 220.0, 22.0), @"Samples", 14.0, NSFontWeightSemibold,
                                           [NSColor colorWithCalibratedWhite:0.86 alpha:1.0]);
    sampleSection.autoresizingMask = NSViewMinYMargin;
    [content addSubview:sampleSection];

    NSScrollView* sampleScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30.0, 126.0, 330.0, 530.0)];
    sampleScroll.autoresizingMask = NSViewHeightSizable;
    sampleScroll.hasVerticalScroller = YES;
    sampleScroll.hasHorizontalScroller = NO;
    sampleScroll.borderType = NSBezelBorder;
    sampleScroll.drawsBackground = YES;
    sampleScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];

    _sampleTable = [[NSTableView alloc] initWithFrame:sampleScroll.bounds];
    _sampleTable.headerView = nil;
    _sampleTable.rowHeight = 30.0;
    _sampleTable.backgroundColor = sampleScroll.backgroundColor;
    _sampleTable.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _sampleTable.gridColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0];
    _sampleTable.dataSource = self;
    _sampleTable.delegate = self;
    _sampleTable.allowsMultipleSelection = NO;
    NSTableColumn* sampleColumn = [[NSTableColumn alloc] initWithIdentifier:@"sample"];
    sampleColumn.width = 315.0;
    sampleColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_sampleTable addTableColumn:sampleColumn];
    sampleScroll.documentView = _sampleTable;
    [content addSubview:sampleScroll];

    _sampleTitleLabel = makeLabel(NSMakeRect(382.0, 660.0, 600.0, 22.0), @"No sample selected", 14.0, NSFontWeightSemibold,
                                  [NSColor colorWithCalibratedWhite:0.90 alpha:1.0]);
    _sampleTitleLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_sampleTitleLabel];

    _waveformView = [[SVWaveformView alloc] initWithFrame:NSMakeRect(382.0, 470.0, 866.0, 180.0)];
    _waveformView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_waveformView];

    _sampleInfoLabel = makeLabel(NSMakeRect(382.0, 444.0, 866.0, 20.0), @"", 11.0, NSFontWeightRegular,
                                 [NSColor colorWithCalibratedWhite:0.64 alpha:1.0]);
    _sampleInfoLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_sampleInfoLabel];

    const NSColor* labelColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0];

    [content addSubview:makeLabel(NSMakeRect(382.0, 405.0, 70.0, 20.0), @"TRIM", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    [content addSubview:makeLabel(NSMakeRect(452.0, 405.0, 44.0, 20.0), @"Start", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _trimStartField = makeNumericField(NSMakeRect(495.0, 402.0, 100.0, 24.0), @"0"); [content addSubview:_trimStartField];
    [content addSubview:makeLabel(NSMakeRect(605.0, 405.0, 34.0, 20.0), @"End", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _trimEndField = makeNumericField(NSMakeRect(642.0, 402.0, 100.0, 24.0), @"0"); [content addSubview:_trimEndField];
    [content addSubview:makeButton(NSMakeRect(754.0, 400.0, 104.0, 28.0), @"Snap Start", self, @selector(snapTrimStartPressed:))];
    [content addSubview:makeButton(NSMakeRect(864.0, 400.0, 100.0, 28.0), @"Snap End", self, @selector(snapTrimEndPressed:))];
    [content addSubview:makeButton(NSMakeRect(1078.0, 400.0, 138.0, 28.0), @"Apply Trim", self, @selector(trimPressed:))];

    [content addSubview:makeLabel(NSMakeRect(382.0, 365.0, 70.0, 20.0), @"LOOP", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    [content addSubview:makeLabel(NSMakeRect(452.0, 365.0, 44.0, 20.0), @"Start", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _loopStartField = makeNumericField(NSMakeRect(495.0, 362.0, 100.0, 24.0), @"0"); [content addSubview:_loopStartField];
    [content addSubview:makeLabel(NSMakeRect(605.0, 365.0, 34.0, 20.0), @"End", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _loopEndField = makeNumericField(NSMakeRect(642.0, 362.0, 100.0, 24.0), @"0"); [content addSubview:_loopEndField];
    [content addSubview:makeButton(NSMakeRect(754.0, 360.0, 92.0, 28.0), @"Set Loop", self, @selector(setLoopPressed:))];
    [content addSubview:makeButton(NSMakeRect(852.0, 360.0, 92.0, 28.0), @"Loop Off", self, @selector(loopOffPressed:))];
    [content addSubview:makeButton(NSMakeRect(950.0, 360.0, 94.0, 28.0), @"Snap Start", self, @selector(snapLoopStartPressed:))];
    [content addSubview:makeButton(NSMakeRect(1050.0, 360.0, 92.0, 28.0), @"Snap End", self, @selector(snapLoopEndPressed:))];

    [content addSubview:makeLabel(NSMakeRect(382.0, 325.0, 108.0, 20.0), @"CROSSFADE", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    _crossfadeField = makeNumericField(NSMakeRect(495.0, 322.0, 100.0, 24.0), @"0"); [content addSubview:_crossfadeField];
    [content addSubview:makeLabel(NSMakeRect(603.0, 325.0, 54.0, 20.0), @"frames", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    [content addSubview:makeButton(NSMakeRect(670.0, 320.0, 174.0, 28.0), @"Apply Loop Crossfade", self, @selector(crossfadePressed:))];
    [content addSubview:makeLabel(NSMakeRect(862.0, 325.0, 90.0, 20.0), @"Zero radius", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _zeroRadiusField = makeNumericField(NSMakeRect(950.0, 322.0, 80.0, 24.0), @"256"); [content addSubview:_zeroRadiusField];

    [content addSubview:makeLabel(NSMakeRect(382.0, 285.0, 70.0, 20.0), @"FADES", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    [content addSubview:makeLabel(NSMakeRect(452.0, 285.0, 56.0, 20.0), @"Fade In", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _fadeInField = makeNumericField(NSMakeRect(510.0, 282.0, 92.0, 24.0), @"0"); [content addSubview:_fadeInField];
    [content addSubview:makeButton(NSMakeRect(610.0, 280.0, 90.0, 28.0), @"Apply", self, @selector(fadeInPressed:))];
    [content addSubview:makeLabel(NSMakeRect(720.0, 285.0, 64.0, 20.0), @"Fade Out", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _fadeOutField = makeNumericField(NSMakeRect(786.0, 282.0, 92.0, 24.0), @"0"); [content addSubview:_fadeOutField];
    [content addSubview:makeButton(NSMakeRect(886.0, 280.0, 90.0, 28.0), @"Apply", self, @selector(fadeOutPressed:))];
    [content addSubview:makeLabel(NSMakeRect(984.0, 285.0, 54.0, 20.0), @"frames", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];

    [content addSubview:makeLabel(NSMakeRect(382.0, 245.0, 70.0, 20.0), @"LEVEL", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    [content addSubview:makeLabel(NSMakeRect(452.0, 245.0, 58.0, 20.0), @"Gain dB", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _gainField = makeNumericField(NSMakeRect(512.0, 242.0, 80.0, 24.0), @"0.0"); [content addSubview:_gainField];
    [content addSubview:makeButton(NSMakeRect(600.0, 240.0, 96.0, 28.0), @"Apply Gain", self, @selector(gainPressed:))];
    [content addSubview:makeLabel(NSMakeRect(716.0, 245.0, 102.0, 20.0), @"Normalize dBFS", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _normalizeField = makeNumericField(NSMakeRect(820.0, 242.0, 80.0, 24.0), @"-1.0"); [content addSubview:_normalizeField];
    [content addSubview:makeButton(NSMakeRect(908.0, 240.0, 104.0, 28.0), @"Normalize", self, @selector(normalizePressed:))];
    [content addSubview:makeButton(NSMakeRect(1078.0, 240.0, 138.0, 28.0), @"Reverse Sample", self, @selector(reversePressed:))];

    [content addSubview:makeLabel(NSMakeRect(382.0, 205.0, 70.0, 20.0), @"TUNING", 12.0, NSFontWeightSemibold, (NSColor*)labelColor)];
    [content addSubview:makeLabel(NSMakeRect(452.0, 205.0, 62.0, 20.0), @"Root Key", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _rootKeyField = makeNumericField(NSMakeRect(516.0, 202.0, 70.0, 24.0), @"60"); [content addSubview:_rootKeyField];
    [content addSubview:makeLabel(NSMakeRect(606.0, 205.0, 72.0, 20.0), @"Fine cents", 11.0, NSFontWeightRegular, (NSColor*)labelColor)];
    _fineTuneField = makeNumericField(NSMakeRect(680.0, 202.0, 80.0, 24.0), @"0.0"); [content addSubview:_fineTuneField];
    [content addSubview:makeButton(NSMakeRect(770.0, 200.0, 120.0, 28.0), @"Apply Tuning", self, @selector(tuningPressed:))];

    _statusLabel = makeLabel(NSMakeRect(30.0, 82.0, 1218.0, 22.0), @"", 12.0, NSFontWeightMedium,
                             [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];

    _pathLabel = makeLabel(NSMakeRect(30.0, 52.0, 1218.0, 20.0), @"Bank not built yet", 11.0, NSFontWeightRegular,
                           [NSColor colorWithCalibratedWhite:0.52 alpha:1.0]);
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_pathLabel];
}

- (NSUInteger)selectedSampleIndex {
    const NSInteger row = _sampleTable.selectedRow;
    return row < 0 ? NSNotFound : static_cast<NSUInteger>(row);
}

- (void)refreshProjectView {
    const NSInteger oldSelection = _sampleTable.selectedRow;
    _sampleRows = [_documentModel sampleDisplayRows];
    [_sampleTable reloadData];
    _statusLabel.stringValue = [_documentModel statusSummary];

    if (_sampleRows.count == 0U) {
        [_sampleTable deselectAll:nil];
        [self refreshSelectedSample];
        return;
    }

    NSInteger selection = oldSelection;
    if (selection < 0 || static_cast<NSUInteger>(selection) >= _sampleRows.count) selection = 0;
    [_sampleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(selection)] byExtendingSelection:NO];
    [self refreshSelectedSample];
}

- (void)refreshSelectedSample {
    const NSUInteger index = [self selectedSampleIndex];
    if (index == NSNotFound) {
        _sampleTitleLabel.stringValue = @"No sample selected";
        _sampleInfoLabel.stringValue = @"";
        _waveformView.points = @[];
        _waveformView.totalFrames = 0U;
        _waveformView.loopEnabled = NO;
        [_waveformView setNeedsDisplay:YES];
        return;
    }

    NSDictionary<NSString*, id>* state = [_documentModel sampleStateAtIndex:index];
    if (state == nil) return;
    _sampleTitleLabel.stringValue = state[@"name"] ?: @"Sample";

    const unsigned int sampleRate = [state[@"sampleRate"] unsignedIntValue];
    const unsigned int channels = [state[@"channels"] unsignedIntValue];
    const unsigned long long totalFrames = [state[@"totalFrames"] unsignedLongLongValue];
    const float peakDb = [state[@"peakDb"] floatValue];
    _sampleInfoLabel.stringValue = [NSString stringWithFormat:@"%u Hz · %u channel%@ · %llu frames · peak %.2f dBFS",
                                    sampleRate, channels, channels == 1U ? @"" : @"s", totalFrames, peakDb];

    NSString* waveformError = nil;
    NSArray<NSNumber*>* waveform = [_documentModel waveformAtIndex:index pointCount:1200U error:&waveformError];
    if (waveform == nil) {
        _waveformView.points = @[];
        if (waveformError.length != 0U) _sampleInfoLabel.stringValue = waveformError;
    } else {
        _waveformView.points = waveform;
    }
    _waveformView.totalFrames = static_cast<uint64_t>(totalFrames);
    _waveformView.loopEnabled = [state[@"loopEnabled"] boolValue];
    _waveformView.loopStart = [state[@"loopStart"] unsignedLongLongValue];
    _waveformView.loopEnd = [state[@"loopEnd"] unsignedLongLongValue];
    [_waveformView setNeedsDisplay:YES];

    _trimStartField.stringValue = @"0";
    _trimEndField.stringValue = [NSString stringWithFormat:@"%llu", totalFrames];
    _loopStartField.stringValue = [NSString stringWithFormat:@"%llu", [state[@"loopStart"] unsignedLongLongValue]];
    _loopEndField.stringValue = [NSString stringWithFormat:@"%llu", [state[@"loopEnd"] unsignedLongLongValue]];
    _crossfadeField.stringValue = [NSString stringWithFormat:@"%u", [state[@"crossfadeFrames"] unsignedIntValue]];
    _rootKeyField.stringValue = [NSString stringWithFormat:@"%u", [state[@"rootKey"] unsignedIntValue]];
    _fineTuneField.stringValue = [NSString stringWithFormat:@"%.2f", [state[@"fineTuneCents"] floatValue]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_sampleRows.count);
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _sampleRows.count) return nil;
    NSTextField* cell = makeLabel(NSMakeRect(8.0, 4.0, 300.0, 22.0), _sampleRows[static_cast<NSUInteger>(row)], 11.0,
                                  NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
    cell.autoresizingMask = NSViewWidthSizable;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification;
    [self refreshSelectedSample];
}

- (BOOL)requireSelectedSample:(NSUInteger*)indexOut {
    const NSUInteger index = [self selectedSampleIndex];
    if (index == NSNotFound) {
        showMessage(self.window, @"No sample selected", @"Select a sample first.", NSAlertStyleWarning);
        return NO;
    }
    if (indexOut != nullptr) *indexOut = index;
    return YES;
}

- (BOOL)readUnsignedField:(NSTextField*)field label:(NSString*)label value:(uint64_t*)valueOut {
    std::uint64_t value = 0U;
    if (!parseUnsignedField(field, value)) {
        showMessage(self.window, @"Invalid numeric value",
                    [NSString stringWithFormat:@"%@ must be a non-negative whole number.", label], NSAlertStyleWarning);
        return NO;
    }
    if (valueOut != nullptr) *valueOut = value;
    return YES;
}

- (void)finishEditWithError:(NSString*)error title:(NSString*)title {
    if (error.length != 0U) {
        showMessage(self.window, title, error, NSAlertStyleCritical);
        return;
    }
    [self refreshProjectView];
}

- (void)importPressed:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Import sampler material";
    panel.prompt = @"Import";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.resolvesAliases = YES;
    panel.allowedFileTypes = @[@"kmp", @"KMP", @"ksc", @"KSC", @"ksf", @"KSF",
                               @"wav", @"WAV", @"wave", @"WAVE", @"aif", @"AIF", @"aiff", @"AIFF", @"aifc", @"AIFC"];

    if ([panel runModal] != NSModalResponseOK) return;
    NSMutableArray<NSString*>* paths = [NSMutableArray arrayWithCapacity:panel.URLs.count];
    for (NSURL* url in panel.URLs) {
        if (url.fileURL && url.path != nil) [paths addObject:url.path];
    }

    NSString* details = nil;
    if (![_documentModel importPaths:paths error:&details]) {
        showMessage(self.window, @"Import failed", details ?: @"No sampler material was imported.", NSAlertStyleCritical);
        return;
    }
    [self refreshProjectView];
    if (details.length != 0U) showMessage(self.window, @"Imported with warnings", details, NSAlertStyleWarning);
}

- (void)clearPressed:(id)sender {
    (void)sender;
    if (_sampleRows.count == 0U) return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Clear the current Manager project?";
    alert.informativeText = @"Imported and edited project-copy data will be cleared. Original source files and already built .sv banks are not deleted.";
    [alert addButtonWithTitle:@"Clear"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_documentModel clearProject];
    _pathLabel.stringValue = @"Bank not built yet";
    [self refreshProjectView];
}

- (void)buildPressed:(id)sender {
    (void)sender;
    if (_sampleRows.count == 0U) {
        showMessage(self.window, @"Nothing to build", @"Import at least one KMP/KSC/KSF/WAV/AIFF resource first.", NSAlertStyleWarning);
        return;
    }

    NSSavePanel* panel = [NSSavePanel savePanel];
    panel.title = @"Build SILVETON bank";
    panel.prompt = @"Build Bank";
    panel.nameFieldStringValue = @"SILVETON_BANK.sv";
    panel.allowedFileTypes = @[@"sv"];
    panel.allowsOtherFileTypes = NO;
    panel.canCreateDirectories = YES;
    if ([panel runModal] != NSModalResponseOK || panel.URL.path == nil) return;

    NSString* error = nil;
    NSString* summary = nil;
    if (![_documentModel buildBankAtPath:panel.URL.path error:&error summary:&summary]) {
        showMessage(self.window, @"Bank build failed", error ?: @"Unknown bank build error.", NSAlertStyleCritical);
        return;
    }

    _pathLabel.stringValue = [NSString stringWithFormat:@"Built: %@", panel.URL.path];
    showMessage(self.window, @"SILVETON bank built", summary ?: @"Bank build completed.", NSAlertStyleInformational);
}

- (void)trimPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t startFrame = 0U;
    uint64_t endFrame = 0U;
    if (![self readUnsignedField:_trimStartField label:@"Trim Start" value:&startFrame] ||
        ![self readUnsignedField:_trimEndField label:@"Trim End" value:&endFrame]) return;
    NSString* error = nil;
    [_documentModel trimSampleAtIndex:index startFrame:startFrame endFrame:endFrame error:&error];
    [self finishEditWithError:error title:@"Trim failed"];
}

- (void)setLoopPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t startFrame = 0U;
    uint64_t endFrame = 0U;
    if (![self readUnsignedField:_loopStartField label:@"Loop Start" value:&startFrame] ||
        ![self readUnsignedField:_loopEndField label:@"Loop End" value:&endFrame]) return;
    NSString* error = nil;
    [_documentModel setLoopForSampleAtIndex:index enabled:YES startFrame:startFrame endFrame:endFrame error:&error];
    [self finishEditWithError:error title:@"Set Loop failed"];
}

- (void)loopOffPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    NSString* error = nil;
    [_documentModel setLoopForSampleAtIndex:index enabled:NO startFrame:0U endFrame:0U error:&error];
    [self finishEditWithError:error title:@"Loop Off failed"];
}

- (void)crossfadePressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t requested = 0U;
    if (![self readUnsignedField:_crossfadeField label:@"Loop Crossfade" value:&requested]) return;
    if (requested > UINT32_MAX) {
        showMessage(self.window, @"Crossfade failed", @"Crossfade frame count is too large.", NSAlertStyleWarning);
        return;
    }
    NSString* error = nil;
    [_documentModel applyLoopCrossfadeForSampleAtIndex:index frames:static_cast<uint32_t>(requested) error:&error];
    [self finishEditWithError:error title:@"Crossfade failed"];
}

- (void)fadeInPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frames = 0U;
    if (![self readUnsignedField:_fadeInField label:@"Fade In" value:&frames]) return;
    NSString* error = nil;
    [_documentModel fadeInSampleAtIndex:index frames:frames error:&error];
    [self finishEditWithError:error title:@"Fade In failed"];
}

- (void)fadeOutPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frames = 0U;
    if (![self readUnsignedField:_fadeOutField label:@"Fade Out" value:&frames]) return;
    NSString* error = nil;
    [_documentModel fadeOutSampleAtIndex:index frames:frames error:&error];
    [self finishEditWithError:error title:@"Fade Out failed"];
}

- (void)gainPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    NSString* error = nil;
    [_documentModel applyGainForSampleAtIndex:index gainDb:_gainField.floatValue error:&error];
    [self finishEditWithError:error title:@"Gain failed"];
}

- (void)normalizePressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    NSString* error = nil;
    [_documentModel normalizeSampleAtIndex:index targetPeakDb:_normalizeField.floatValue error:&error];
    [self finishEditWithError:error title:@"Normalize failed"];
}

- (void)reversePressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    NSString* error = nil;
    [_documentModel reverseSampleAtIndex:index error:&error];
    [self finishEditWithError:error title:@"Reverse failed"];
}

- (void)tuningPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    const NSInteger root = _rootKeyField.integerValue;
    const float cents = _fineTuneField.floatValue;
    if (root < 0 || root > 127) {
        showMessage(self.window, @"Tuning failed", @"Root Key must be between 0 and 127.", NSAlertStyleWarning);
        return;
    }
    if (cents < -100.0F || cents > 100.0F) {
        showMessage(self.window, @"Tuning failed", @"Fine Tune must be between -100 and +100 cents.", NSAlertStyleWarning);
        return;
    }

    NSString* error = nil;
    if (![_documentModel setRootKeyForSampleAtIndex:index rootKey:static_cast<uint8_t>(root) error:&error]) {
        [self finishEditWithError:error title:@"Tuning failed"];
        return;
    }
    if (![_documentModel setFineTuneForSampleAtIndex:index cents:cents error:&error]) {
        [self finishEditWithError:error title:@"Tuning failed"];
        return;
    }
    [self finishEditWithError:nil title:@"Tuning failed"];
}

- (BOOL)readZeroRadius:(uint64_t*)radiusOut {
    return [self readUnsignedField:_zeroRadiusField label:@"Zero radius" value:radiusOut];
}

- (void)snapTrimStartPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frame = 0U;
    uint64_t radius = 0U;
    if (![self readUnsignedField:_trimStartField label:@"Trim Start" value:&frame] || ![self readZeroRadius:&radius]) return;
    const uint64_t snapped = [_documentModel nearestZeroCrossingForSampleAtIndex:index frame:frame radius:radius];
    _trimStartField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(snapped)];
}

- (void)snapTrimEndPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frame = 0U;
    uint64_t radius = 0U;
    if (![self readUnsignedField:_trimEndField label:@"Trim End" value:&frame] || ![self readZeroRadius:&radius]) return;
    const uint64_t snapped = [_documentModel nearestZeroCrossingForSampleAtIndex:index frame:frame radius:radius];
    _trimEndField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(snapped)];
}

- (void)snapLoopStartPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frame = 0U;
    uint64_t radius = 0U;
    if (![self readUnsignedField:_loopStartField label:@"Loop Start" value:&frame] || ![self readZeroRadius:&radius]) return;
    const uint64_t snapped = [_documentModel nearestZeroCrossingForSampleAtIndex:index frame:frame radius:radius];
    _loopStartField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(snapped)];
}

- (void)snapLoopEndPressed:(id)sender {
    (void)sender;
    NSUInteger index = 0U; if (![self requireSelectedSample:&index]) return;
    uint64_t frame = 0U;
    uint64_t radius = 0U;
    if (![self readUnsignedField:_loopEndField label:@"Loop End" value:&frame] || ![self readZeroRadius:&radius]) return;
    const uint64_t snapped = [_documentModel nearestZeroCrossingForSampleAtIndex:index frame:frame radius:radius];
    _loopEndField.stringValue = [NSString stringWithFormat:@"%llu", static_cast<unsigned long long>(snapped)];
}

@end
