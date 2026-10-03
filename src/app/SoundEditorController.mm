#import <AppKit/AppKit.h>

#include <cerrno>
#include <cmath>
#include <cstdlib>

@interface SVManagerDocument : NSObject
- (NSArray<NSString*>*)soundDisplayRows;
- (NSDictionary<NSString*, id>*)soundStateAtIndex:(NSUInteger)index;
- (NSArray<NSDictionary<NSString*, id>*>*)soundLayerStatesAtIndex:(NSUInteger)index;
- (NSArray<NSString*>*)multisampleDisplayRows;
- (BOOL)addSoundLayerAtIndex:(NSUInteger)soundIndex multisampleIndex:(NSUInteger)multisampleIndex error:(NSString**)error;
- (BOOL)removeSoundLayerAtIndex:(NSUInteger)soundIndex layerIndex:(NSUInteger)layerIndex error:(NSString**)error;
- (BOOL)updateSoundLayerAtIndex:(NSUInteger)soundIndex
                     layerIndex:(NSUInteger)layerIndex
               multisampleIndex:(NSUInteger)multisampleIndex
                        enabled:(BOOL)enabled
                         keyLow:(NSUInteger)keyLow
                        keyHigh:(NSUInteger)keyHigh
                    velocityLow:(NSUInteger)velocityLow
                   velocityHigh:(NSUInteger)velocityHigh
             transposeSemitones:(NSInteger)transposeSemitones
                      tuneCents:(float)tuneCents
                        levelDb:(float)levelDb
                            pan:(float)pan
                          error:(NSString**)error;
@end

namespace {

NSTextField* SVSELabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
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

NSTextField* SVSEField(NSRect frame, NSString* text) {
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

NSButton* SVSEButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title ?: @"";
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

void SVSEAlert(NSWindow* window, NSString* title, NSString* message, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"SILVETON SOUND Editor";
    alert.informativeText = message ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

BOOL SVSEParseInteger(NSTextField* field, NSString* label, NSInteger minimum, NSInteger maximum, NSInteger* valueOut, NSWindow* window) {
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0U) {
        SVSEAlert(window, @"Invalid SOUND layer value", [NSString stringWithFormat:@"%@ is required.", label], NSAlertStyleWarning);
        return NO;
    }
    const char* value = text.UTF8String;
    if (value == nullptr) return NO;
    errno = 0;
    char* end = nullptr;
    const long parsed = std::strtol(value, &end, 10);
    if (errno == ERANGE || end == value || end == nullptr || *end != '\0' || parsed < minimum || parsed > maximum) {
        SVSEAlert(window, @"Invalid SOUND layer value",
                  [NSString stringWithFormat:@"%@ must be between %ld and %ld.", label, (long)minimum, (long)maximum], NSAlertStyleWarning);
        return NO;
    }
    if (valueOut != nullptr) *valueOut = static_cast<NSInteger>(parsed);
    return YES;
}

BOOL SVSEParseFloat(NSTextField* field, NSString* label, float minimum, float maximum, float* valueOut, NSWindow* window) {
    NSString* text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0U) {
        SVSEAlert(window, @"Invalid SOUND layer value", [NSString stringWithFormat:@"%@ is required.", label], NSAlertStyleWarning);
        return NO;
    }
    const char* value = text.UTF8String;
    if (value == nullptr) return NO;
    errno = 0;
    char* end = nullptr;
    const float parsed = std::strtof(value, &end);
    if (errno == ERANGE || end == value || end == nullptr || *end != '\0' || !std::isfinite(parsed) || parsed < minimum || parsed > maximum) {
        SVSEAlert(window, @"Invalid SOUND layer value",
                  [NSString stringWithFormat:@"%@ must be between %.2f and %.2f.", label, minimum, maximum], NSAlertStyleWarning);
        return NO;
    }
    if (valueOut != nullptr) *valueOut = parsed;
    return YES;
}

} // namespace

@interface SVSoundEditorWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel;
- (void)refreshFromDocument;
@end

