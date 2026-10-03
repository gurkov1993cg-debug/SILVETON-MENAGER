#import <AppKit/AppKit.h>
#import <objc/runtime.h>

@interface SVManagerDocument : NSObject
- (NSArray<NSString*>*)sampleDisplayRows;
- (NSArray<NSString*>*)multisampleDisplayRows;
- (NSArray<NSString*>*)soundDisplayRows;
- (NSDictionary<NSString*, id>*)sampleStateAtIndex:(NSUInteger)index;
- (NSDictionary<NSString*, id>*)multisampleStateAtIndex:(NSUInteger)index;
- (NSDictionary<NSString*, id>*)soundStateAtIndex:(NSUInteger)index;
- (BOOL)renameObjectKind:(NSInteger)kind index:(NSUInteger)index name:(NSString*)name error:(NSString**)error;
- (BOOL)duplicateObjectKind:(NSInteger)kind index:(NSUInteger)index createdIndex:(NSUInteger*)createdIndex error:(NSString**)error;
- (BOOL)deleteObjectKind:(NSInteger)kind index:(NSUInteger)index summary:(NSString**)summary error:(NSString**)error;
- (BOOL)createSoundFromMultisampleIndex:(NSUInteger)multisampleIndex name:(NSString*)name createdIndex:(NSUInteger*)createdIndex error:(NSString**)error;
@end

@interface SVAppDelegate : NSObject
- (void)refreshAllEditors;
@end

@interface SVObjectManagerWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate;
- (void)refreshFromDocument;
@end

@interface SVAppDelegate (ObjectManagerCommands)
- (void)showObjectManagerCommand:(id)sender;
@end

namespace {
static const void* kSVObjectManagerControllerKey = &kSVObjectManagerControllerKey;

NSTextField* Label(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight) {
    NSTextField* label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text ?: @"";
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    return label;
}

NSButton* Button(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void Message(NSWindow* window, NSString* title, NSString* text, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"Object Manager";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

SVManagerDocument* Document(SVAppDelegate* delegate) {
    id main = [delegate valueForKey:@"mainWindowController"];
    return [main valueForKey:@"documentModel"];
}
}

@implementation SVObjectManagerWindowController {
    SVAppDelegate* _delegate;
    SVManagerDocument* _document;
    NSSegmentedControl* _kindControl;
    NSTableView* _table;
    NSArray<NSString*>* _rows;
    NSTextField* _nameField;
    NSPopUpButton* _multisamplePopup;
    NSTextField* _statusLabel;
}

- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate {
    NSWindow* window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0.0, 0.0, 900.0, 600.0)
                                                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered defer:NO];
    window.title = @"SILVETON Object Manager";
    window.minSize = NSMakeSize(760.0, 520.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];
    self = [super initWithWindow:window];
    if (self) {
        _delegate = delegate;
        _document = Document(delegate);
        _rows = @[];
        [self buildInterface];
        [self refreshFromDocument];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    [content addSubview:Label(NSMakeRect(24.0, 548.0, 420.0, 30.0), @"OBJECT MANAGER", 20.0, NSFontWeightSemibold)];
    NSTextField* help = Label(NSMakeRect(24.0, 524.0, 830.0, 20.0), @"Rename and Duplicate are non-destructive. Delete is explicit and may cascade only after confirmation.", 11.0, NSFontWeightRegular);
    help.textColor = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
    [content addSubview:help];

    _kindControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(24.0, 486.0, 390.0, 28.0)];
    _kindControl.segmentCount = 3;
    [_kindControl setLabel:@"Samples" forSegment:0];
    [_kindControl setLabel:@"Multisamples" forSegment:1];
    [_kindControl setLabel:@"SOUNDs" forSegment:2];
    _kindControl.selectedSegment = 0;
    _kindControl.target = self;
    _kindControl.action = @selector(kindChanged:);
    [content addSubview:_kindControl];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24.0, 92.0, 520.0, 380.0)];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _table.headerView = nil;
    _table.rowHeight = 30.0;
    _table.dataSource = self;
    _table.delegate = self;
    _table.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"object"];
    column.width = 500.0;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_table addTableColumn:column];
    scroll.documentView = _table;
    [content addSubview:scroll];

    const CGFloat x = 570.0;
    [content addSubview:Label(NSMakeRect(x, 444.0, 280.0, 20.0), @"Selected object name", 12.0, NSFontWeightSemibold)];
    _nameField = [[NSTextField alloc] initWithFrame:NSMakeRect(x, 410.0, 300.0, 28.0)];
    _nameField.editable = YES;
    _nameField.selectable = YES;
    [content addSubview:_nameField];
    [content addSubview:Button(NSMakeRect(x, 366.0, 92.0, 30.0), @"Rename", self, @selector(renamePressed:))];
    [content addSubview:Button(NSMakeRect(x + 102.0, 366.0, 92.0, 30.0), @"Duplicate", self, @selector(duplicatePressed:))];
    NSButton* deleteButton = Button(NSMakeRect(x + 204.0, 366.0, 96.0, 30.0), @"Delete…", self, @selector(deletePressed:));
    [content addSubview:deleteButton];

    [content addSubview:Label(NSMakeRect(x, 294.0, 300.0, 20.0), @"Create SOUND from multisample", 12.0, NSFontWeightSemibold)];
    _multisamplePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(x, 258.0, 300.0, 28.0) pullsDown:NO];
    [content addSubview:_multisamplePopup];
    [content addSubview:Button(NSMakeRect(x, 218.0, 150.0, 30.0), @"Create SOUND", self, @selector(createSoundPressed:))];

    NSTextField* note = Label(NSMakeRect(x, 150.0, 300.0, 54.0), @"New samples are created by Import. New multisamples are created in Multisample Editor from selected samples.", 10.5, NSFontWeightRegular);
    note.textColor = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];
    note.maximumNumberOfLines = 3;
    note.lineBreakMode = NSLineBreakByWordWrapping;
    [content addSubview:note];

    _statusLabel = Label(NSMakeRect(24.0, 50.0, 840.0, 24.0), @"", 11.0, NSFontWeightMedium);
    _statusLabel.textColor = [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0];
    [content addSubview:_statusLabel];
}

