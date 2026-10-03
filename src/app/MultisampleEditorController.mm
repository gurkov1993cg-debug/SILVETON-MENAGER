#import <AppKit/AppKit.h>

#include <cerrno>
#include <cmath>
#include <cstdint>
#include <cstdlib>

@interface SVManagerDocument : NSObject
- (NSArray<NSString*>*)sampleDisplayRows;
- (NSArray<NSString*>*)multisampleDisplayRows;
- (NSDictionary<NSString*, id>*)multisampleStateAtIndex:(NSUInteger)index;
- (NSArray<NSDictionary<NSString*, id>*>*)zoneStatesForMultisampleAtIndex:(NSUInteger)index;
- (BOOL)createMultisampleNamed:(NSString*)name sampleIndexes:(NSIndexSet*)sampleIndexes error:(NSString**)error createdIndex:(NSUInteger*)createdIndex;
- (BOOL)renameMultisampleAtIndex:(NSUInteger)index name:(NSString*)name error:(NSString**)error;
- (BOOL)addZoneToMultisampleAtIndex:(NSUInteger)multisampleIndex sampleIndex:(NSUInteger)sampleIndex error:(NSString**)error;
- (BOOL)removeZoneFromMultisampleAtIndex:(NSUInteger)multisampleIndex zoneIndex:(NSUInteger)zoneIndex error:(NSString**)error;
- (BOOL)updateZoneAtMultisampleIndex:(NSUInteger)multisampleIndex
                           zoneIndex:(NSUInteger)zoneIndex
                         sampleIndex:(NSUInteger)sampleIndex
                              keyLow:(NSUInteger)keyLow
                             keyHigh:(NSUInteger)keyHigh
                         velocityLow:(NSUInteger)velocityLow
                        velocityHigh:(NSUInteger)velocityHigh
                             rootKey:(NSUInteger)rootKey
                  transposeSemitones:(NSInteger)transposeSemitones
                           tuneCents:(float)tuneCents
                              gainDb:(float)gainDb
                                 pan:(float)pan
                               error:(NSString**)error;
@end

namespace {

NSTextField* SVLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
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

NSTextField* SVField(NSRect frame, NSString* text) {
    NSTextField* field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = text ?: @"";
    field.bezeled = YES;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.backgroundColor = [NSColor colorWithCalibratedRed:0.085 green:0.098 blue:0.112 alpha:1.0];
    field.textColor = [NSColor colorWithCalibratedWhite:0.94 alpha:1.0];
    field.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    field.alignment = NSTextAlignmentRight;
    return field;
}

NSButton* SVButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void SVAlert(NSWindow* window, NSString* title, NSString* message, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Multisample Editor";
    alert.informativeText = message ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

BOOL SVParseInteger(NSTextField* field, NSInteger* valueOut) {
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0U) return NO;
    const char* value = text.UTF8String;
    if (value == nullptr) return NO;
    errno = 0;
    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (errno == ERANGE || end == value || end == nullptr || *end != '\0') return NO;
    if (valueOut != nullptr) *valueOut = static_cast<NSInteger>(parsed);
    return YES;
}

BOOL SVParseFloat(NSTextField* field, float* valueOut) {
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0U) return NO;
    const char* value = text.UTF8String;
    if (value == nullptr) return NO;
    errno = 0;
    char* end = nullptr;
    const float parsed = std::strtof(value, &end);
    if (errno == ERANGE || end == value || end == nullptr || *end != '\0' || !std::isfinite(parsed)) return NO;
    if (valueOut != nullptr) *valueOut = parsed;
    return YES;
}

BOOL SVBlackKey(NSUInteger note) {
    const NSUInteger pitchClass = note % 12U;
    return pitchClass == 1U || pitchClass == 3U || pitchClass == 6U || pitchClass == 8U || pitchClass == 10U;
}

} // namespace

@interface SVZoneMapView : NSView
@property(nonatomic, copy) NSArray<NSDictionary<NSString*, id>*>* zones;
@property(nonatomic) NSInteger selectedZone;
@end