@implementation SVSoundEditorWindowController {
    SVManagerDocument* _documentModel;
    NSArray<NSString*>* _soundRows;
    NSArray<NSDictionary<NSString*, id>*>* _layerStates;
    NSArray<NSString*>* _multisampleRows;

    NSTableView* _soundTable;
    NSTableView* _layerTable;
    NSPopUpButton* _multisamplePopup;
    NSButton* _enabledButton;
    NSTextField* _keyLowField;
    NSTextField* _keyHighField;
    NSTextField* _velocityLowField;
    NSTextField* _velocityHighField;
    NSTextField* _transposeField;
    NSTextField* _tuneField;
    NSTextField* _levelField;
    NSTextField* _panField;
    NSTextField* _soundInfoLabel;
    NSTextField* _statusLabel;
}

- (instancetype)initWithDocumentModel:(SVManagerDocument*)documentModel {
    const NSRect rect = NSMakeRect(0.0, 0.0, 1120.0, 690.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:rect
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON SOUND Editor";
    window.minSize = NSMakeSize(1000.0, 620.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];

    self = [super initWithWindow:window];
    if (self) {
        _documentModel = documentModel;
        _soundRows = @[];
        _layerStates = @[];
        _multisampleRows = @[];
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

    NSTextField* title = SVSELabel(NSMakeRect(24.0, 638.0, 420.0, 30.0), @"SOUND / PROGRAM LAYERS", 20.0, NSFontWeightSemibold,
                                   [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0]);
    title.autoresizingMask = NSViewMinYMargin;
    [content addSubview:title];

    NSTextField* subtitle = SVSELabel(NSMakeRect(26.0, 616.0, 900.0, 20.0),
                                      @"Layer edits are explicit. Bank/Page/Slot naming stays in Bank Organizer; this window edits the real SOUND structure.",
                                      11.0, NSFontWeightRegular, dimText);
    subtitle.autoresizingMask = NSViewMinYMargin;
    [content addSubview:subtitle];

    NSScrollView* soundScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24.0, 72.0, 330.0, 526.0)];
    soundScroll.autoresizingMask = NSViewHeightSizable;
    soundScroll.hasVerticalScroller = YES;
    soundScroll.hasHorizontalScroller = NO;
    soundScroll.borderType = NSBezelBorder;
    soundScroll.drawsBackground = YES;
    soundScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    _soundTable = [[NSTableView alloc] initWithFrame:soundScroll.bounds];
    _soundTable.headerView = nil;
    _soundTable.rowHeight = 30.0;
    _soundTable.backgroundColor = soundScroll.backgroundColor;
    _soundTable.dataSource = self;
    _soundTable.delegate = self;
    _soundTable.allowsMultipleSelection = NO;
    NSTableColumn* soundColumn = [[NSTableColumn alloc] initWithIdentifier:@"sound"];
    soundColumn.width = 314.0;
    soundColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_soundTable addTableColumn:soundColumn];
    soundScroll.documentView = _soundTable;
    [content addSubview:soundScroll];

    _soundInfoLabel = SVSELabel(NSMakeRect(378.0, 574.0, 716.0, 24.0), @"No SOUND selected", 14.0, NSFontWeightSemibold, mainText);
    _soundInfoLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [content addSubview:_soundInfoLabel];

    NSScrollView* layerScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(378.0, 360.0, 716.0, 204.0)];
    layerScroll.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    layerScroll.hasVerticalScroller = YES;
    layerScroll.hasHorizontalScroller = NO;
    layerScroll.borderType = NSBezelBorder;
    layerScroll.drawsBackground = YES;
    layerScroll.backgroundColor = soundScroll.backgroundColor;
    _layerTable = [[NSTableView alloc] initWithFrame:layerScroll.bounds];
    _layerTable.headerView = nil;
    _layerTable.rowHeight = 30.0;
    _layerTable.backgroundColor = layerScroll.backgroundColor;
    _layerTable.dataSource = self;
    _layerTable.delegate = self;
    _layerTable.allowsMultipleSelection = NO;
    NSTableColumn* layerColumn = [[NSTableColumn alloc] initWithIdentifier:@"layer"];
    layerColumn.width = 700.0;
    layerColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_layerTable addTableColumn:layerColumn];
    layerScroll.documentView = _layerTable;
    [content addSubview:layerScroll];

    [content addSubview:SVSELabel(NSMakeRect(378.0, 324.0, 94.0, 20.0), @"Multisample", 11.0, NSFontWeightRegular, mainText)];
    _multisamplePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(474.0, 319.0, 292.0, 28.0) pullsDown:NO];
    _multisamplePopup.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    [content addSubview:_multisamplePopup];

    _enabledButton = [[NSButton alloc] initWithFrame:NSMakeRect(790.0, 319.0, 110.0, 26.0)];
    _enabledButton.buttonType = NSSwitchButton;
    _enabledButton.title = @"Layer Enabled";
    _enabledButton.state = NSControlStateValueOn;
    _enabledButton.font = [NSFont systemFontOfSize:11.5 weight:NSFontWeightRegular];
    [content addSubview:_enabledButton];

    [content addSubview:SVSELabel(NSMakeRect(378.0, 282.0, 58.0, 20.0), @"Key Low", 11.0, NSFontWeightRegular, mainText)];
    _keyLowField = SVSEField(NSMakeRect(438.0, 278.0, 64.0, 26.0), @"0"); [content addSubview:_keyLowField];
    [content addSubview:SVSELabel(NSMakeRect(516.0, 282.0, 62.0, 20.0), @"Key High", 11.0, NSFontWeightRegular, mainText)];
    _keyHighField = SVSEField(NSMakeRect(580.0, 278.0, 64.0, 26.0), @"127"); [content addSubview:_keyHighField];
    [content addSubview:SVSELabel(NSMakeRect(666.0, 282.0, 70.0, 20.0), @"Vel Low", 11.0, NSFontWeightRegular, mainText)];
    _velocityLowField = SVSEField(NSMakeRect(736.0, 278.0, 64.0, 26.0), @"1"); [content addSubview:_velocityLowField];
    [content addSubview:SVSELabel(NSMakeRect(814.0, 282.0, 72.0, 20.0), @"Vel High", 11.0, NSFontWeightRegular, mainText)];
    _velocityHighField = SVSEField(NSMakeRect(886.0, 278.0, 64.0, 26.0), @"127"); [content addSubview:_velocityHighField];

    [content addSubview:SVSELabel(NSMakeRect(378.0, 240.0, 72.0, 20.0), @"Transpose", 11.0, NSFontWeightRegular, mainText)];
    _transposeField = SVSEField(NSMakeRect(452.0, 236.0, 72.0, 26.0), @"0"); [content addSubview:_transposeField];
    [content addSubview:SVSELabel(NSMakeRect(542.0, 240.0, 76.0, 20.0), @"Tune cents", 11.0, NSFontWeightRegular, mainText)];
    _tuneField = SVSEField(NSMakeRect(620.0, 236.0, 76.0, 26.0), @"0.0"); [content addSubview:_tuneField];
    [content addSubview:SVSELabel(NSMakeRect(716.0, 240.0, 62.0, 20.0), @"Level dB", 11.0, NSFontWeightRegular, mainText)];
    _levelField = SVSEField(NSMakeRect(780.0, 236.0, 76.0, 26.0), @"0.0"); [content addSubview:_levelField];
    [content addSubview:SVSELabel(NSMakeRect(876.0, 240.0, 36.0, 20.0), @"Pan", 11.0, NSFontWeightRegular, mainText)];
    _panField = SVSEField(NSMakeRect(914.0, 236.0, 76.0, 26.0), @"0.0"); [content addSubview:_panField];

    [content addSubview:SVSEButton(NSMakeRect(378.0, 184.0, 136.0, 30.0), @"Add Layer", self, @selector(addLayerPressed:))];
    [content addSubview:SVSEButton(NSMakeRect(524.0, 184.0, 136.0, 30.0), @"Remove Layer", self, @selector(removeLayerPressed:))];
    [content addSubview:SVSEButton(NSMakeRect(844.0, 184.0, 150.0, 30.0), @"Apply Layer", self, @selector(applyLayerPressed:))];

    NSTextField* note = SVSELabel(NSMakeRect(378.0, 132.0, 700.0, 38.0),
                                  @"Key 0–127 · Velocity 1–127 · Transpose -127…+127 · Tune -100…+100 cents · Level -120…+24 dB · Pan -1…+1. Add/Remove/Apply only change the project when pressed.",
                                  10.5, NSFontWeightRegular, dimText);
    note.lineBreakMode = NSLineBreakByWordWrapping;
    note.maximumNumberOfLines = 2;
    [content addSubview:note];

    _statusLabel = SVSELabel(NSMakeRect(24.0, 36.0, 1070.0, 22.0), @"", 11.0, NSFontWeightMedium,
                             [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];
}

