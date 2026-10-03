#import <AppKit/AppKit.h>
#import <objc/runtime.h>

#include "silveton/manager/MediaPathPolicy.h"

#include <string>

using silveton::manager::MediaEntryKind;
using silveton::manager::MediaPathPolicy;

@interface SVManagerDocument : NSObject
- (BOOL)importPaths:(NSArray<NSString*>*)paths error:(NSString**)error;
- (BOOL)loadBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
- (BOOL)buildBankAtPath:(NSString*)path error:(NSString**)error summary:(NSString**)summary;
@end

@interface SVMainWindowController : NSWindowController
@end

@interface SVAppDelegate : NSObject
- (void)refreshAllEditors;
@end

@interface SVMediaWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate;
- (void)refreshSources;
@end

@interface SVAppDelegate (MediaCommands)
- (void)showMediaCommand:(id)sender;
@end

namespace {

static const void* kSVMediaControllerKey = &kSVMediaControllerKey;

NSTextField* SVMediaLabel(NSRect frame, NSString* text, CGFloat size, NSFontWeight weight, NSColor* color) {
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

NSButton* SVMediaButton(NSRect frame, NSString* title, id target, SEL action) {
    NSButton* button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.target = target;
    button.action = action;
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
    return button;
}

SVMainWindowController* SVMediaMainController(SVAppDelegate* delegate) {
    id controller = [delegate valueForKey:@"mainWindowController"];
    return [controller isKindOfClass:[NSWindowController class]] ? controller : nil;
}

SVManagerDocument* SVMediaDocument(SVAppDelegate* delegate) {
    id document = [SVMediaMainController(delegate) valueForKey:@"documentModel"];
    return document;
}

void SVMediaStopAudition(SVAppDelegate* delegate) {
    id player = [delegate valueForKey:@"auditionPlayer"];
    if (player != nil && [player respondsToSelector:@selector(stop)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [player performSelector:@selector(stop)];
#pragma clang diagnostic pop
    }
}

void SVMediaMessage(NSWindow* window, NSString* title, NSString* text, NSAlertStyle style) {
    NSAlert* alert = [[NSAlert alloc] init];
    alert.messageText = title ?: @"MEDIA";
    alert.informativeText = text ?: @"";
    alert.alertStyle = style;
    if (window != nil) [alert beginSheetModalForWindow:window completionHandler:nil];
    else [alert runModal];
}

NSString* SVMediaHumanBytes(unsigned long long bytes) {
    const double gib = static_cast<double>(bytes) / (1024.0 * 1024.0 * 1024.0);
    if (gib >= 1.0) return [NSString stringWithFormat:@"%.1f GB", gib];
    const double mib = static_cast<double>(bytes) / (1024.0 * 1024.0);
    return [NSString stringWithFormat:@"%.1f MB", mib];
}

BOOL SVMediaPathInside(NSURL* rootURL, NSURL* candidateURL) {
    if (rootURL.path == nil || candidateURL.path == nil) return NO;
    return MediaPathPolicy::isInsideRoot(std::string(rootURL.path.fileSystemRepresentation),
                                         std::string(candidateURL.path.fileSystemRepresentation)) ? YES : NO;
}

NSString* SVMediaTypeLabel(MediaEntryKind kind) {
    switch (kind) {
        case MediaEntryKind::Directory: return @"Folder";
        case MediaEntryKind::SilvetonBank: return @"SILVETON Bank";
        case MediaEntryKind::ImportableSamplerFile: return @"Sampler File";
        case MediaEntryKind::Unsupported: break;
    }
    return @"Unsupported";
}

} // namespace

@implementation SVMediaWindowController {
    SVAppDelegate* _delegate;
    NSArray<NSDictionary<NSString*, id>*>* _sources;
    NSArray<NSDictionary<NSString*, id>*>* _entries;
    NSTableView* _sourceTable;
    NSTableView* _fileTable;
    NSTextField* _pathLabel;
    NSTextField* _sourceInfoLabel;
    NSTextField* _statusLabel;
    NSURL* _rootURL;
    NSURL* _currentURL;
    BOOL _currentReadOnly;
}

- (instancetype)initWithAppDelegate:(SVAppDelegate*)delegate {
    const NSRect rect = NSMakeRect(0.0, 0.0, 1040.0, 650.0);
    NSWindow* window = [[NSWindow alloc] initWithContentRect:rect
                                                  styleMask:(NSWindowStyleMaskTitled |
                                                             NSWindowStyleMaskClosable |
                                                             NSWindowStyleMaskMiniaturizable |
                                                             NSWindowStyleMaskResizable)
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    window.title = @"SILVETON MEDIA";
    window.minSize = NSMakeSize(860.0, 540.0);
    window.backgroundColor = [NSColor colorWithCalibratedRed:0.055 green:0.067 blue:0.078 alpha:1.0];
    self = [super initWithWindow:window];
    if (self) {
        _delegate = delegate;
        _sources = @[];
        _entries = @[];
        _currentReadOnly = NO;
        [self buildInterface];
        [self refreshSources];
    }
    return self;
}

- (void)buildInterface {
    NSView* content = self.window.contentView;
    NSColor* mainText = [NSColor colorWithCalibratedWhite:0.88 alpha:1.0];
    NSColor* dimText = [NSColor colorWithCalibratedWhite:0.62 alpha:1.0];

    [content addSubview:SVMediaLabel(NSMakeRect(24.0, 600.0, 360.0, 30.0), @"MEDIA", 22.0, NSFontWeightSemibold,
                                      [NSColor colorWithCalibratedRed:0.72 green:0.84 blue:0.96 alpha:1.0])];
    [content addSubview:SVMediaLabel(NSMakeRect(24.0, 578.0, 800.0, 20.0),
                                      @"Choose the physical source first, then explicitly Load, Import or Save. Nothing runs automatically.",
                                      11.0, NSFontWeightRegular, dimText)];

    [content addSubview:SVMediaLabel(NSMakeRect(24.0, 544.0, 180.0, 20.0), @"Storage source", 13.0, NSFontWeightSemibold, mainText)];
    NSButton* refreshButton = SVMediaButton(NSMakeRect(174.0, 538.0, 120.0, 28.0), @"Refresh Sources", self, @selector(refreshSourcesPressed:));
    [content addSubview:refreshButton];

    NSScrollView* sourceScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(24.0, 122.0, 270.0, 408.0)];
    sourceScroll.autoresizingMask = NSViewHeightSizable;
    sourceScroll.hasVerticalScroller = YES;
    sourceScroll.borderType = NSBezelBorder;
    sourceScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    sourceScroll.drawsBackground = YES;
    _sourceTable = [[NSTableView alloc] initWithFrame:sourceScroll.bounds];
    _sourceTable.headerView = nil;
    _sourceTable.rowHeight = 42.0;
    _sourceTable.backgroundColor = sourceScroll.backgroundColor;
    _sourceTable.dataSource = self;
    _sourceTable.delegate = self;
    NSTableColumn* sourceColumn = [[NSTableColumn alloc] initWithIdentifier:@"source"];
    sourceColumn.width = 252.0;
    sourceColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_sourceTable addTableColumn:sourceColumn];
    sourceScroll.documentView = _sourceTable;
    [content addSubview:sourceScroll];

    _sourceInfoLabel = SVMediaLabel(NSMakeRect(24.0, 78.0, 270.0, 38.0), @"", 10.5, NSFontWeightRegular, dimText);
    _sourceInfoLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _sourceInfoLabel.maximumNumberOfLines = 2;
    [content addSubview:_sourceInfoLabel];

    [content addSubview:SVMediaLabel(NSMakeRect(318.0, 544.0, 100.0, 20.0), @"Contents", 13.0, NSFontWeightSemibold, mainText)];
    NSButton* upButton = SVMediaButton(NSMakeRect(404.0, 538.0, 54.0, 28.0), @"Up", self, @selector(upPressed:));
    [content addSubview:upButton];
    NSButton* openButton = SVMediaButton(NSMakeRect(464.0, 538.0, 92.0, 28.0), @"Open Folder", self, @selector(openFolderPressed:));
    [content addSubview:openButton];

    _pathLabel = SVMediaLabel(NSMakeRect(566.0, 542.0, 450.0, 20.0), @"No source selected", 10.5, NSFontWeightRegular, dimText);
    _pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _pathLabel.autoresizingMask = NSViewWidthSizable;
    [content addSubview:_pathLabel];

    NSScrollView* fileScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(318.0, 122.0, 698.0, 408.0)];
    fileScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    fileScroll.hasVerticalScroller = YES;
    fileScroll.borderType = NSBezelBorder;
    fileScroll.backgroundColor = [NSColor colorWithCalibratedRed:0.075 green:0.086 blue:0.098 alpha:1.0];
    fileScroll.drawsBackground = YES;
    _fileTable = [[NSTableView alloc] initWithFrame:fileScroll.bounds];
    _fileTable.rowHeight = 30.0;
    _fileTable.backgroundColor = fileScroll.backgroundColor;
    _fileTable.dataSource = self;
    _fileTable.delegate = self;
    _fileTable.allowsMultipleSelection = YES;
    _fileTable.doubleAction = @selector(fileDoubleClicked:);
    _fileTable.target = self;
    NSTableColumn* nameColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    nameColumn.title = @"Name";
    nameColumn.width = 420.0;
    nameColumn.resizingMask = NSTableColumnAutoresizingMask;
    [_fileTable addTableColumn:nameColumn];
    NSTableColumn* typeColumn = [[NSTableColumn alloc] initWithIdentifier:@"type"];
    typeColumn.title = @"Type";
    typeColumn.width = 140.0;
    [_fileTable addTableColumn:typeColumn];
    NSTableColumn* sizeColumn = [[NSTableColumn alloc] initWithIdentifier:@"size"];
    sizeColumn.title = @"Size";
    sizeColumn.width = 105.0;
    [_fileTable addTableColumn:sizeColumn];
    fileScroll.documentView = _fileTable;
    [content addSubview:fileScroll];