@implementation SVZoneMapView

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    const NSRect bounds = self.bounds;
    [[NSColor colorWithCalibratedRed:0.040 green:0.048 blue:0.057 alpha:1.0] setFill];
    NSRectFill(bounds);

    const CGFloat width = NSWidth(bounds);
    const CGFloat height = NSHeight(bounds);
    const CGFloat keyboardTop = MAX(62.0, height - 68.0);
    const CGFloat noteWidth = width / 128.0;

    for (NSUInteger note = 0U; note < 128U; ++note) {
        const CGFloat x = static_cast<CGFloat>(note) * noteWidth;
        const NSRect keyRect = NSMakeRect(x, keyboardTop, MAX(1.0, noteWidth), height - keyboardTop);
        NSColor* fill = SVBlackKey(note)
            ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
            : [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
        [fill setFill];
        NSRectFill(keyRect);

        [[NSColor colorWithCalibratedWhite:0.30 alpha:1.0] setStroke];
        NSBezierPath* separator = [NSBezierPath bezierPath];
        [separator moveToPoint:NSMakePoint(x, keyboardTop)];
        [separator lineToPoint:NSMakePoint(x, height)];
        [separator stroke];

        if ((note % 12U) == 0U && note < 120U) {
            NSString* octave = [NSString stringWithFormat:@"C%ld", static_cast<long>(note / 12U) - 1L];
            NSDictionary* attrs = @{
                NSFontAttributeName: [NSFont systemFontOfSize:9.0 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: SVBlackKey(note)
                    ? [NSColor colorWithCalibratedWhite:0.95 alpha:1.0]
                    : [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]
            };
            [octave drawAtPoint:NSMakePoint(x + 2.0, keyboardTop + 4.0) withAttributes:attrs];
        }
    }

    for (NSUInteger index = 0U; index < self.zones.count; ++index) {
        NSDictionary<NSString*, id>* zone = self.zones[index];
        const NSUInteger low = MIN(127U, [zone[@"keyLow"] unsignedIntegerValue]);
        const NSUInteger high = MIN(127U, [zone[@"keyHigh"] unsignedIntegerValue]);
        if (high < low) continue;

        const CGFloat x = static_cast<CGFloat>(low) * noteWidth;
        const CGFloat zoneWidth = static_cast<CGFloat>(high - low + 1U) * noteWidth;
        const CGFloat top = 10.0 + static_cast<CGFloat>(index % 4U) * 18.0;
        const CGFloat zoneHeight = MAX(15.0, keyboardTop - top - 8.0);
        const BOOL selected = static_cast<NSInteger>(index) == self.selectedZone;

        NSColor* fill = selected
            ? [NSColor colorWithCalibratedRed:0.22 green:0.67 blue:0.98 alpha:0.72]
            : [NSColor colorWithCalibratedRed:0.20 green:0.52 blue:0.82 alpha:0.34];
        [fill setFill];
        NSBezierPath* box = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(x, top, MAX(2.0, zoneWidth), zoneHeight)
                                                            xRadius:3.0 yRadius:3.0];
        [box fill];
        [[NSColor colorWithCalibratedRed:0.49 green:0.81 blue:1.0 alpha:selected ? 1.0 : 0.65] setStroke];
        box.lineWidth = selected ? 2.0 : 1.0;
        [box stroke];

        NSString* name = zone[@"sampleName"] ?: @"Sample";
        NSString* text = [NSString stringWithFormat:@"%lu  %@", static_cast<unsigned long>(index + 1U), name];
        NSDictionary* attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10.0 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor whiteColor]
        };
        [text drawInRect:NSInsetRect(box.bounds, 5.0, 3.0) withAttributes:attrs];
    }

    [[NSColor colorWithCalibratedWhite:0.30 alpha:1.0] setStroke];
    NSFrameRect(bounds);
}

@end

@interface SVSamplePickerDataSource : NSObject <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithRows:(NSArray<NSString*>*)rows;
@end

@implementation SVSamplePickerDataSource {
    NSArray<NSString*>* _rows;
}

