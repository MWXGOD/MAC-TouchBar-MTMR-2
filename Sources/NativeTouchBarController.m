#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <dlfcn.h>

extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

typedef bool (*MRMediaRemoteSendCommandFunction)(NSInteger command, NSDictionary *userInfo);

@interface NSTouchBar (MTMRPrivateMethods)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

@interface NSTouchBarItem (MTMRPrivateMethods)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

static NSTouchBarItemIdentifier const kControlStripIdentifier = @"com.ahs.mtmr2.controlStrip";
static NSTouchBarItemIdentifier const kPreviousIdentifier = @"com.ahs.mtmr2.previous";
static NSTouchBarItemIdentifier const kToggleIdentifier = @"com.ahs.mtmr2.toggle";
static NSTouchBarItemIdentifier const kNextIdentifier = @"com.ahs.mtmr2.next";
static NSTouchBarItemIdentifier const kLyricsIdentifier = @"com.ahs.mtmr2.lyrics";
static NSString *const kScreenSyncPreference = @"MTMRScreenTouchBarSyncEnabled";

@interface MTMRTouchBarButton : NSButton
@property(nonatomic, assign, getter=isPressed) BOOL pressed;
@property(nonatomic, strong) NSImage *iconImage;
@end

@implementation MTMRTouchBarButton

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect backgroundRect = NSInsetRect(self.bounds, 1.0, 1.0);
    CGFloat gray = (self.isPressed || self.isHighlighted) ? 0.38 : 0.20;
    [[NSColor colorWithWhite:gray alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:backgroundRect xRadius:6.0 yRadius:6.0] fill];

    if (!self.iconImage) {
        return;
    }

    NSSize iconSize = NSMakeSize(18.0, 18.0);
    NSRect iconRect = NSMakeRect(floor((NSWidth(self.bounds) - iconSize.width) / 2.0),
                                 floor((NSHeight(self.bounds) - iconSize.height) / 2.0),
                                 iconSize.width,
                                 iconSize.height);
    CGContextRef context = [NSGraphicsContext currentContext].CGContext;
    CGContextSaveGState(context);
    CGContextBeginTransparencyLayer(context, NULL);
    [self.iconImage drawInRect:iconRect
                       fromRect:NSZeroRect
                      operation:NSCompositingOperationSourceOver
                       fraction:1.0];
    [[NSColor colorWithWhite:1.0 alpha:1.0] setFill];
    NSRectFillUsingOperation(iconRect, NSCompositingOperationSourceIn);
    CGContextEndTransparencyLayer(context);
    CGContextRestoreGState(context);
}

- (void)highlight:(BOOL)flag {
    [super highlight:flag];
    self.pressed = flag;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event {
    self.pressed = YES;
    [self setNeedsDisplay:YES];
    [super mouseDown:event];
    self.pressed = NO;
    [self setNeedsDisplay:YES];
}

@end

@interface MTMRLyricsView : NSView
@property(nonatomic, copy) NSString *text;
@property(nonatomic, strong) NSFont *font;
@end

@implementation MTMRLyricsView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _text = @"";
        _font = [NSFont systemFontOfSize:17.0 weight:NSFontWeightRegular];
        self.accessibilityRole = NSAccessibilityStaticTextRole;
    }
    return self;
}

- (void)setText:(NSString *)text {
    _text = [text copy] ?: @"";
    self.accessibilityValue = _text;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.text.length == 0) {
        return;
    }

    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.alignment = NSTextAlignmentCenter;
    paragraphStyle.lineBreakMode = NSLineBreakByTruncatingTail;
    NSDictionary *attributes = @{
        NSFontAttributeName: self.font,
        NSForegroundColorAttributeName: [NSColor colorWithWhite:1.0 alpha:1.0],
        NSParagraphStyleAttributeName: paragraphStyle
    };
    NSSize textSize = [self.text sizeWithAttributes:attributes];
    CGFloat y = floor((NSHeight(self.bounds) - textSize.height) / 2.0) - 0.5;
    NSRect textRect = NSMakeRect(0.0, y, NSWidth(self.bounds), textSize.height + 1.0);
    [self.text drawInRect:textRect withAttributes:attributes];
}

