#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>

static NSDictionary<NSString *, NSString *> *MTMRChineseTitles(void) {
    return @{
        @"Preferences": @"偏好设置",
        @"Open preset": @"打开配置文件",
        @"Check for Updates...": @"检查更新...",
        @"Settings": @"设置",
        @"Haptic Feedback": @"触觉反馈",
        @"Hide Control Strip": @"隐藏原生 Control Strip",
        @"Toggle current app in blacklist": @"将当前应用加入黑名单",
        @"Start at login": @"开机启动",
        @"Volume/Brightness gestures": @"音量/亮度手势",
        @"Quit": @"退出 MTMR",
        @"About MTMR": @"关于 MTMR",
        @"About": @"关于",
        @"Settings…": @"设置…",
        @"Hide MTMR": @"隐藏 MTMR",
        @"Quit MTMR": @"退出 MTMR",
        @"Services": @"服务",
        @"Show All": @"显示全部",
        @"Hide Others": @"隐藏其他",
        @"Show All Applications": @"显示所有应用"
    };
}

static NSString *MTMRLocalizedTitle(NSString *title) {
    return MTMRChineseTitles()[title] ?: title;
}

static void (*MTMROriginalSetTitle)(id, SEL, NSString *);
static void MTMRLocalizedSetTitle(id self, SEL selector, NSString *title) {
    MTMROriginalSetTitle(self, selector, MTMRLocalizedTitle(title));
}

static id (*MTMROriginalInitWithTitle)(id, SEL, NSString *, SEL, NSString *);
static id MTMRLocalizedInitWithTitle(id self, SEL selector, NSString *title, SEL action, NSString *keyEquivalent) {
    return MTMROriginalInitWithTitle(self, selector, MTMRLocalizedTitle(title), action, keyEquivalent);
}

static void MTMRInstallMenuTitleHooks(void) {
    Class menuItemClass = [NSMenuItem class];
    Method setTitle = class_getInstanceMethod(menuItemClass, @selector(setTitle:));
    MTMROriginalSetTitle = (void (*)(id, SEL, NSString *))method_getImplementation(setTitle);
    method_setImplementation(setTitle, (IMP)MTMRLocalizedSetTitle);

    Method initWithTitle = class_getInstanceMethod(menuItemClass, @selector(initWithTitle:action:keyEquivalent:));
    MTMROriginalInitWithTitle = (id (*)(id, SEL, NSString *, SEL, NSString *))method_getImplementation(initWithTitle);
    method_setImplementation(initWithTitle, (IMP)MTMRLocalizedInitWithTitle);
}

static void MTMRSetStatusItemImage(NSImage *logo) {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    NSArray *items = nil;
    @try {
        items = [statusBar valueForKey:@"statusItems"];
    } @catch (__unused NSException *exception) {
        items = nil;
    }
    for (NSStatusItem *item in items) {
        if (item.menu) item.button.image = logo;
    }
}

static void MTMRLocalizeMenuItems(NSMenu *menu, NSDictionary<NSString *, NSString *> *titles) {
    for (NSMenuItem *item in menu.itemArray) {
        NSString *localized = titles[item.title];
        if (localized) item.title = localized;
        if (item.submenu) MTMRLocalizeMenuItems(item.submenu, titles);
    }
}

static void MTMRLocalizeMenu(void) {
    NSStatusItem *statusItem = nil;
    @try {
        statusItem = [(id)NSApp.delegate valueForKey:@"statusItem"];
    } @catch (__unused NSException *exception) {
        statusItem = nil;
    }

    NSDictionary *titles = MTMRChineseTitles();
    NSString *logoPath = [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:@"mtmr-logo.png"];
    NSImage *logo = [[NSImage alloc] initWithContentsOfFile:logoPath];
    // Preserve the white background and black mark from the supplied logo.
    logo.template = NO;
    // The source is 32 px for retina rendering; the menu bar slot is 16 pt.
    logo.size = NSMakeSize(16.0, 16.0);
    if (statusItem) {
        statusItem.button.image = logo;
        MTMRLocalizeMenuItems(statusItem.menu, titles);
    }
    MTMRSetStatusItemImage(logo);

    NSMenu *applicationMenu = NSApp.mainMenu;
    if (applicationMenu) MTMRLocalizeMenuItems(applicationMenu, titles);
}

__attribute__((constructor)) static void MTMRInstallMenuLocalizer(void) {
    MTMRInstallMenuTitleHooks();
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSTimer scheduledTimerWithTimeInterval:0.5
                                         repeats:YES
                                           block:^(__unused NSTimer *timer) {
            MTMRLocalizeMenu();
        }];
    });
}
