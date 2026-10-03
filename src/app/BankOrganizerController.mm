#import <AppKit/AppKit.h>

@interface SVManagerDocument : NSObject
- (NSUInteger)soundCount;
- (NSArray<NSString*>*)soundDisplayRows;
- (NSDictionary<NSString*, id>*)soundStateAtIndex:(NSUInteger)index;
- (BOOL)updateSoundAtIndex:(NSUInteger)index
                      name:(NSString*)name
                      bank:(NSUInteger)bank
                      page:(NSUInteger)page
                      slot:(NSUInteger)slot
                  category:(NSUInteger)category
                     error:(NSString**)error;
- (NSDictionary<NSString*, NSNumber*>*)nextFreeSoundAddressFromBank:(NSUInteger)bank
                                                               page:(NSUInteger)page
                                                               slot:(NSUInteger)slot
                                                     excludingIndex:(NSUInteger)excludingIndex
                                                              error:(NSString**)error;
- (BOOL)autoPackSoundAddressesFromBank:(NSUInteger)bank
                                   page:(NSUInteger)page
                                   slot:(NSUInteger)slot
                                  error:(NSString**)error;
@end

@interface SVBankOrganizerWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

namespace {

NSTextField* SVBOLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
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

NSTextField* SVBOField(NSRect frame, NSString* value) {
    NSTextField* field = [[NSTextField alloc] initWithFrame:frame];
    field.stringValue = value ?: @"";
    field.bezeled = YES;
    field.editable = YES;
    field.selectable = YES;
    field.drawsBackground = YES;
    field.backgroundColor = [NSColor colorWithCalibratedRed:0.085 green:0.098 blue:0.112 alpha:1.0];
    field.textColor = [NSColor colorWithCalibratedWhite:0.92 alpha:1.0];
    field.font = [NSFont monospacedDigitSystemFontOfSize:12.0 weight:NSFontWeightRegular];
    return field;
}

NSButton* SVBOButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void SVBOMessage(NSWindow* window, NSString* title, NSString* message, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Bank Organizer";
    alert.informativeText = message ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

BOOL SVBOReadRange(NSTextField* field, NSString* label, NSUInteger* valueOut, NSWindow* window) {
    NSString* trimmed = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0U || [trimmed hasPrefix:@"-"]) {
        SVBOMessage(window, @"Invalid address", [NSString stringWithFormat:@"%@ must be between 0 and 127.", label], NSAlertStyleWarning);
        return NO;
    }
    NSScanner* scanner = [NSScanner scannerWithString:trimmed];
    unsigned long long parsed = 0ULL;
    if (![scanner scanUnsignedLongLong:&parsed] || !scanner.isAtEnd || parsed > 127ULL) {
        SVBOMessage(window, @"Invalid address", [NSString stringWithFormat:@"%@ must be between 0 and 127.", label], NSAlertStyleWarning);
        return NO;
    }
    if (valueOut != nullptr) *valueOut = static_cast<NSUInteger>(parsed);
    return YES;
}

} // namespace

@implementation SVBankOrganizerWindowController {
    SVManagerDocument* _documentModel;
    NSArray<NSString*>* _rows;
    NSTableView* _table;
    NSTextField* _nameField;
    NSTextField* _bankField;
    NSTextField* _pageField;
    NSTextField* _slotField;
    NSTextField* _categoryField;
    NSTextField* _sourceLabel;
    NSTextField* _statusLabel;
}

- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel {
    const NSRect rect = NSMakeRect(0.0, 0.0, 920.0, 610.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:rect
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Bank Organizer";
    window.minSize = NSMakeSize(820.0, 540.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        _documentModel = documentModel;
        _rows = @[];
        [self buildInterface];
        [self refreshFromDocument];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    content.autoresizesSubviews = YES;
    NSColor* mainText = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    NSColor* dimText = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];

    NSTextField* title = SVBOLabel(NSMakeRect(24.0, 558.0, 430.0, 30.0), @"BANK / LIBRARY ORGANIZER", 20.0, NSFontWeightSemibold,
                                   [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0]);
    title.autoresizingMask = NSViewMinYMargin;
    [content addSubview:title];

    NSTextField* subtitle = SVBOLabel(NSMakeRect(26.0, 536.0, 760.0, 20.0),
                                      @"Name and destination only. Nothing is moved or renamed until Apply / Auto Pack is pressed.",
                                      11.0, NSFontWeightRegular, dimText);
    subtitle.autoresizingMask = NSViewMinYMargin;
    [content addSubview:subtitle];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24.0, 74.0, 510.0, 448.0)];
    scroll.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];

    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _table.headerView = nil;
    _table.rowHeight = 30.0;
    _table.backgroundColor = scroll.backgroundColor;
    _table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _table.gridColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0];
    _table.dataSource = self;
    _table.delegate = self;
    _table.allowsMultipleSelection = NO;
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"sound"];
    column.width = 494.0;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    scroll.documentView = _table;
    [content addSubview:scroll];

    const CGFloat x = 560.0;
    [content addSubview:SVBOLabel(NSMakeRect(x, 492.0, 250.0, 22.0), @"Selected library entry", 14.0, NSFontWeightSemibold, mainText)];

    [content addSubview:SVBOLabel(NSMakeRect(x, 450.0, 70.0, 20.0), @"Name", 11.0, NSFontWeightRegular, mainText)];
    _nameField = SVBOField(NSMakeRect(x + 82.0, 446.0, 250.0, 26.0), @"");
    _nameField.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];
    [content addSubview:_nameField];

    [content addSubview:SVBOLabel(NSMakeRect(x, 410.0, 70.0, 20.0), @"Bank", 11.0, NSFontWeightRegular, mainText)];
    _bankField = SVBOField(NSMakeRect(x + 82.0, 406.0, 72.0, 26.0), @"0"); [content addSubview:_bankField];
    [content addSubview:SVBOLabel(NSMakeRect(x + 170.0, 410.0, 48.0, 20.0), @"Page", 11.0, NSFontWeightRegular, mainText)];
    _pageField = SVBOField(NSMakeRect(x + 220.0, 406.0, 60.0, 26.0), @"0"); [content addSubview:_pageField];
    [content addSubview:SVBOLabel(NSMakeRect(x, 370.0, 70.0, 20.0), @"Slot", 11.0, NSFontWeightRegular, mainText)];
    _slotField = SVBOField(NSMakeRect(x + 82.0, 366.0, 72.0, 26.0), @"0"); [content addSubview:_slotField];
    [content addSubview:SVBOLabel(NSMakeRect(x + 170.0, 370.0, 72.0, 20.0), @"Category", 11.0, NSFontWeightRegular, mainText)];
    _categoryField = SVBOField(NSMakeRect(x + 242.0, 366.0, 60.0, 26.0), @"0"); [content addSubview:_categoryField];

    NSButton* nextFree = SVBOButton(NSMakeRect(x, 320.0, 150.0, 30.0), @"Find Next Free", self, @selector(nextFreePressed:));
    [content addSubview:nextFree];
    NSButton* apply = SVBOButton(NSMakeRect(x + 164.0, 320.0, 168.0, 30.0), @"Apply Entry", self, @selector(applyPressed:));
    [content addSubview:apply];

    _sourceLabel = SVBOLabel(NSMakeRect(x, 262.0, 332.0, 44.0), @"", 11.0, NSFontWeightRegular, dimText);
    _sourceLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _sourceLabel.maximumNumberOfLines = 2;
    [content addSubview:_sourceLabel];

    [content addSubview:SVBOLabel(NSMakeRect(x, 214.0, 332.0, 20.0), @"Auto Pack from the address above", 12.0, NSFontWeightSemibold, mainText)];
    [content addSubview:SVBOLabel(NSMakeRect(x, 188.0, 332.0, 32.0),
                                  @"Packs every entry in list order through Slot, then Page, then Bank. This only runs when you press the button.",
                                  10.5, NSFontWeightRegular, dimText)];
    NSButton* autoPack = SVBOButton(NSMakeRect(x, 142.0, 332.0, 32.0), @"Auto Pack All…", self, @selector(autoPackPressed:));
    [content addSubview:autoPack];

    _statusLabel = SVBOLabel(NSMakeRect(24.0, 38.0, 872.0, 22.0), @"", 11.0, NSFontWeightMedium,
                             [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];
}

- (NSUInteger)selectedSoundIndex {
    const NSInteger row = _table.selectedRow;
    return row < 0 ? NSNotFound : static_cast<NSUInteger>(row);
}

- (void)refreshFromDocument {
    const NSInteger previous = _table.selectedRow;
    _rows = [_documentModel soundDisplayRows] ?: @[];
    [_table reloadData];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu library entr%@", (unsigned long)_rows.count, _rows.count == 1U ? @"y" : @"ies"];

    if (_rows.count == 0U) {
        [_table deselectAll:nil];
        _nameField.stringValue = @"";
        _sourceLabel.stringValue = @"Import samples / multisamples first.";
        return;
    }

    NSInteger selection = previous;
    if (selection < 0 || static_cast<NSUInteger>(selection) >= _rows.count) selection = 0;
    [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(selection)] byExtendingSelection:NO];
    [self loadSelection];
}