    NSButton* loadButton = SVMediaButton(NSMakeRect(318.0, 76.0, 128.0, 32.0), @"Load .sv Bank", self, @selector(loadBankPressed:));
    [content addSubview:loadButton];
    NSButton* importButton = SVMediaButton(NSMakeRect(456.0, 76.0, 154.0, 32.0), @"Import Selected", self, @selector(importPressed:));
    [content addSubview:importButton];
    NSButton* saveButton = SVMediaButton(NSMakeRect(620.0, 76.0, 170.0, 32.0), @"Save Bank Here…", self, @selector(saveBankPressed:));
    [content addSubview:saveButton];

    _statusLabel = SVMediaLabel(NSMakeRect(318.0, 42.0, 698.0, 24.0), @"", 11.0, NSFontWeightMedium,
                                [NSColor colorWithCalibratedRed:0.45 green:0.72 blue:0.96 alpha:1.0]);
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [content addSubview:_statusLabel];
}

- (void)refreshSourcesPressed:(id)sender {
    (void)sender;
    [self refreshSources];
}

- (void)refreshSources {
    NSString* previousRoot = _rootURL.path;
    NSArray<NSURLResourceKey>* keys = @[NSURLVolumeNameKey, NSURLVolumeIsRemovableKey, NSURLVolumeIsInternalKey,
                                         NSURLVolumeIsReadOnlyKey, NSURLVolumeAvailableCapacityKey];
    NSArray<NSURL*>* urls = [[NSFileManager defaultManager] mountedVolumeURLsIncludingResourceValuesForKeys:keys
                                                                                                    options:NSVolumeEnumerationSkipHiddenVolumes];
    NSMutableArray<NSDictionary<NSString*, id>*>* sources = [NSMutableArray array];
    for (NSURL* url in urls) {
        NSError* valueError = nil;
        NSDictionary<NSURLResourceKey, id>* values = [url resourceValuesForKeys:keys error:&valueError];
        if (valueError != nil) continue;
        NSString* name = values[NSURLVolumeNameKey];
        NSNumber* removable = values[NSURLVolumeIsRemovableKey];
        NSNumber* internal = values[NSURLVolumeIsInternalKey];
        NSNumber* readOnly = values[NSURLVolumeIsReadOnlyKey];
        NSNumber* capacity = values[NSURLVolumeAvailableCapacityKey];
        const BOOL isExternal = removable.boolValue || !internal.boolValue;
        NSString* kind = isExternal ? @"USB / External" : @"Internal";
        [sources addObject:@{@"url": url,
                             @"name": name ?: url.lastPathComponent ?: @"Storage",
                             @"kind": kind,
                             @"readOnly": @(readOnly.boolValue),
                             @"capacity": capacity ?: @0}];
    }
    [sources sortUsingComparator:^NSComparisonResult(NSDictionary<NSString*, id>* a, NSDictionary<NSString*, id>* b) {
        const BOOL aExternal = [a[@"kind"] isEqual:@"USB / External"];
        const BOOL bExternal = [b[@"kind"] isEqual:@"USB / External"];
        if (aExternal != bExternal) return aExternal ? NSOrderedDescending : NSOrderedAscending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    _sources = [sources copy];
    [_sourceTable reloadData];

    NSInteger selection = -1;
    if (previousRoot.length > 0U) {
        for (NSUInteger i = 0U; i < _sources.count; ++i) {
            NSURL* url = _sources[i][@"url"];
            if ([url.path isEqualToString:previousRoot]) { selection = static_cast<NSInteger>(i); break; }
        }
    }
    if (selection < 0 && _sources.count > 0U) selection = 0;
    if (selection >= 0) {
        [_sourceTable selectRowIndexes:[NSIndexSet indexSetWithIndex:static_cast<NSUInteger>(selection)] byExtendingSelection:NO];
        [self selectSourceAtIndex:static_cast<NSUInteger>(selection)];
    } else {
        _rootURL = nil;
        _currentURL = nil;
        _entries = @[];
        [_fileTable reloadData];
        _pathLabel.stringValue = @"No mounted storage source found";
        _sourceInfoLabel.stringValue = @"";
        _statusLabel.stringValue = @"No media source available";
    }
}

- (void)selectSourceAtIndex:(NSUInteger)index {
    if (index >= _sources.count) return;
    NSDictionary<NSString*, id>* source = _sources[index];
    _rootURL = source[@"url"];
    _currentURL = _rootURL;
    _currentReadOnly = [source[@"readOnly"] boolValue];
    NSNumber* capacity = source[@"capacity"];
    _sourceInfoLabel.stringValue = [NSString stringWithFormat:@"%@ · %@ free%@",
                                    source[@"kind"], SVMediaHumanBytes(capacity.unsignedLongLongValue),
                                    _currentReadOnly ? @" · Read-only" : @""];
    [self refreshEntries];
}

- (void)refreshEntries {
    if (_currentURL == nil || _rootURL == nil || !SVMediaPathInside(_rootURL, _currentURL)) {
        _entries = @[];
        [_fileTable reloadData];
        return;
    }
    NSError* directoryError = nil;
    NSArray<NSURLResourceKey>* keys = @[NSURLIsDirectoryKey, NSURLFileSizeKey];
    NSArray<NSURL*>* urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:_currentURL
                                                          includingPropertiesForKeys:keys
                                                                             options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                               error:&directoryError];
    if (urls == nil) {
        _entries = @[];
        [_fileTable reloadData];
        _statusLabel.stringValue = directoryError.localizedDescription ?: @"Cannot read this folder";
        return;
    }

    NSMutableArray<NSDictionary<NSString*, id>*>* entries = [NSMutableArray array];
    for (NSURL* url in urls) {
        if (!SVMediaPathInside(_rootURL, url)) continue;
        NSError* valueError = nil;
        NSDictionary<NSURLResourceKey, id>* values = [url resourceValuesForKeys:keys error:&valueError];
        if (valueError != nil) continue;
        const BOOL directory = [values[NSURLIsDirectoryKey] boolValue];
        const std::string path(url.path.fileSystemRepresentation ?: "");
        const MediaEntryKind kind = MediaPathPolicy::classify(path, directory == YES);
        if (kind == MediaEntryKind::Unsupported) continue;
        [entries addObject:@{@"url": url,
                             @"name": url.lastPathComponent ?: @"",
                             @"kind": @(static_cast<NSInteger>(kind)),
                             @"size": values[NSURLFileSizeKey] ?: @0}];
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary<NSString*, id>* a, NSDictionary<NSString*, id>* b) {
        const MediaEntryKind kindA = static_cast<MediaEntryKind>([a[@"kind"] integerValue]);
        const MediaEntryKind kindB = static_cast<MediaEntryKind>([b[@"kind"] integerValue]);
        const BOOL dirA = kindA == MediaEntryKind::Directory;
        const BOOL dirB = kindB == MediaEntryKind::Directory;
        if (dirA != dirB) return dirA ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
    }];
    _entries = [entries copy];
    [_fileTable reloadData];
    _pathLabel.stringValue = _currentURL.path ?: @"";
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu visible item%@ · selected source controls every MEDIA operation",
                                (unsigned long)_entries.count, _entries.count == 1U ? @"" : @"s"];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView {
    if (tableView == _sourceTable) return static_cast<NSInteger>(_sources.count);
    if (tableView == _fileTable) return static_cast<NSInteger>(_entries.count);
    return 0;
}

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)tableColumn row:(NSInteger)row {
    if (row < 0) return nil;
    if (tableView == _sourceTable) {
        if (static_cast<NSUInteger>(row) >= _sources.count) return nil;
        NSDictionary<NSString*, id>* source = _sources[static_cast<NSUInteger>(row)];
        NSTextField* label = SVMediaLabel(NSMakeRect(8.0, 4.0, 240.0, 34.0),
                                           [NSString stringWithFormat:@"%@\n%@", source[@"name"], source[@"kind"]],
                                           11.0, NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
        label.lineBreakMode = NSLineBreakByTruncatingTail;
        label.maximumNumberOfLines = 2;
        return label;
    }
    if (tableView == _fileTable) {
        if (static_cast<NSUInteger>(row) >= _entries.count) return nil;
        NSDictionary<NSString*, id>* entry = _entries[static_cast<NSUInteger>(row)];
        NSString* identifier = tableColumn.identifier;
        NSString* text = @"";
        if ([identifier isEqualToString:@"name"]) text = entry[@"name"];
        else if ([identifier isEqualToString:@"type"]) text = SVMediaTypeLabel(static_cast<MediaEntryKind>([entry[@"kind"] integerValue]));
        else if ([identifier isEqualToString:@"size"]) {
            const MediaEntryKind kind = static_cast<MediaEntryKind>([entry[@"kind"] integerValue]);
            text = kind == MediaEntryKind::Directory ? @"—" : SVMediaHumanBytes([entry[@"size"] unsignedLongLongValue]);
        }
        NSTextField* label = SVMediaLabel(NSMakeRect(6.0, 4.0, NSWidth(tableColumn.tableView.bounds), 20.0), text ?: @"",
                                           11.0, NSFontWeightRegular, [NSColor colorWithCalibratedWhite:0.88 alpha:1.0]);
        label.lineBreakMode = NSLineBreakByTruncatingMiddle;
        return label;
    }
    return nil;
}

- (void)tableViewSelectionDidChange:(NSNotification*)notification {
    if (notification.object == _sourceTable) {
        const NSInteger row = _sourceTable.selectedRow;
        if (row >= 0) [self selectSourceAtIndex:static_cast<NSUInteger>(row)];
    }
}

- (NSDictionary<NSString*, id>*)singleSelectedEntry {
    const NSInteger row = _fileTable.selectedRow;
    if (row < 0 || static_cast<NSUInteger>(row) >= _entries.count) return nil;
    return _entries[static_cast<NSUInteger>(row)];
}

- (void)fileDoubleClicked:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* entry = [self singleSelectedEntry];
    if (entry == nil) return;
    const MediaEntryKind kind = static_cast<MediaEntryKind>([entry[@"kind"] integerValue]);
    if (kind == MediaEntryKind::Directory) [self enterDirectoryURL:entry[@"url"]];
    else if (kind == MediaEntryKind::SilvetonBank) [self loadBankPressed:self];
}

