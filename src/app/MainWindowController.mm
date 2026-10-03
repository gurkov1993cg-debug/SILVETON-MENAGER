#import <AppKit/AppKit.h>

@interface SVManagerDocument : NSObject
- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (NSArray<NSString*>*)displayRows;
- (NSString*)statusSummary;
- (void)clearProject;
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

NSButton* makeButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    return button;
}

void showMessage(NSWindow* window, NSString* title, NSString* message, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON Manager";
    alert.informativeText = message ?: @"";
    alert.alertStyle = style;
    [alert beginSheetModalForWindow:window completionHandler:nil];
}

} // namespace

@implementation SVMainWindowController {
    SVManagerDocument* _documentModel;
    NSTableView* _soundTable;
    NSTextField* _statusLabel;
    NSTextField* _pathLabel;
    NSArray<NSString*>* _rows;
}

- (instancetype)init {
    const NSRect rect = NSMakeRect(0.0, 0.0, 1040.0, 680.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:rect
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON Manager";
    window.minSize = NSMakeSize(820.0, 520.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        _documentModel = [[SVManagerDocument alloc] init];
        _rows = @[];
        [self buildInterface];
        [self refreshProjectView];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    content.autoresizesSubviews = YES;

    NSTextField* title = makeLabel(NSMakeRect(28.0, 620.0, 460.0, 32.0), @"SILVETON MANAGER", 24.0, NSFontWeightSemibold,
                                   [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0]);
    title.autoresizingMask = NSViewMinYMargin;
    [content addSubview:title];

    NSTextField* subtitle = makeLabel(NSMakeRect(30.0, 596.0, 700.0, 22.0),
                                      @"Prepare Korg / WAV / AIFF libraries and build one SILVETON_BANK.sv",
                                      12.0, NSFontWeightRegular,
                                      [NSColor colorWithCalibratedWhite:0.62 alpha:1.0]);
    subtitle.autoresizingMask = NSViewMinYMargin;
    [content addSubview:subtitle];

    NSButton* importButton = makeButton(NSMakeRect(30.0, 548.0, 150.0, 34.0), @"Import Samples…", self, @selector(importPressed:));
    importButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:importButton];

    NSButton* clearButton = makeButton(NSMakeRect(190.0, 548.0, 100.0, 34.0), @"Clear", self, @selector(clearPressed:));
    clearButton.autoresizingMask = NSViewMinYMargin;
    [content addSubview:clearButton];

    NSButton* buildButton = makeButton(NSMakeRect(820.0, 548.0, 188.0, 34.0), @"Build SILVETON_BANK.sv…", self, @selector(buildPressed:));
    buildButton.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [content addSubview:buildButton];

    NSTextField* section = makeLabel(NSMakeRect(30.0, 508.0, 300.0, 24.0), @"Prepared SOUNDs", 14.0, NSFontWeightSemibold,
                                     [NSColor colorWithCalibratedWhite:0.86 alpha:1.0]);
    section.autoresizingMask = NSViewMinYMargin;
    [content addSubview:section];

    NSScrollView* scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(30.0, 100.0, 978.0, 400.0)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = NO;
    scroll.borderType = NSBezelBorder;
    scroll.drawsBackground = YES;
    scroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];

    _soundTable = [[NSTableView alloc] initWithFrame:scroll.bounds];
    _soundTable.headerView = nil;
    _soundTable.rowHeight = 30.0;
    _soundTable.backgroundColor = scroll.backgroundColor;
    _soundTable.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
    _soundTable.gridColor = [NSColor colorWithCalibratedWhite:0.16 alpha:1.0];
    _soundTable.dataSource = self;
    _soundTable.delegate = self;

    NSTableColumn* column = [[NSTableColumn alloc] initWithIdentifier:@"sound"];
    column.width = 950.0;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_soundTable addTableColumn:column];
    scroll.documentView = _soundTable;
    [content addSubview:scroll];

    _statusLabel = makeLabel(NSMakeRect(30.0, 64.0, 978.0, 22.0), @"", 12.0, NSFontWeightMedium,
                             [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];

    _pathLabel = makeLabel(NSMakeRect(30.0, 34.0, 978.0, 20.0), @"Bank not built yet", 11.0, NSFontWeightRegular,
                           [NSColor colorWithCalibratedWhite:0.52 alpha:1.0]);
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_pathLabel];
}

- (void)refreshProjectView {
    _rows = [_documentModel displayRows];
    [_soundTable reloadData];
    _statusLabel.stringValue = [_documentModel statusSummary];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    (void)tableView;
    return static_cast<NSInteger>(_rows.count);
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableView;
    (void)tableColumn;
    if (row < 0 || static_cast<NSUInteger>(row) >= _rows.count) return nil;

    NSTextField* cell = makeLabel(NSMakeRect(10.0, 4.0, 920.0, 22.0), _rows[static_cast<NSUInteger>(row)], 12.0,
                                  NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
    cell.autoresizingMask = NSViewWidthSizable;
    return cell;
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
    if (_rows.count == 0U) return;
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Clear the current Manager project?";
    alert.informativeText = @"Imported data in memory will be cleared. Existing source files and already built .sv banks are not deleted.";
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
    if (_rows.count == 0U) {
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

@end
