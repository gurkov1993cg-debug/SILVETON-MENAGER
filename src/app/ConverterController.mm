#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVManagerDocument : NSObject
- (NSArray<NSString*>*)sampleDisplayRows;
- (BOOL)convertSamplesAtIndexes:(NSIndexSet*)indexes
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error;
- (BOOL)exportSamplesAtIndexes:(NSIndexSet*)indexes
                     directory:(NSString*)directory
                  formatChoice:(NSInteger)formatChoice
                     sampleRate:(NSUInteger)sampleRate
                       channels:(NSUInteger)channels
                 encodingChoice:(NSInteger)encodingChoice
                         dither:(BOOL)dither
                        summary:(NSString**)summary
                          error:(NSString**)error;
@end

@interface SVAppDelegate : NSObject
- (void)refreshAllEditors;
@end

@interface SVConverterWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate;
- (void)refreshFromDocument;
@end

@interface SVAppDelegate (ConverterCommands)
- (void)showConverterCommand:(id)sender;
- (void)refreshConverterIfOpen;
@end

namespace {
static const void* kSVConverterControllerKey = &kSVConverterControllerKey;

NSTextField* ConverterLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
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

NSButton* ConverterButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void ConverterMessage(NSWindow* window, NSString* title, NSString* text, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Converter";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

SVManagerDocument* ConverterDocument(SVAppDelegate* delegate) {
    id main = [delegate valueForKey:@"mainWindowController"];
    return [main valueForKey:@"documentModel"];
}

NSUInteger sampleRateForPopup(NSPopUpButton* popup) {
    switch (popup.indexOfSelectedItem) {
        case 1: return 44100U;
        case 2: return 48000U;
        case 3: return 88200U;
        case 4: return 96000U;
        case 5: return 176400U;
        case 6: return 192000U;
        default: return 0U;
    }
}

NSUInteger channelsForPopup(NSPopUpButton* popup) {
    switch (popup.indexOfSelectedItem) {
        case 1: return 1U;
        case 2: return 2U;
        default: return 0U;
    }
}

} // namespace

@implementation SVConverterWindowController {
    SVAppDelegate* _delegate;
    SVManagerDocument* _document;
    NSArray<NSString*>* _rows;
    NSTableView* _table;
    NSPopUpButton* _ratePopup;
    NSPopUpButton* _channelsPopup;
    NSPopUpButton* _encodingPopup;
    NSPopUpButton* _formatPopup;
    NSButton* _ditherCheck;
    NSTextField* _statusLabel;
}

- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 980.0, 640.0)
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Sample Converter";
    window.minSize = NSMakeSize(860.0, 560.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];
    self = [super initWithWindow:window];
    if (self) {
        _delegate = delegate;
        _document = ConverterDocument(delegate);
        _rows = @[];
        [self buildInterface];
        [self refreshFromDocument];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    NSColor* mainText = [NSColor colorWithCalibratedWhite:0.90 alpha:1.0];
    NSColor* dimText = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
    NSColor* accent = [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0];

    [content addSubview:ConverterLabel(NSMakeRect(24.0, 590.0, 460.0, 30.0), @"SAMPLE CONVERTER", 21.0, NSFontWeightSemibold, accent)];
    NSTextField* help = ConverterLabel(NSMakeRect(24.0, 566.0, 900.0, 20.0),
                                       @"Select samples, choose conversion settings, then explicitly Apply or Export. Nothing changes automatically.",
                                       11.0, NSFontWeightRegular, dimText);
    [content addSubview:help];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24.0, 94.0, 550.0, 452.0)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    scroll.drawsBackground = YES;
    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _table.headerView = nil;
    _table.rowHeight = 30.0;
    _table.allowsMultipleSelection = YES;
    _table.dataSource = self;
    _table.delegate = self;
    _table.backgroundColor = scroll.backgroundColor;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"sample"];
    column.width = 530.0;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    scroll.documentView = _table;
    [content addSubview:scroll];

    const CGFloat x = 602.0;
    [content addSubview:ConverterLabel(NSMakeRect(x, 512.0, 320.0, 22.0), @"Conversion settings", 14.0, NSFontWeightSemibold, mainText)];

    [content addSubview:ConverterLabel(NSMakeRect(x, 470.0, 110.0, 20.0), @"Sample rate", 11.0, NSFontWeightRegular, mainText)];
    _ratePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 118.0, 464.0, 210.0, 28.0) pullsDown:NO];
    [_ratePopup addItemsWithTitles:@[@"Keep original", @"44.1 kHz", @"48 kHz", @"88.2 kHz", @"96 kHz", @"176.4 kHz", @"192 kHz"]];
    [content addSubview:_ratePopup];

    [content addSubview:ConverterLabel(NSMakeRect(x, 428.0, 110.0, 20.0), @"Channels", 11.0, NSFontWeightRegular, mainText)];
    _channelsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 118.0, 422.0, 210.0, 28.0) pullsDown:NO];
    [_channelsPopup addItemsWithTitles:@[@"Keep original", @"Mono", @"Stereo"]];
    [content addSubview:_channelsPopup];

    [content addSubview:ConverterLabel(NSMakeRect(x, 386.0, 110.0, 20.0), @"Bit depth", 11.0, NSFontWeightRegular, mainText)];
    _encodingPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 118.0, 380.0, 210.0, 28.0) pullsDown:NO];
    [_encodingPopup addItemsWithTitles:@[@"Keep original", @"16-bit PCM", @"24-bit PCM", @"32-bit Float"]];
    [content addSubview:_encodingPopup];

    _ditherCheck = [[NSButton alloc] initWithFrame:NSMakeRect(x, 338.0, 328.0, 24.0)];
    _ditherCheck.buttonType = NSButtonTypeSwitch;
    _ditherCheck.title = @"TPDF dither when writing integer PCM";
    _ditherCheck.state = NSControlStateValueOn;
    _ditherCheck.font = [NSFont systemFontOfSize:11.0];
    [content addSubview:_ditherCheck];

    NSButton* apply = ConverterButton(NSMakeRect(x, 284.0, 328.0, 34.0), @"Apply Conversion to Selected…", self, @selector(applyPressed:));
    [content addSubview:apply];

    [content addSubview:ConverterLabel(NSMakeRect(x, 226.0, 320.0, 22.0), @"Non-destructive export", 13.0, NSFontWeightSemibold, mainText)];
    [content addSubview:ConverterLabel(NSMakeRect(x, 190.0, 90.0, 20.0), @"Format", 11.0, NSFontWeightRegular, mainText)];
    _formatPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x + 118.0, 184.0, 210.0, 28.0) pullsDown:NO];
    [_formatPopup addItemsWithTitles:@[@"WAV", @"AIFF / AIFC"]];
    [content addSubview:_formatPopup];
    NSButton* exportButton = ConverterButton(NSMakeRect(x, 136.0, 328.0, 34.0), @"Export Selected to Folder…", self, @selector(exportPressed:));
    [content addSubview:exportButton];

    NSTextField* note = ConverterLabel(NSMakeRect(x, 82.0, 328.0, 42.0),
                                       @"Apply changes the samples stored in the project. Export converts copies only; the project audio is untouched.",
                                       10.5, NSFontWeightRegular, dimText);
    note.lineBreakMode = NSLineBreakByWordWrapping;
    note.maximumNumberOfLines = 2;
    [content addSubview:note];

    _statusLabel = ConverterLabel(NSMakeRect(24.0, 48.0, 930.0, 26.0), @"", 11.0, NSFontWeightMedium, accent);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];
}