- (instancetype)initWithRows:(NSArray<NSString*>*)rows {
    self = [super init];
    if (self) _rows = [rows copy] ?: @[];
    return self;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_rows.count);
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _rows.count) return nil;
    return SVLabel(NSMakeRect(6.0, 3.0, 494.0, 20.0), _rows[static_cast<NSUInteger>(row)], 11.0,
                   NSFontWeightRegular, [NSColor labelColor]);
}

@end

@interface SVMultisampleWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@implementation SVMultisampleWindowController {
    SVManagerDocument* _documentModel;
    NSTableView* _multisampleTable;
    NSTableView* _zoneTable;
    SVZoneMapView* _zoneMap;
    NSTextField* _nameField;
    NSPopUpButton* _samplePopup;
    NSTextField* _keyLowField;
    NSTextField* _keyHighField;
    NSTextField* _velocityLowField;
    NSTextField* _velocityHighField;
    NSTextField* _rootKeyField;
    NSTextField* _transposeField;
    NSTextField* _tuneField;
    NSTextField* _gainField;
    NSTextField* _panField;
    NSTextField* _statusLabel;
    NSArray<NSString*>* _multisampleRows;
    NSArray<NSString*>* _sampleRows;
    NSArray<NSDictionary<NSString*, id>*>* _zoneRows;
    NSUInteger _preferredMultisampleIndex;
    SVSamplePickerDataSource* _samplePickerDataSource;
}

- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel {
    const NSRect frame = NSMakeRect(0.0, 0.0, 1260.0, 790.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:frame
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Manager — Multisample Editor";
    window.minSize = NSMakeSize(1050.0, 690.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        _documentModel = documentModel;
        _multisampleRows = @[];
        _sampleRows = @[];
        _zoneRows = @[];
        _preferredMultisampleIndex = NSNotFound;
        [self buildInterface];
        [self refreshFromDocument];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    content.autoresizesSubviews = YES;
    NSColor* titleColor = [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0];
    NSColor* textColor = [NSColor colorWithCalibratedWhite:0.78 alpha:1.0];

    [content addSubview:SVLabel(NSMakeRect(26.0, 742.0, 520.0, 30.0), @"MULTISAMPLE EDITOR", 22.0, NSFontWeightSemibold, titleColor)];
    [content addSubview:SVLabel(NSMakeRect(28.0, 719.0, 900.0, 20.0),
                                @"Nothing is changed automatically — use Create / Apply / Add / Remove explicitly.",
                                11.0, NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.62 alpha:1.0])];

    [content addSubview:SVButton(NSMakeRect(28.0, 677.0, 162.0, 30.0), @"New from Samples…", self, @selector(newMultisamplePressed:))];
    [content addSubview:SVButton(NSMakeRect(198.0, 677.0, 110.0, 30.0), @"Refresh", self, @selector(refreshPressed:))];

    NSScrollView* msScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(28.0, 116.0, 300.0, 548.0)];
    msScroll.hasVerticalScroller = YES;
    msScroll.borderType = NSBezelBorder;
    msScroll.drawsBackground = YES;
    msScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    msScroll.autoresizingMask = NSViewHeightSizable;
    _multisampleTable = [[NSTableView alloc] initWithFrame:msScroll.bounds];
    _multisampleTable.headerView = nil;
    _multisampleTable.rowHeight = 29.0;
    _multisampleTable.backgroundColor = msScroll.backgroundColor;
    _multisampleTable.dataSource = self;
    _multisampleTable.delegate = self;
    NSTableColumn* msColumn = [[NSTableColumn alloc] initWithIdentifier:@"multisample"];
    msColumn.width = 286.0;
    msColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_multisampleTable addTableColumn:msColumn];
    msScroll.documentView = _multisampleTable;
    [content addSubview:msScroll];

    [content addSubview:SVLabel(NSMakeRect(350.0, 682.0, 48.0, 20.0), @"Name", 11.0, NSFontWeightRegular, textColor)];
    _nameField = SVField(NSMakeRect(400.0, 678.0, 360.0, 26.0), @"");
    _nameField.alignment = NSTextAlignmentLeft;
    [content addSubview:_nameField];
    [content addSubview:SVButton(NSMakeRect(770.0, 676.0, 110.0, 30.0), @"Apply Name", self, @selector(renamePressed:))];

    _zoneMap = [[SVZoneMapView alloc] initWithFrame:NSMakeRect(350.0, 468.0, 880.0, 192.0)];
    _zoneMap.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _zoneMap.selectedZone = -1;
    [content addSubview:_zoneMap];

    [content addSubview:SVLabel(NSMakeRect(350.0, 443.0, 170.0, 20.0), @"Zones", 13.0, NSFontWeightSemibold, textColor)];
    [content addSubview:SVButton(NSMakeRect(970.0, 438.0, 116.0, 28.0), @"Add Zone", self, @selector(addZonePressed:))];
    [content addSubview:SVButton(NSMakeRect(1094.0, 438.0, 136.0, 28.0), @"Remove Zone", self, @selector(removeZonePressed:))];

    NSScrollView* zoneScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(350.0, 265.0, 880.0, 170.0)];
    zoneScroll.hasVerticalScroller = YES;
    zoneScroll.borderType = NSBezelBorder;
    zoneScroll.drawsBackground = YES;
    zoneScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    zoneScroll.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _zoneTable = [[NSTableView alloc] initWithFrame:zoneScroll.bounds];
    _zoneTable.headerView = nil;
    _zoneTable.rowHeight = 27.0;
    _zoneTable.backgroundColor = zoneScroll.backgroundColor;
    _zoneTable.dataSource = self;
    _zoneTable.delegate = self;
    NSTableColumn* zoneColumn = [[NSTableColumn alloc] initWithIdentifier:@"zone"];
    zoneColumn.width = 864.0;
    zoneColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_zoneTable addTableColumn:zoneColumn];
    zoneScroll.documentView = _zoneTable;
    [content addSubview:zoneScroll];

    [content addSubview:SVLabel(NSMakeRect(350.0, 235.0, 56.0, 20.0), @"Sample", 11.0, NSFontWeightRegular, textColor)];
    _samplePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(410.0, 230.0, 300.0, 28.0) pullsDown:NO];
    [content addSubview:_samplePopup];

    [content addSubview:SVLabel(NSMakeRect(728.0, 235.0, 52.0, 20.0), @"Key Lo", 11.0, NSFontWeightRegular, textColor)];
    _keyLowField = SVField(NSMakeRect(780.0, 232.0, 58.0, 24.0), @"0"); [content addSubview:_keyLowField];
    [content addSubview:SVLabel(NSMakeRect(846.0, 235.0, 52.0, 20.0), @"Key Hi", 11.0, NSFontWeightRegular, textColor)];
    _keyHighField = SVField(NSMakeRect(898.0, 232.0, 58.0, 24.0), @"127"); [content addSubview:_keyHighField];
    [content addSubview:SVLabel(NSMakeRect(968.0, 235.0, 44.0, 20.0), @"Root", 11.0, NSFontWeightRegular, textColor)];
    _rootKeyField = SVField(NSMakeRect(1012.0, 232.0, 58.0, 24.0), @"60"); [content addSubview:_rootKeyField];

    [content addSubview:SVLabel(NSMakeRect(350.0, 197.0, 52.0, 20.0), @"Vel Lo", 11.0, NSFontWeightRegular, textColor)];
    _velocityLowField = SVField(NSMakeRect(404.0, 194.0, 58.0, 24.0), @"1"); [content addSubview:_velocityLowField];
    [content addSubview:SVLabel(NSMakeRect(470.0, 197.0, 52.0, 20.0), @"Vel Hi", 11.0, NSFontWeightRegular, textColor)];
    _velocityHighField = SVField(NSMakeRect(522.0, 194.0, 58.0, 24.0), @"127"); [content addSubview:_velocityHighField];
    [content addSubview:SVLabel(NSMakeRect(598.0, 197.0, 72.0, 20.0), @"Transpose", 11.0, NSFontWeightRegular, textColor)];
    _transposeField = SVField(NSMakeRect(670.0, 194.0, 62.0, 24.0), @"0"); [content addSubview:_transposeField];
    [content addSubview:SVLabel(NSMakeRect(746.0, 197.0, 66.0, 20.0), @"Tune ct", 11.0, NSFontWeightRegular, textColor)];
    _tuneField = SVField(NSMakeRect(814.0, 194.0, 70.0, 24.0), @"0.0"); [content addSubview:_tuneField];
    [content addSubview:SVLabel(NSMakeRect(898.0, 197.0, 58.0, 20.0), @"Gain dB", 11.0, NSFontWeightRegular, textColor)];
    _gainField = SVField(NSMakeRect(956.0, 194.0, 70.0, 24.0), @"0.0"); [content addSubview:_gainField];
    [content addSubview:SVLabel(NSMakeRect(1040.0, 197.0, 32.0, 20.0), @"Pan", 11.0, NSFontWeightRegular, textColor)];
    _panField = SVField(NSMakeRect(1074.0, 194.0, 70.0, 24.0), @"0.0"); [content addSubview:_panField];
    [content addSubview:SVButton(NSMakeRect(1152.0, 191.0, 78.0, 30.0), @"Apply", self, @selector(applyZonePressed:))];

    _statusLabel = SVLabel(NSMakeRect(350.0, 145.0, 880.0, 38.0), @"", 11.0, NSFontWeightRegular,
                           [NSColor colorWithCalibratedRed:0.46 green:0.73 blue:0.97 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];
    [content addSubview:SVLabel(NSMakeRect(350.0, 116.0, 880.0, 22.0),
                                @"Zones use the same Manager project that is later written to SILVETON_BANK.sv.",
                                10.0, NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.54 alpha:1.0])];
}