- (void)enterDirectoryURL:(NSURL*)url {
    if (url == nil || !SVMediaPathInside(_rootURL, url)) {
        SVMediaMessage(self.window, @"MEDIA navigation blocked", @"The requested folder is outside the selected storage source.", NSAlertStyleWarning);
        return;
    }
    _currentURL = url;
    [self refreshEntries];
}

- (void)openFolderPressed:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* entry = [self singleSelectedEntry];
    if (entry == nil || static_cast<MediaEntryKind>([entry[@"kind"] integerValue]) != MediaEntryKind::Directory) {
        SVMediaMessage(self.window, @"Open Folder", @"Select a folder first.", NSAlertStyleWarning);
        return;
    }
    [self enterDirectoryURL:entry[@"url"]];
}

- (void)upPressed:(id)sender {
    (void)sender;
    if (_currentURL == nil || _rootURL == nil || [_currentURL.path isEqualToString:_rootURL.path]) return;
    NSURL* parent = [_currentURL URLByDeletingLastPathComponent];
    if (!SVMediaPathInside(_rootURL, parent)) parent = _rootURL;
    [self enterDirectoryURL:parent];
}

- (void)loadBankPressed:(id)sender {
    (void)sender;
    NSDictionary<NSString*, id>* entry = [self singleSelectedEntry];
    if (entry == nil || static_cast<MediaEntryKind>([entry[@"kind"] integerValue]) != MediaEntryKind::SilvetonBank) {
        SVMediaMessage(self.window, @"Load Bank", @"Select a .sv bank first.", NSAlertStyleWarning);
        return;
    }
    NSURL* url = entry[@"url"];
    if (!SVMediaPathInside(_rootURL, url)) return;
    SVManagerDocument* document = SVMediaDocument(_delegate);
    if (document == nil) {
        SVMediaMessage(self.window, @"Load Bank", @"The Manager document is unavailable.", NSAlertStyleCritical);
        return;
    }
    NSString* error = nil;
    NSString* summary = nil;
    if (![document loadBankAtPath:url.path error:&error summary:&summary]) {
        SVMediaMessage(self.window, @"Bank load failed", error ?: @"The selected bank could not be loaded.", NSAlertStyleCritical);
        return;
    }
    SVMediaStopAudition(_delegate);
    [_delegate refreshAllEditors];
    _statusLabel.stringValue = summary ?: @"Bank loaded";
}