- (void)refreshFromDocument {
    _document = ConverterDocument(_delegate);
    NSIndexSet* previous = [_table.selectedRowIndexes copy];
    _rows = [_document sampleDisplayRows] ?: @[];
    [_table reloadData];
    if (previous.count > 0U) {
        NSMutableIndexSet* valid = [NSMutableIndexSet indexSet];
        [previous enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
            (void)stop;
            if (idx < self->_rows.count) [valid addIndex:idx];
        }];
        [_table selectRowIndexes:valid byExtendingSelection:NO];
    }
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu sample%@ available · %lu selected",
                                (unsigned long)_rows.count, _rows.count == 1U ? @"" : @"s",
                                (unsigned long)_table.selectedRowIndexes.count];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_rows.count);
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _rows.count) return nil;
    NSTextField* label = ConverterLabel(NSMakeRect(8.0, 4.0, 520.0, 22.0), _rows[static_cast<NSUInteger>(row)], 11.0,
                                         NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification;
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu sample%@ available · %lu selected",
                                (unsigned long)_rows.count, _rows.count == 1U ? @"" : @"s",
                                (unsigned long)_table.selectedRowIndexes.count];
}

- (void)applyPressed:(id)sender {
    (void)sender;
    NSIndexSet* selection = _table.selectedRowIndexes;
    if (selection.count == 0U) {
        ConverterMessage(self.window, @"Converter", @"Select one or more samples first.", NSAlertStyleWarning);
        return;
    }
    NSAlert* confirm = [[NSAlert alloc] init];
    confirm.messageText = @"Apply conversion to selected samples?";
    confirm.informativeText = @"This replaces the selected project audio with the converted result. It runs only after you confirm. Sample Undo/Redo is reset because frame indexes and sample format may change.";
    [confirm addButtonWithTitle:@"Apply"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSString* error = nil;
    NSString* summary = nil;
    if (![_document convertSamplesAtIndexes:selection
                                  sampleRate:sampleRateForPopup(_ratePopup)
                                    channels:channelsForPopup(_channelsPopup)
                              encodingChoice:_encodingPopup.indexOfSelectedItem
                                      dither:_ditherCheck.state == NSControlStateValueOn
                                     summary:&summary
                                       error:&error]) {
        ConverterMessage(self.window, @"Conversion failed", error, NSAlertStyleCritical);
        return;
    }
    [_delegate refreshAllEditors];
    [self refreshFromDocument];
    _statusLabel.stringValue = summary ?: @"Conversion complete";
}

- (void)exportPressed:(id)sender {
    (void)sender;
    NSIndexSet* selection = _table.selectedRowIndexes;
    if (selection.count == 0U) {
        ConverterMessage(self.window, @"Export", @"Select one or more samples first.", NSAlertStyleWarning);
        return;
    }

    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.title = @"Choose Export Folder";
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    if ([panel runModal] != NSModalResponseOK || panel.URL.path.length == 0U) return;

    NSString* error = nil;
    NSString* summary = nil;
    if (![_document exportSamplesAtIndexes:selection
                                  directory:panel.URL.path
                               formatChoice:_formatPopup.indexOfSelectedItem
                                  sampleRate:sampleRateForPopup(_ratePopup)
                                    channels:channelsForPopup(_channelsPopup)
                              encodingChoice:_encodingPopup.indexOfSelectedItem
                                      dither:_ditherCheck.state == NSControlStateValueOn
                                     summary:&summary
                                       error:&error]) {
        ConverterMessage(self.window, @"Export failed", error, NSAlertStyleCritical);
        return;
    }
    _statusLabel.stringValue = summary ?: @"Export complete";
}

@end

@implementation SVAppDelegate (ConverterCommands)

- (void)showConverterCommand:(id)sender {
    (void)sender;
    SVConverterWindowController* controller = objc_getAssociatedObject(self, kSVConverterControllerKey);
    if (controller == nil) {
        controller = [[SVConverterWindowController alloc] initWithAppDelegate:self];
        objc_setAssociatedObject(self, kSVConverterControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [controller refreshFromDocument];
    [controller showWindow:nil];
    [controller.window makeKeyAndOrderFront:nil];
}

- (void)refreshConverterIfOpen {
    SVConverterWindowController* controller = objc_getAssociatedObject(self, kSVConverterControllerKey);
    [controller refreshFromDocument];
}

@end