- (NSUInteger)selectedMultisampleIndex {
    return _multisampleTable.selectedRow < 0 ? NSNotFound : static_cast<NSUInteger>(_multisampleTable.selectedRow);
}

- (NSUInteger)selectedZoneIndex {
    return _zoneTable.selectedRow < 0 ? NSNotFound : static_cast<NSUInteger>(_zoneTable.selectedRow);
}

- (void)refreshFromDocument {
    const NSInteger oldSelection = _multisampleTable.selectedRow;
    _multisampleRows = [_documentModel multisampleDisplayRows] ?: @[];
    _sampleRows = [_documentModel sampleDisplayRows] ?: @[];
    [_multisampleTable reloadData];

    [_samplePopup removeAllItems];
    for (NSString* row in _sampleRows) [_samplePopup addItemWithTitle:row];

    if (_multisampleRows.count == 0U) {
        _zoneRows = @[];
        [_zoneTable reloadData];
        _zoneMap.zones = @[];
        _zoneMap.selectedZone = -1;
        [_zoneMap setNeedsDisplay:YES];
        _nameField.stringValue = @"";
        _statusLabel.stringValue = @"No multisamples in the current project.";
        return;
    }

    NSUInteger selection = 0U;
    if (_preferredMultisampleIndex != NSNotFound && _preferredMultisampleIndex < _multisampleRows.count) {
        selection = _preferredMultisampleIndex;
    } else if (oldSelection >= 0 && static_cast<NSUInteger>(oldSelection) < _multisampleRows.count) {
        selection = static_cast<NSUInteger>(oldSelection);
    }
    _preferredMultisampleIndex = NSNotFound;
    [_multisampleTable selectRowIndexes:[NSIndexSet indexSetWithIndex:selection] byExtendingSelection:NO];
    [self refreshSelectedMultisample];
}

- (void)refreshSelectedMultisample {
    const NSUInteger msIndex = [self selectedMultisampleIndex];
    if (msIndex == NSNotFound) {
        _zoneRows = @[];
        [_zoneTable reloadData];
        _zoneMap.zones = @[];
        _zoneMap.selectedZone = -1;
        [_zoneMap setNeedsDisplay:YES];
        return;
    }

    NSDictionary<NSString*, id>* state = [_documentModel multisampleStateAtIndex:msIndex];
    _nameField.stringValue = state[@"name"] ?: @"";
    _zoneRows = [_documentModel zoneStatesForMultisampleAtIndex:msIndex] ?: @[];
    [_zoneTable reloadData];
    _zoneMap.zones = _zoneRows;
    _zoneMap.selectedZone = -1;
    [_zoneMap setNeedsDisplay:YES];

    _statusLabel.stringValue = [NSString stringWithFormat:@"Multisample %lu / %lu · %@ · %lu zone%@ · %lu available samples",
                                static_cast<unsigned long>(msIndex + 1U),
                                static_cast<unsigned long>(_multisampleRows.count),
                                state[@"name"] ?: @"Unnamed",
                                static_cast<unsigned long>(_zoneRows.count),
                                _zoneRows.count == 1U ? @"" : @"s",
                                static_cast<unsigned long>(_sampleRows.count)];
    if (_zoneRows.count > 0U) {
        [_zoneTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0U] byExtendingSelection:NO];
        [self refreshSelectedZone];
    }
}