- (void)importPressed:(id)sender {
    (void)sender;
    NSIndexSet* selected = _fileTable.selectedRowIndexes;
    if (selected.count == 0U) {
        SVMediaMessage(self.window, @"Import", @"Select one or more sampler/audio files first.", NSAlertStyleWarning);
        return;
    }
    NSMutableArray<NSString*>* paths = [NSMutableArray array];
    [selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL* stop) {
        (void)stop;
        if (idx >= self->_entries.count) return;
        NSDictionary<NSString*, id>* entry = self->_entries[idx];
        if (static_cast<MediaEntryKind>([entry[@"kind"] integerValue]) != MediaEntryKind::ImportableSamplerFile) return;
        NSURL* url = entry[@"url"];
        if (SVMediaPathInside(self->_rootURL, url) && url.path != nil) [paths addObject:url.path];
    }];
    if (paths.count == 0U) {
        SVMediaMessage(self.window, @"Import", @"The selection contains no importable KMP/KSC/KSF/WAV/AIFF files.", NSAlertStyleWarning);
        return;
    }
    SVManagerDocument* document = SVMediaDocument(_delegate);
    NSString* details = nil;
    if (document == nil || ![document importPaths:paths error:&details]) {
        SVMediaMessage(self.window, @"Import failed", details ?: @"No sampler material was imported.", NSAlertStyleCritical);
        return;
    }
    [_delegate refreshAllEditors];
    _statusLabel.stringValue = [NSString stringWithFormat:@"Imported %lu selected file%@", (unsigned long)paths.count, paths.count == 1U ? @"" : @"s"];
    if (details.length > 0U) SVMediaMessage(self.window, @"Imported with warnings", details, NSAlertStyleWarning);
}