- (void)loadSelection {
    const NSUInteger index = [self selectedSoundIndex];
    if (index == NSNotFound) return;
    NSDictionary<NSString*, id>* state = [_documentModel soundStateAtIndex:index];
    if (state == nil) return;
    _nameField.stringValue = state[@"name"] ?: @"";
    _bankField.stringValue = [NSString stringWithFormat:@"%u", [state[@"bank"] unsignedIntValue]];
    _pageField.stringValue = [NSString stringWithFormat:@"%u", [state[@"page"] unsignedIntValue]];
    _slotField.stringValue = [NSString stringWithFormat:@"%u", [state[@"slot"] unsignedIntValue]];
    _categoryField.stringValue = [NSString stringWithFormat:@"%u", [state[@"category"] unsignedIntValue]];
    NSString* multisample = state[@"multisampleName"] ?: @"No multisample";
    const unsigned long long zones = [state[@"zoneCount"] unsignedLongLongValue];
    _sourceLabel.stringValue = [NSString stringWithFormat:@"Source: %@\n%llu zone%@ · organizational metadata only",
                                multisample, zones, zones == 1ULL ? @"" : @"s"];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_rows.count);
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _rows.count) return nil;
    NSTextField* cell = SVBOLabel(NSMakeRect(8.0, 4.0, 480.0, 22.0), _rows[static_cast<NSUInteger>(row)], 11.0,
                                  NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
    cell.autoresizingMask = NSViewWidthSizable;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    (void)notification;
    [self loadSelection];
}

- (BOOL)readAddressBank:(NSUInteger*)bank page:(NSUInteger*)page slot:(NSUInteger*)slot category:(NSUInteger*)category {
    return SVBOReadRange(_bankField, @"Bank", bank, self.window) &&
           SVBOReadRange(_pageField, @"Page", page, self.window) &&
           SVBOReadRange(_slotField, @"Slot", slot, self.window) &&
           SVBOReadRange(_categoryField, @"Category", category, self.window);
}

- (void)applyPressed:(id)sender {
    (void)sender;
    const NSUInteger index = [self selectedSoundIndex];
    if (index == NSNotFound) {
        SVBOMessage(self.window, @"No entry selected", @"Select a bank/library entry first.", NSAlertStyleWarning);
        return;
    }
    NSUInteger bank = 0U, page = 0U, slot = 0U, category = 0U;
    if (![self readAddressBank:&bank page:&page slot:&slot category:&category]) return;

    NSString* error = nil;
    if (![_documentModel updateSoundAtIndex:index name:_nameField.stringValue bank:bank page:page slot:slot category:category error:&error]) {
        SVBOMessage(self.window, @"Apply failed", error, NSAlertStyleWarning);
        return;
    }
    [self refreshFromDocument];
}

- (void)nextFreePressed:(id)sender {
    (void)sender;
    NSUInteger bank = 0U, page = 0U, slot = 0U, category = 0U;
    if (![self readAddressBank:&bank page:&page slot:&slot category:&category]) return;
    (void)category;
    const NSUInteger selected = [self selectedSoundIndex];
    NSString* error = nil;
    NSDictionary<NSString*, NSNumber*>* address = [_documentModel nextFreeSoundAddressFromBank:bank
                                                                                         page:page
                                                                                         slot:slot
                                                                               excludingIndex:selected
                                                                                        error:&error];
    if (address == nil) {
        SVBOMessage(self.window, @"No free address", error, NSAlertStyleWarning);
        return;
    }
    _bankField.stringValue = [NSString stringWithFormat:@"%u", [address[@"bank"] unsignedIntValue]];
    _pageField.stringValue = [NSString stringWithFormat:@"%u", [address[@"page"] unsignedIntValue]];
    _slotField.stringValue = [NSString stringWithFormat:@"%u", [address[@"slot"] unsignedIntValue]];
}

- (void)autoPackPressed:(id)sender {
    (void)sender;
    NSUInteger bank = 0U, page = 0U, slot = 0U, category = 0U;
    if (![self readAddressBank:&bank page:&page slot:&slot category:&category]) return;
    (void)category;

    NSAlert* confirmation = [[NSAlert alloc] init];
    confirmation.messageText = @"Auto Pack every library entry?";
    confirmation.informativeText = @"This will explicitly replace all Bank/Page/Slot destinations in current list order. Names, categories, multisamples and sample audio are not changed.";
    [confirmation addButtonWithTitle:@"Auto Pack"];
    [confirmation addButtonWithTitle:@"Cancel"];
    confirmation.alertStyle = NSAlertStyleWarning;
    if ([confirmation runModal] != NSAlertFirstButtonReturn) return;

    NSString* error = nil;
    if (![_documentModel autoPackSoundAddressesFromBank:bank page:page slot:slot error:&error]) {
        SVBOMessage(self.window, @"Auto Pack failed", error, NSAlertStyleWarning);
        return;
    }
    [self refreshFromDocument];
}

@end