- (void)refreshSelectedZone {
    const NSUInteger zoneIndex = [self selectedZoneIndex];
    if (zoneIndex == NSNotFound || zoneIndex >= _zoneRows.count) {
        _zoneMap.selectedZone = -1;
        [_zoneMap setNeedsDisplay:YES];
        return;
    }

    NSDictionary<NSString*, id>* zone = _zoneRows[zoneIndex];
    const NSUInteger sampleIndex = [zone[@"sampleIndex"] unsignedIntegerValue];
    if (sampleIndex < static_cast<NSUInteger>(_samplePopup.numberOfItems)) {
        [_samplePopup selectItemAtIndex:static_cast<NSInteger>(sampleIndex)];
    }
    _keyLowField.integerValue = [zone[@"keyLow"] integerValue];
    _keyHighField.integerValue = [zone[@"keyHigh"] integerValue];
    _velocityLowField.integerValue = [zone[@"velocityLow"] integerValue];
    _velocityHighField.integerValue = [zone[@"velocityHigh"] integerValue];
    _rootKeyField.integerValue = [zone[@"rootKey"] integerValue];
    _transposeField.integerValue = [zone[@"transposeSemitones"] integerValue];
    _tuneField.floatValue = [zone[@"tuneCents"] floatValue];
    _gainField.floatValue = [zone[@"gainDb"] floatValue];
    _panField.floatValue = [zone[@"pan"] floatValue];
    _zoneMap.selectedZone = static_cast<NSInteger>(zoneIndex);
    [_zoneMap setNeedsDisplay:YES];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _multisampleTable) return static_cast<NSInteger>(_multisampleRows.count);
    if (tableView == _zoneTable) return static_cast<NSInteger>(_zoneRows.count);
    return 0;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0) return nil;
    NSString* text = @"";
    CGFloat width = NSWidth(tableView.bounds) - 12.0;

    if (tableView == _multisampleTable) {
        if (static_cast<NSUInteger>(row) >= _multisampleRows.count) return nil;
        text = _multisampleRows[static_cast<NSUInteger>(row)];
    } else if (tableView == _zoneTable) {
        if (static_cast<NSUInteger>(row) >= _zoneRows.count) return nil;
        NSDictionary<NSString*, id>* zone = _zoneRows[static_cast<NSUInteger>(row)];
        text = [NSString stringWithFormat:@"%02ld  %@ · K %03ld–%03ld · V %03ld–%03ld · Root %03ld · Tr %+ld · Tune %+.1f · Gain %+.1f dB · Pan %+.2f",
                static_cast<long>(row + 1), zone[@"sampleName"] ?: @"Sample",
                static_cast<long>([zone[@"keyLow"] integerValue]), static_cast<long>([zone[@"keyHigh"] integerValue]),
                static_cast<long>([zone[@"velocityLow"] integerValue]), static_cast<long>([zone[@"velocityHigh"] integerValue]),
                static_cast<long>([zone[@"rootKey"] integerValue]), static_cast<long>([zone[@"transposeSemitones"] integerValue]),
                [zone[@"tuneCents"] floatValue], [zone[@"gainDb"] floatValue], [zone[@"pan"] floatValue]];
    }

    NSTextField* cell = SVLabel(NSMakeRect(6.0, 3.0, width, 21.0), text, 10.5, NSFontWeightRegular,
                                [NSColor colorWithCalibratedWhite:0.89 alpha:1.0]);
    cell.autoresizingMask = NSViewWidthSizable;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _multisampleTable) [self refreshSelectedMultisample];
    else if (notification.object == _zoneTable) [self refreshSelectedZone];
}