- (void)saveBankPressed:(id)sender {
    (void)sender;
    if (_currentURL == nil || _rootURL == nil) {
        SVMediaMessage(self.window, @"Save Bank", @"Choose a storage source first.", NSAlertStyleWarning);
        return;
    }
    if (_currentReadOnly) {
        SVMediaMessage(self.window, @"Save Bank", @"The selected storage source is read-only.", NSAlertStyleWarning);
        return;
    }

    NSAlert* naming = [[NSAlert alloc] init];
    naming.messageText = @"Save SILVETON bank here";
    naming.informativeText = _currentURL.path ?: @"";
    [naming addButtonWithTitle:@"Save"];
    [naming addButtonWithTitle:@"Cancel"];
    NSTextField* field = [[NSTextField alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 24.0)];
    field.stringValue = @"SILVETON_BANK.sv";
    field.selectable = YES;
    field.editable = YES;
    naming.accessoryView = field;
    if ([naming runModal] != NSAlertFirstButtonReturn) return;

    NSString* name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0U || [name containsString:@"/"] || [name containsString:@":"]) {
        SVMediaMessage(self.window, @"Save Bank", @"Enter a valid bank filename without folder separators.", NSAlertStyleWarning);
        return;
    }
    if (![name.pathExtension.lowercaseString isEqualToString:@"sv"]) name = [name stringByAppendingPathExtension:@"sv"];
    NSURL* destination = [_currentURL URLByAppendingPathComponent:name isDirectory:NO];
    if (!SVMediaPathInside(_rootURL, destination)) {
        SVMediaMessage(self.window, @"Save Bank", @"The requested destination is outside the selected storage source.", NSAlertStyleWarning);
        return;
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) {
        NSAlert* overwrite = [[NSAlert alloc] init];
        overwrite.messageText = @"Replace existing bank?";
        overwrite.informativeText = destination.path ?: @"";
        [overwrite addButtonWithTitle:@"Replace"];
        [overwrite addButtonWithTitle:@"Cancel"];
        overwrite.alertStyle = NSAlertStyleWarning;
        if ([overwrite runModal] != NSAlertFirstButtonReturn) return;
    }

    SVManagerDocument* document = SVMediaDocument(_delegate);
    NSString* error = nil;
    NSString* summary = nil;
    if (document == nil || ![document buildBankAtPath:destination.path error:&error summary:&summary]) {
        SVMediaMessage(self.window, @"Bank save failed", error ?: @"The bank could not be saved.", NSAlertStyleCritical);
        return;
    }
    _statusLabel.stringValue = summary ?: @"Bank saved";
    [self refreshEntries];
}

@end

@implementation SVAppDelegate (MediaCommands)

- (void)showMediaCommand:(id)sender {
    (void)sender;
    SVMediaWindowController* controller = objc_getAssociatedObject(self, kSVMediaControllerKey);
    if (controller == nil) {
        controller = [[SVMediaWindowController alloc] initWithAppDelegate:self];
        objc_setAssociatedObject(self, kSVMediaControllerKey, controller, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else {
        [controller refreshSources];
    }
    [controller showWindow:self];
    [controller.window center];
    [controller.window makeKeyAndOrderFront:self];
}

@end