- (NSUInteger)selectedSoundIndex {
    const NSInteger row = _soundTable.selectedRow;
    return row < 0 ? NSNotFound : static_cast<NSUInteger>(row);
}

- (NSUInteger)selectedLayerIndex {
    const NSInteger row = _layerTable.selectedRow;
    return row < 0 ? NSNotFound : static_cast<NSUInteger>(row);
}

- (void)reloadMultisamplePopup {
    _multisampleRows = [_documentModel multisampleDisplayRows] ?: @[];
    [_multisamplePopup removeAllItems];
    for (NSUInteger i = 0U; i < _multisampleRows.count; ++i) {
        [_multisamplePopup addItemWithTitle:_multisampleRows[i]];
        _multisamplePopup.lastItem.tag = static_cast<NSInteger>(i);
    }
}

- (void)refreshFromDocument {
    const NSInteger previousSound = _soundTable.selectedRow;
    [self reloadMultisamplePopup];
    _soundRows = [_documentModel soundDisplayRows] ?: @[];
    [_soundTable reloadData];

    if (_soundRows.count == 0U) {
        [_soundTable deselectAll:nil];
        _layerStates = @[];
        [_layerTable reloadData];
        _soundInfoLabel.stringValue = @"No SOUND selected";
        _statusLabel.stringValue = @"Import samples / multisamples first.";
        return;
    }

    NSInteger selection = previousSound;
    if (selection < 0 || static_cast<NSUInteger>(selection) >= _soundRows.count) selection = 0;
    [_soundTable selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(selection)] byExtendingSelection:NO];
    [self refreshSelectedSoundPreservingLayer:YES];
}