- (NSInteger)kind { return _kindControl.selectedSegment; }

- (void)kindChanged:(id)sender { (void)sender; [self refreshFromDocument]; }

- (void)refreshFromDocument {
    _document = Document(_delegate);
    if (_document == nil) { _rows = @[]; [_table reloadData]; return; }
    const NSInteger kind = [self kind];
    if (kind == 0) _rows = [_document sampleDisplayRows] ?: @[];
    else if (kind == 1) _rows = [_document multisampleDisplayRows] ?: @[];
    else _rows = [_document soundDisplayRows] ?: @[];
    [_table reloadData];

    NSArray<NSString*>* multisamples = [_document multisampleDisplayRows] ?: @[];
    [_multisamplePopup removeAllItems];
    for (NSString* row in multisamples) [_multisamplePopup addItemWithTitle:row];
    _multisamplePopup.enabled = multisamples.count > 0U;

    if (_rows.count > 0U) {
        NSUInteger selection = _table.selectedRow >= 0 ? static_cast<NSUInteger>(_table.selectedRow) : 0U;
        if (selection >= _rows.count) selection = _rows.count - 1U;
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:selection] byExtendingSelection:NO];
        [self loadSelection];
    } else {
        [_table deselectAll:nil];
        _nameField.stringValue = @"";
    }
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu object%@ in this section", (unsigned long)_rows.count, _rows.count == 1U ? @"" : @"s"];
}

- (NSUInteger)selectedIndex {
    return _table.selectedRow < 0 ? NSNotFound : static_cast<NSUInteger>(_table.selectedRow);
}