- (void)refreshPressed:(id)sender {
    (void)sender;
    [self refreshFromDocument];
}

- (void)renamePressed:(id)sender {
    (void)sender;
    const NSUInteger msIndex = [self selectedMultisampleIndex];
    if (msIndex == NSNotFound) {
        SVAlert(self.window, @"No multisample selected", @"Select a multisample first.", NSAlertStyleWarning);
        return;
    }
    NSString* error = nil;
    if (![_documentModel renameMultisampleAtIndex:msIndex name:_nameField.stringValue error:&error]) {
        SVAlert(self.window, @"Rename failed", error, NSAlertStyleCritical);
        return;
    }
    _preferredMultisampleIndex = msIndex;
    [self refreshFromDocument];
}

- (void)addZonePressed:(id)sender {
    (void)sender;
    const NSUInteger msIndex = [self selectedMultisampleIndex];
    if (msIndex == NSNotFound) {
        SVAlert(self.window, @"No multisample selected", @"Select a multisample first.", NSAlertStyleWarning);
        return;
    }
    if (_samplePopup.indexOfSelectedItem < 0) {
        SVAlert(self.window, @"No sample selected", @"Choose a sample for the new zone.", NSAlertStyleWarning);
        return;
    }
    NSString* error = nil;
    const NSUInteger sampleIndex = static_cast<NSUInteger>(_samplePopup.indexOfSelectedItem);
    if (![_documentModel addZoneToMultisampleAtIndex:msIndex sampleIndex:sampleIndex error:&error]) {
        SVAlert(self.window, @"Add Zone failed", error, NSAlertStyleCritical);
        return;
    }
    _preferredMultisampleIndex = msIndex;
    [self refreshFromDocument];
    if (_zoneRows.count > 0U) {
        const NSUInteger newIndex = _zoneRows.count - 1U;
        [_zoneTable selectRowIndexes:[NSIndexSet indexSetWithIndex:newIndex] byExtendingSelection:NO];
        [self refreshSelectedZone];
    }
}

- (void)removeZonePressed:(id)sender {
    (void)sender;
    const NSUInteger msIndex = [self selectedMultisampleIndex];
    const NSUInteger zoneIndex = [self selectedZoneIndex];
    if (msIndex == NSNotFound || zoneIndex == NSNotFound) {
        SVAlert(self.window, @"No zone selected", @"Select a zone first.", NSAlertStyleWarning);
        return;
    }
    NSString* error = nil;
    if (![_documentModel removeZoneFromMultisampleAtIndex:msIndex zoneIndex:zoneIndex error:&error]) {
        SVAlert(self.window, @"Remove Zone failed", error, NSAlertStyleCritical);
        return;
    }
    _preferredMultisampleIndex = msIndex;
    [self refreshFromDocument];
}