- (void)refreshSelectedSoundPreservingLayer:(BOOL)preserveLayer {
    const NSUInteger soundIndex = [self selectedSoundIndex];
    if (soundIndex == NSNotFound) return;
    const NSInteger previousLayer = preserveLayer ? _layerTable.selectedRow : -1;
    NSDictionary<NSString*, id>* state = [_documentModel soundStateAtIndex:soundIndex];
    _layerStates = [_documentModel soundLayerStatesAtIndex:soundIndex] ?: @[];
    [_layerTable reloadData];

    NSString* name = state[@"name"] ?: @"SOUND";
    const unsigned int bank = [state[@"bank"] unsignedIntValue];
    const unsigned int page = [state[@"page"] unsignedIntValue];
    const unsigned int slot = [state[@"slot"] unsignedIntValue];
    const unsigned int category = [state[@"category"] unsignedIntValue];
    _soundInfoLabel.stringValue = [NSString stringWithFormat:@"%@   ·   Bank %u / Page %u / Slot %u   ·   Category %u", name, bank, page, slot, category];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu SOUND%@ · %lu layer%@ in selected SOUND · %lu multisample%@ available",
                                (unsigned long)_soundRows.count, _soundRows.count == 1U ? @"" : @"s",
                                (unsigned long)_layerStates.count, _layerStates.count == 1U ? @"" : @"s",
                                (unsigned long)_multisampleRows.count, _multisampleRows.count == 1U ? @"" : @"s"];

    if (_layerStates.count == 0U) {
        [_layerTable deselectAll:nil];
        return;
    }
    NSInteger layerSelection = previousLayer;
    if (layerSelection < 0 || static_cast<NSUInteger>(layerSelection) >= _layerStates.count) layerSelection = 0;
    [_layerTable selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(layerSelection)] byExtendingSelection:NO];
    [self loadSelectedLayer];
}