@end

@interface MTMRAppDelegate : NSObject <NSApplicationDelegate, NSTouchBarDelegate>
@property(nonatomic, strong) NSTouchBar *touchBar;
@property(nonatomic, strong) MTMRLyricsView *lyricsField;
@property(nonatomic, strong) NSTimer *lyricsTimer;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *screenSyncMenuItem;
@property(nonatomic, assign) BOOL screenSyncEnabled;
@property(nonatomic, assign) BOOL screensSleeping;
@end

@implementation MTMRAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    DFRSystemModalShowsCloseBoxWhenFrontMost(NO);
    self.screenSyncEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:kScreenSyncPreference] == nil
        ? YES
        : [[NSUserDefaults standardUserDefaults] boolForKey:kScreenSyncPreference];
    [self installStatusItem];
    [self installTouchBar];
    [self installScreenSleepNotifications];
}

- (void)installStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"mtmr-logo" ofType:@"png"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    logo.template = NO;
    logo.size = NSMakeSize(18.0, 18.0);
    self.statusItem.button.image = logo;
    self.statusItem.button.title = @"";

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MTMR-2"];
    self.screenSyncMenuItem = [[NSMenuItem alloc]
        initWithTitle:@"屏幕休眠时同步触控栏"
               action:@selector(toggleScreenSync:)
        keyEquivalent:@""];
    self.screenSyncMenuItem.target = self;
    self.screenSyncMenuItem.state = self.screenSyncEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:self.screenSyncMenuItem];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"退出 MTMR-2" action:@selector(terminate:) keyEquivalent:@"q"];
    self.statusItem.menu = menu;
}

- (void)installScreenSleepNotifications {
    NSNotificationCenter *workspaceCenter = [NSWorkspace sharedWorkspace].notificationCenter;
    [workspaceCenter addObserver:self
                        selector:@selector(screensDidSleep:)
                            name:NSWorkspaceScreensDidSleepNotification
                          object:nil];
    [workspaceCenter addObserver:self
                        selector:@selector(screensDidWake:)
                            name:NSWorkspaceScreensDidWakeNotification
                          object:nil];
}

- (void)toggleScreenSync:(NSMenuItem *)sender {
    self.screenSyncEnabled = !self.screenSyncEnabled;
    [[NSUserDefaults standardUserDefaults] setBool:self.screenSyncEnabled forKey:kScreenSyncPreference];
    sender.state = self.screenSyncEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.screenSyncEnabled && !self.screensSleeping) {
        [self presentTouchBarIfNeeded];
    }
}

- (void)screensDidSleep:(NSNotification *)notification {
    (void)notification;
    self.screensSleeping = YES;
    if (self.screenSyncEnabled && self.touchBar) {
        [NSTouchBar minimizeSystemModalTouchBar:self.touchBar];
    }
}

- (void)screensDidWake:(NSNotification *)notification {
    (void)notification;
    self.screensSleeping = NO;
    [self presentTouchBarIfNeeded];
}

- (void)presentTouchBarIfNeeded {
    if (!self.screenSyncEnabled || self.screensSleeping || !self.touchBar) {
        return;
    }
    [NSTouchBar presentSystemModalTouchBar:self.touchBar
                  systemTrayItemIdentifier:kControlStripIdentifier];
}

- (void)dealloc {
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
}