- (void)applyZonePressed:(id)sender {
    (void)sender;
    const NSUInteger msIndex = [self selectedMultisampleIndex];
    const NSUInteger zoneIndex = [self selectedZoneIndex];
    if (msIndex == NSNotFound || zoneIndex == NSNotFound) {
        SVAlert(self.window, @"No zone selected", @"Select a zone first.", NSAlertStyleWarning);
        return;
    }
    if (_samplePopup.indexOfSelectedItem < 0) {
        SVAlert(self.window, @"Invalid sample", @"Choose a valid sample assignment.", NSAlertStyleWarning);
        return;
    }

    NSInteger keyLow = 0, keyHigh = 0, velocityLow = 0, velocityHigh = 0, rootKey = 0, transpose = 0;
    float tune = 0.0F, gain = 0.0F, pan = 0.0F;
    if (!SVParseInteger(_keyLowField, &keyLow) || !SVParseInteger(_keyHighField, &keyHigh) ||
        !SVParseInteger(_velocityLowField, &velocityLow) || !SVParseInteger(_velocityHighField, &velocityHigh) ||
        !SVParseInteger(_rootKeyField, &rootKey) || !SVParseInteger(_transposeField, &transpose) ||
        !SVParseFloat(_tuneField, &tune) || !SVParseFloat(_gainField, &gain) || !SVParseFloat(_panField, &pan)) {
        SVAlert(self.window, @"Invalid zone values", @"All zone fields must contain valid numeric values.", NSAlertStyleWarning);
        return;
    }
    if (keyLow < 0 || keyHigh < 0 || velocityLow < 0 || velocityHigh < 0 || rootKey < 0) {
        SVAlert(self.window, @"Invalid zone values", @"Key, velocity and Root values cannot be negative.", NSAlertStyleWarning);
        return;
    }

    NSString* error = nil;
    const BOOL ok = [_documentModel updateZoneAtMultisampleIndex:msIndex
                                                       zoneIndex:zoneIndex
                                                     sampleIndex:static_cast<NSUInteger>(_samplePopup.indexOfSelectedItem)
                                                          keyLow:static_cast<NSUInteger>(keyLow)
                                                         keyHigh:static_cast<NSUInteger>(keyHigh)
                                                     velocityLow:static_cast<NSUInteger>(velocityLow)
                                                    velocityHigh:static_cast<NSUInteger>(velocityHigh)
                                                         rootKey:static_cast<NSUInteger>(rootKey)
                                              transposeSemitones:transpose
                                                       tuneCents:tune
                                                          gainDb:gain
                                                             pan:pan
                                                           error:&error];
    if (!ok) {
        SVAlert(self.window, @"Apply Zone failed", error, NSAlertStyleCritical);
        return;
    }

    _preferredMultisampleIndex = msIndex;
    [self refreshFromDocument];
    if (zoneIndex < _zoneRows.count) {
        [_zoneTable selectRowIndexes:[NSIndexSet indexSetWithIndex:zoneIndex] byExtendingSelection:NO];
        [self refreshSelectedZone];
    }
}

- (void)newMultisamplePressed:(id)sender {
    (void)sender;
    if (_sampleRows.count == 0U) {
        SVAlert(self.window, @"No samples available", @"Import samples before creating a multisample.", NSAlertStyleWarning);
        return;
    }

    NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 520.0, 300.0)];
    [accessory addSubview:SVLabel(NSMakeRect(0.0, 276.0, 80.0, 20.0), @"Name", 11.0, NSFontWeightRegular, [NSColor labelColor])];
    NSTextField* nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(82.0, 272.0, 438.0, 26.0)];
    nameField.stringValue = @"New Multisample";
    [accessory addSubview:nameField];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 520.0, 260.0)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTableView* table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    table.headerView = nil;
    table.rowHeight = 26.0;
    table.allowsMultipleSelection = YES;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"sampleSelection"];
    column.width = 505.0;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [table addTableColumn:column];

    _samplePickerDataSource = [[SVSamplePickerDataSource alloc] initWithRows:_sampleRows];
    table.dataSource = _samplePickerDataSource;
    table.delegate = _samplePickerDataSource;
    scroll.documentView = table;
    [accessory addSubview:scroll];
    [table reloadData];

    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Create Multisample";
    alert.informativeText = @"Select samples to map. Root-Key mapping is performed only after you press Create.";
    alert.accessoryView = accessory;
    [alert addButtonWithTitle:@"Create"];
    [alert addButtonWithTitle:@"Cancel"];
    const NSModalResponse response = [alert runModal];

    NSIndexSet* selected = [table.selectedRowIndexes copy];
    NSString* name = [nameField.stringValue copy];
    table.dataSource = nil;
    table.delegate = nil;
    _samplePickerDataSource = nil;

    if (response != NSAlertFirstButtonReturn) return;
    if (selected.count == 0U) {
        SVAlert(self.window, @"No samples selected", @"Select at least one sample.", NSAlertStyleWarning);
        return;
    }

    NSString* error = nil;
    NSUInteger createdIndex = NSNotFound;
    if (![_documentModel createMultisampleNamed:name sampleIndexes:selected error:&error createdIndex:&createdIndex]) {
        SVAlert(self.window, @"Create Multisample failed", error, NSAlertStyleCritical);
        return;
    }
    _preferredMultisampleIndex = createdIndex;
    [self refreshFromDocument];
}

@end