- (void)loadSelectedLayer {
    const NSUInteger layerIndex = [self selectedLayerIndex];
    if (layerIndex == NSNotFound || layerIndex >= _layerStates.count) return;
    NSDictionary<NSString*, id>* state = _layerStates[layerIndex];
    const NSInteger multisampleIndex = [state[@"multisampleIndex"] integerValue];
    if (multisampleIndex >= 0 && static_cast<NSUInteger>(multisampleIndex) < _multisampleRows.count) {
        [_multisamplePopup selectItemAtIndex:multisampleIndex];
    }
    _enabledButton.state = [state[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    _keyLowField.stringValue = [NSString stringWithFormat:@"%u", [state[@"keyLow"] unsignedIntValue]];
    _keyHighField.stringValue = [NSString stringWithFormat:@"%u", [state[@"keyHigh"] unsignedIntValue]];
    _velocityLowField.stringValue = [NSString stringWithFormat:@"%u", [state[@"velocityLow"] unsignedIntValue]];
    _velocityHighField.stringValue = [NSString stringWithFormat:@"%u", [state[@"velocityHigh"] unsignedIntValue]];
    _transposeField.stringValue = [NSString stringWithFormat:@"%ld", (long)[state[@"transposeSemitones"] integerValue]];
    _tuneField.stringValue = [NSString stringWithFormat:@"%.2f", [state[@"tuneCents"] floatValue]];
    _levelField.stringValue = [NSString stringWithFormat:@"%.2f", [state[@"levelDb"] floatValue]];
    _panField.stringValue = [NSString stringWithFormat:@"%.3f", [state[@"pan"] floatValue]];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _soundTable) return static_cast<NSInteger>(_soundRows.count);
    if (tableView == _layerTable) return static_cast<NSInteger>(_layerStates.count);
    return 0;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    (void)tableColumn;
    if (row < 0) return nil;
    if (tableView == _soundTable) {
        if (static_cast<NSUInteger>(row) >= _soundRows.count) return nil;
        NSTextField* cell = SVSELabel(NSMakeRect(8.0, 4.0, 300.0, 22.0), _soundRows[static_cast<NSUInteger>(row)], 10.5,
                                      NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
        cell.autoresizingMask = NSViewWidthSizable;
        return cell;
    }
    if (tableView == _layerTable) {
        if (static_cast<NSUInteger>(row) >= _layerStates.count) return nil;
        NSDictionary<NSString*, id>* state = _layerStates[static_cast<NSUInteger>(row)];
        NSString* on = [state[@"enabled"] boolValue] ? @"ON" : @"OFF";
        NSString* text = [NSString stringWithFormat:@"L%02ld  [%@]  %@  · K %u–%u · V %u–%u · T %ld · %.1f ct · %.1f dB · P %.2f",
                          (long)row + 1L, on, state[@"multisampleName"] ?: @"Multisample",
                          [state[@"keyLow"] unsignedIntValue], [state[@"keyHigh"] unsignedIntValue],
                          [state[@"velocityLow"] unsignedIntValue], [state[@"velocityHigh"] unsignedIntValue],
                          (long)[state[@"transposeSemitones"] integerValue], [state[@"tuneCents"] floatValue],
                          [state[@"levelDb"] floatValue], [state[@"pan"] floatValue]];
        NSTextField* cell = SVSELabel(NSMakeRect(8.0, 4.0, 680.0, 22.0), text, 10.5, NSFontWeightRegular,
                                      [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
        cell.autoresizingMask = NSViewWidthSizable;
        return cell;
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _soundTable) [self refreshSelectedSoundPreservingLayer:NO];
    else if (notification.object == _layerTable) [self loadSelectedLayer];
}

- (void)addLayerPressed:(id)sender {
    (void)sender;
    const NSUInteger soundIndex = [self selectedSoundIndex];
    if (soundIndex == NSNotFound) {
        SVSEAlert(self.window, @"Add Layer", @"Select a SOUND first.", NSAlertStyleWarning);
        return;
    }
    const NSInteger multisampleIndex = _multisamplePopup.indexOfSelectedItem;
    if (multisampleIndex < 0) {
        SVSEAlert(self.window, @"Add Layer", @"No multisample is available.", NSAlertStyleWarning);
        return;
    }
    NSString* error = nil;
    if (![_documentModel addSoundLayerAtIndex:soundIndex multisampleIndex:static_cast<NSUInteger>(multisampleIndex) error:&error]) {
        SVSEAlert(self.window, @"Add Layer failed", error, NSAlertStyleWarning);
        return;
    }
    [self refreshFromDocument];
    if (_layerStates.count > 0U) {
        [_layerTable selectRowIndexes:[NSIndexSet indexSetWithIndex:_layerStates.count - 1U] byExtendingSelection:NO];
        [self loadSelectedLayer];
    }
}

- (void)removeLayerPressed:(id)sender {
    (void)sender;
    const NSUInteger soundIndex = [self selectedSoundIndex];
    const NSUInteger layerIndex = [self selectedLayerIndex];
    if (soundIndex == NSNotFound || layerIndex == NSNotFound) {
        SVSEAlert(self.window, @"Remove Layer", @"Select a SOUND layer first.", NSAlertStyleWarning);
        return;
    }
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = @"Remove selected SOUND layer?";
    alert.informativeText = @"Only the selected SOUND layer assignment is removed. Samples and multisamples are not deleted.";
    [alert addButtonWithTitle:@"Remove Layer"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString* error = nil;
    if (![_documentModel removeSoundLayerAtIndex:soundIndex layerIndex:layerIndex error:&error]) {
        SVSEAlert(self.window, @"Remove Layer failed", error, NSAlertStyleWarning);
        return;
    }
    [self refreshFromDocument];
}

- (void)applyLayerPressed:(id)sender {
    (void)sender;
    const NSUInteger soundIndex = [self selectedSoundIndex];
    const NSUInteger layerIndex = [self selectedLayerIndex];
    if (soundIndex == NSNotFound || layerIndex == NSNotFound) {
        SVSEAlert(self.window, @"Apply Layer", @"Select a SOUND layer first.", NSAlertStyleWarning);
        return;
    }
    const NSInteger multisampleIndex = _multisamplePopup.indexOfSelectedItem;
    if (multisampleIndex < 0) {
        SVSEAlert(self.window, @"Apply Layer", @"Select a multisample.", NSAlertStyleWarning);
        return;
    }

    NSInteger keyLow = 0, keyHigh = 0, velocityLow = 0, velocityHigh = 0, transpose = 0;
    float tune = 0.0F, level = 0.0F, pan = 0.0F;
    if (!SVSEParseInteger(_keyLowField, @"Key Low", 0, 127, &keyLow, self.window) ||
        !SVSEParseInteger(_keyHighField, @"Key High", 0, 127, &keyHigh, self.window) ||
        !SVSEParseInteger(_velocityLowField, @"Velocity Low", 1, 127, &velocityLow, self.window) ||
        !SVSEParseInteger(_velocityHighField, @"Velocity High", 1, 127, &velocityHigh, self.window) ||
        !SVSEParseInteger(_transposeField, @"Transpose", -127, 127, &transpose, self.window) ||
        !SVSEParseFloat(_tuneField, @"Tune", -100.0F, 100.0F, &tune, self.window) ||
        !SVSEParseFloat(_levelField, @"Level", -120.0F, 24.0F, &level, self.window) ||
        !SVSEParseFloat(_panField, @"Pan", -1.0F, 1.0F, &pan, self.window)) return;

    if (keyLow > keyHigh) {
        SVSEAlert(self.window, @"Apply Layer", @"Key Low cannot exceed Key High.", NSAlertStyleWarning);
        return;
    }
    if (velocityLow > velocityHigh) {
        SVSEAlert(self.window, @"Apply Layer", @"Velocity Low cannot exceed Velocity High.", NSAlertStyleWarning);
        return;
    }

    NSString* error = nil;
    if (![_documentModel updateSoundLayerAtIndex:soundIndex
                                      layerIndex:layerIndex
                                multisampleIndex:static_cast<NSUInteger>(multisampleIndex)
                                         enabled:_enabledButton.state == NSControlStateValueOn
                                          keyLow:static_cast<NSUInteger>(keyLow)
                                         keyHigh:static_cast<NSUInteger>(keyHigh)
                                     velocityLow:static_cast<NSUInteger>(velocityLow)
                                    velocityHigh:static_cast<NSUInteger>(velocityHigh)
                              transposeSemitones:transpose
                                       tuneCents:tune
                                         levelDb:level
                                             pan:pan
                                           error:&error]) {
        SVSEAlert(self.window, @"Apply Layer failed", error, NSAlertStyleWarning);
        return;
    }
    [self refreshSelectedSoundPreservingLayer:YES];
}

@end