- (void)loadSelection {
    const NSUInteger index = [self selectedIndex];
    if (index == NSNotFound) return;
    NSDictionary<NSString*, id>* state = nil;
    if ([self kind] == 0) state = [_document sampleStateAtIndex:index];
    else if ([self kind] == 1) state = [_document multisampleStateAtIndex:index];
    else state = [_document soundStateAtIndex:index];
    _nameField.stringValue = state[@"name"] ?: @"";
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView { (void)tableView; return static_cast<NSInteger>(_rows.count); }

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView; (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _rows.count) return nil;
    NSTextField* label = Label(NSMakeRect(8.0, 4.0, 500.0, 22.0), _rows[static_cast<NSUInteger>(row)], 11.0, NSFontWeightRegular);
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    return label;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification { (void)notification; [self loadSelection]; }

- (void)renamePressed:(id)sender {
    (void)sender;
    const NSUInteger index = [self selectedIndex];
    if (index == NSNotFound) { Message(self.window, @"Rename", @"Select an object first.", NSAlertStyleWarning); return; }
    NSString* error = nil;
    if (![_document renameObjectKind:[self kind] index:index name:_nameField.stringValue error:&error]) {
        Message(self.window, @"Rename failed", error, NSAlertStyleWarning); return;
    }
    [_delegate refreshAllEditors];
    [self refreshFromDocument];
}

- (void)duplicatePressed:(id)sender {
    (void)sender;
    const NSUInteger index = [self selectedIndex];
    if (index == NSNotFound) { Message(self.window, @"Duplicate", @"Select an object first.", NSAlertStyleWarning); return; }
    NSString* error = nil;
    NSUInteger created = NSNotFound;
    if (![_document duplicateObjectKind:[self kind] index:index createdIndex:&created error:&error]) {
        Message(self.window, @"Duplicate failed", error, NSAlertStyleWarning); return;
    }
    [_delegate refreshAllEditors];
    [self refreshFromDocument];
    if (created != NSNotFound && created < _rows.count) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:created] byExtendingSelection:NO];
}

- (void)deletePressed:(id)sender {
    (void)sender;
    const NSUInteger index = [self selectedIndex];
    if (index == NSNotFound) { Message(self.window, @"Delete", @"Select an object first.", NSAlertStyleWarning); return; }
    NSString* kindName = [self kind] == 0 ? @"sample" : ([self kind] == 1 ? @"multisample" : @"SOUND");
    NSAlert* confirm = [[NSAlert alloc] init];
    confirm.messageText = [NSString stringWithFormat:@"Delete selected %@?", kindName];
    confirm.informativeText = [self kind] == 2 ? @"This removes only the selected SOUND." : @"Referenced zones/layers that become invalid will also be removed. Empty dependent objects are removed safely. This cannot be undone by sample Undo.";
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];
    confirm.alertStyle = NSAlertStyleWarning;
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSString* error = nil;
    NSString* summary = nil;
    if (![_document deleteObjectKind:[self kind] index:index summary:&summary error:&error]) {
        Message(self.window, @"Delete failed", error, NSAlertStyleCritical); return;
    }
    [_delegate refreshAllEditors];
    [self refreshFromDocument];
    _statusLabel.stringValue = summary ?: @"Object deleted";
}

- (void)createSoundPressed:(id)sender {
    (void)sender;
    const NSInteger selected = _multisamplePopup.indexOfSelectedItem;
    if (selected < 0) { Message(self.window, @"Create SOUND", @"No multisample is available.", NSAlertStyleWarning); return; }
    NSAlert* naming = [[NSAlert alloc] init];
    naming.messageText = @"Create SOUND";
    naming.informativeText = @"Enter a name. A free Bank/Page/Slot address is assigned automatically and can be changed in Bank Organizer.";
    [naming addButtonWithTitle:@"Create"];
    [naming addButtonWithTitle:@"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 320.0, 24.0)];
    field.stringValue = _multisamplePopup.titleOfSelectedItem ?: @"New SOUND";
    naming.accessoryView = field;
    if ([naming runModal] != NSAlertFirstButtonReturn) return;
    NSString* error = nil;
    NSUInteger created = NSNotFound;
    if (![_document createSoundFromMultisampleIndex:static_cast<NSUInteger>(selected) name:field.stringValue createdIndex:&created error:&error]) {
        Message(self.window, @"Create SOUND failed", error, NSAlertStyleWarning); return;
    }
    [_delegate refreshAllEditors];
    _kindControl.selectedSegment = 2;
    [self refreshFromDocument];
    if (created != NSNotFound && created < _rows.count) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:created] byExtendingSelection:NO];
}

@end

@implementation SVAppDelegate (ObjectManagerCommands)
- (void)showObjectManagerCommand:(id)sender {
    (void)sender;
    SVObjectManagerWindowController* controller = objc_getAssociatedObject(self, kSVObjectManagerControllerKey);
    if (controller == nil) {
        controller = [[SVObjectManagerWindowController alloc] initWithAppDelegate:self];
        objc_setAssociatedObject(self, kSVObjectManagerControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        [controller refreshFromDocument];
    }
    [controller showWindow:self];
    [controller.window center];
    [controller.window makeKeyAndOrderFront:self];
}
@end