- (void)installTouchBar {
    self.touchBar = [[NSTouchBar alloc] init];
    self.touchBar.delegate = self;
    self.touchBar.defaultItemIdentifiers = @[
        kPreviousIdentifier,
        kToggleIdentifier,
        kNextIdentifier,
        NSTouchBarItemIdentifierFlexibleSpace,
        kLyricsIdentifier,
        NSTouchBarItemIdentifierFlexibleSpace
    ];

    NSCustomTouchBarItem *controlStrip = [[NSCustomTouchBarItem alloc] initWithIdentifier:kControlStripIdentifier];
    controlStrip.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1, 1)];
    [NSTouchBarItem addSystemTrayItem:controlStrip];
    [NSTouchBar presentSystemModalTouchBar:self.touchBar systemTrayItemIdentifier:kControlStripIdentifier];

    self.lyricsTimer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                                          target:self
                                                        selector:@selector(refreshLyrics)
                                                        userInfo:nil
                                                         repeats:YES];
    [self refreshLyrics];
}

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)touchBar;
    if ([identifier isEqualToString:kPreviousIdentifier]) {
        return [self buttonItem:identifier imageName:NSImageNameTouchBarRewindTemplate accessibilityLabel:@"上一首" action:@selector(previous:)];
    }
    if ([identifier isEqualToString:kToggleIdentifier]) {
        return [self buttonItem:identifier imageName:NSImageNameTouchBarPlayPauseTemplate accessibilityLabel:@"播放/暂停" action:@selector(toggle:)];
    }
    if ([identifier isEqualToString:kNextIdentifier]) {
        return [self buttonItem:identifier imageName:NSImageNameTouchBarFastForwardTemplate accessibilityLabel:@"下一首" action:@selector(next:)];
    }
    if ([identifier isEqualToString:kLyricsIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        self.lyricsField = [[MTMRLyricsView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 300.0, 30.0)];
        self.lyricsField.translatesAutoresizingMaskIntoConstraints = NO;
        item.view = self.lyricsField;
        [NSLayoutConstraint activateConstraints:@[
            [self.lyricsField.widthAnchor constraintEqualToConstant:300.0],
            [self.lyricsField.heightAnchor constraintEqualToConstant:30.0]
        ]];
        return item;
    }
    return nil;
}

- (NSCustomTouchBarItem *)buttonItem:(NSTouchBarItemIdentifier)identifier
                           imageName:(NSImageName)imageName
                 accessibilityLabel:(NSString *)accessibilityLabel
                              action:(SEL)action {
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    MTMRTouchBarButton *button = [MTMRTouchBarButton buttonWithTitle:@"" target:self action:action];
    button.bordered = NO;
    button.bezelStyle = NSBezelStyleRegularSquare;
    button.focusRingType = NSFocusRingTypeNone;
    button.title = accessibilityLabel;
    button.accessibilityLabel = accessibilityLabel;
    button.imagePosition = NSNoImage;
    button.contentTintColor = [NSColor colorWithWhite:1.0 alpha:1.0];
    button.alphaValue = 1.0;
    NSImage *image = [[NSImage imageNamed:imageName] copy];
    image.template = YES;
    button.iconImage = image;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    item.view = button;
    [NSLayoutConstraint activateConstraints:@[
        [button.widthAnchor constraintEqualToConstant:42.0],
        [button.heightAnchor constraintEqualToConstant:28.0]
    ]];
    return item;
}

- (void)runMediaCommand:(NSString *)command {
    static NSDictionary<NSString *, NSNumber *> *commands;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        commands = @{
            @"toggle": @2,
            @"next": @4,
            @"previous": @5
        };
    });
    NSNumber *commandNumber = commands[command];
    if (!commandNumber) {
        return;
    }
    void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_GLOBAL);
    if (!framework) {
        return;
    }
    MRMediaRemoteSendCommandFunction send = (MRMediaRemoteSendCommandFunction)dlsym(framework, "MRMediaRemoteSendCommand");
    if (send) {
        send(commandNumber.integerValue, nil);
    }
    dlclose(framework);
}

- (void)previous:(id)sender {
    (void)sender;
    [self runMediaCommand:@"previous"];
}

- (void)toggle:(id)sender {
    (void)sender;
    [self runMediaCommand:@"toggle"];
}

- (void)next:(id)sender {
    (void)sender;
    [self runMediaCommand:@"next"];
}

- (void)refreshLyrics {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TouchBarLyrics-MTMR-2/display.txt"];
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    self.lyricsField.text = value ?: @"";
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        MTMRAppDelegate *delegate = [[MTMRAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
