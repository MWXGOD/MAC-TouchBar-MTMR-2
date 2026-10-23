#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ApplicationServices/ApplicationServices.h>
#import <unistd.h>
#import <stdarg.h>

extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL show);

@interface NSTouchBar (MTMRPrivateMethods)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

@interface NSTouchBarItem (MTMRPrivateMethods)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
@end

static NSTouchBarItemIdentifier const kControlStripIdentifier = @"com.ahs.mtmr2.controlStrip";
static NSTouchBarItemIdentifier const kMediaControlsIdentifier = @"com.ahs.mtmr2.mediaControls";
static NSTouchBarItemIdentifier const kLyricsIdentifier = @"com.ahs.mtmr2.lyrics";
static NSString *const kScreenSyncPreference = @"MTMRScreenTouchBarSyncEnabled";
static NSString *const kAgentCommandRequestName = @"command-request.json";
static NSString *const kAgentCommandResultName = @"command-result.json";
static NSString *const kButtonDebugLogName = @"button-debug.log";
static const CGFloat kNativeControlStripButtonWidth = 50.0;
static const CGFloat kNativeControlStripButtonHeight = 30.0;

static NSString *MTMRSupportDirectory(void) {
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/TouchBarLyrics-MTMR-2"];
}

static void MTMRDebugLog(NSString *format, ...) {
    if (format.length == 0) {
        return;
    }

    static NSObject *logLock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        logLock = [[NSObject alloc] init];
    });

    va_list arguments;
    va_start(arguments, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
    va_end(arguments);

    NSString *directory = MTMRSupportDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:directory
           withIntermediateDirectories:YES
                            attributes:@{NSFilePosixPermissions: @0700}
                                 error:nil];
    NSString *path = [directory stringByAppendingPathComponent:kButtonDebugLogName];
    NSString *line = [NSString stringWithFormat:@"%@ %@\n",
        [NSDate date], message];
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];

    @synchronized (logLock) {
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!handle) {
            [data writeToFile:path atomically:YES];
        } else {
            [handle seekToEndOfFile];
            [handle writeData:data];
            [handle closeFile];
        }
    }
}

static BOOL RequestAccessibilityPermission(void) {
    if (AXIsProcessTrusted()) {
        return YES;
    }
    NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    BOOL trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
    if (!trusted) {
        NSLog(@"MTMR-2: 未获得辅助功能权限；网易云 Touch Bar 按钮需要在系统设置中允许 MTMR-2");
    }
    return trusted;
}

static NSString *MTMRAXStringValue(AXUIElementRef element, CFStringRef attribute) {
    if (!element) {
        return nil;
    }
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (error != kAXErrorSuccess || !value) {
        return nil;
    }
    NSString *result = CFGetTypeID(value) == CFStringGetTypeID()
        ? [(__bridge NSString *)value copy]
        : nil;
    CFRelease(value);
    return result;
}

static AXUIElementRef MTMRAXChildWithTitle(AXUIElementRef parent, NSString *title) {
    if (!parent || title.length == 0) {
        return NULL;
    }
    CFTypeRef childrenValue = NULL;
    AXError error = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute, &childrenValue);
    if (error != kAXErrorSuccess || !childrenValue || CFGetTypeID(childrenValue) != CFArrayGetTypeID()) {
        if (childrenValue) {
            CFRelease(childrenValue);
        }
        return NULL;
    }

    AXUIElementRef result = NULL;
    CFArrayRef children = (CFArrayRef)childrenValue;
    for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, index);
        NSString *childTitle = MTMRAXStringValue(child, kAXTitleAttribute);
        if ([childTitle isEqualToString:title]) {
            result = (AXUIElementRef)CFRetain(child);
            break;
        }
    }
    CFRelease(childrenValue);
    return result;
}

static AXUIElementRef MTMRAXChildWithAnyTitle(AXUIElementRef parent, NSArray<NSString *> *titles) {
    if (!parent || titles.count == 0) {
        return NULL;
    }
    for (NSString *title in titles) {
        AXUIElementRef child = MTMRAXChildWithTitle(parent, title);
        if (child) {
            return child;
        }
    }
    return NULL;
}

static AXUIElementRef MTMRAXChildWithRole(AXUIElementRef parent, CFStringRef role) {
    if (!parent || !role) {
        return NULL;
    }
    CFTypeRef childrenValue = NULL;
    AXError error = AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute, &childrenValue);
    if (error != kAXErrorSuccess || !childrenValue || CFGetTypeID(childrenValue) != CFArrayGetTypeID()) {
        if (childrenValue) {
            CFRelease(childrenValue);
        }
        return NULL;
    }
    AXUIElementRef result = NULL;
    CFArrayRef children = (CFArrayRef)childrenValue;
    for (CFIndex index = 0; index < CFArrayGetCount(children); index++) {
        AXUIElementRef child = (AXUIElementRef)CFArrayGetValueAtIndex(children, index);
        NSString *childRole = MTMRAXStringValue(child, kAXRoleAttribute);
        if ([childRole isEqualToString:(__bridge NSString *)role]) {
            result = (AXUIElementRef)CFRetain(child);
            break;
        }
    }
    CFRelease(childrenValue);
    return result;
}

static AXUIElementRef MTMRAXMenuForMenuBarItem(AXUIElementRef menuBarItem) {
    if (!menuBarItem) {
        return NULL;
    }
    return MTMRAXChildWithRole(menuBarItem, kAXMenuRole);
}

static NSRunningApplication *MTMRNetEaseApplication(void) {
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([application.bundleIdentifier isEqualToString:@"com.netease.163music"] &&
            !application.isTerminated) {
            return application;
        }
    }
    return nil;
}

static BOOL MTMRCopyNetEaseAccessibilityElements(AXUIElementRef *outApplication,
                                                  AXUIElementRef *outMenuBar) {
    if (outApplication) {
        *outApplication = NULL;
    }
    if (outMenuBar) {
        *outMenuBar = NULL;
    }
    if (!AXIsProcessTrusted()) {
        MTMRDebugLog(@"accessibility-not-trusted");
        return NO;
    }

    NSRunningApplication *netEase = MTMRNetEaseApplication();
    if (!netEase) {
        MTMRDebugLog(@"netease-not-running");
        return NO;
    }

    // Read NetEase's menu without activating its application. Activating it
    // here makes its window flash every time a Touch Bar command is pressed.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.2];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        AXUIElementRef applicationElement = AXUIElementCreateApplication(netEase.processIdentifier);
        if (!applicationElement) {
            [NSThread sleepForTimeInterval:0.05];
            continue;
        }
        AXUIElementSetMessagingTimeout(applicationElement, 0.5);

        CFTypeRef menuBarValue = NULL;
        AXError error = AXUIElementCopyAttributeValue(applicationElement,
                                                       kAXMenuBarAttribute,
                                                       &menuBarValue);
        BOOL validMenuBar = error == kAXErrorSuccess && menuBarValue &&
            CFGetTypeID(menuBarValue) == AXUIElementGetTypeID();
        if (validMenuBar) {
            if (outApplication) {
                *outApplication = applicationElement;
            } else {
                CFRelease(applicationElement);
            }
            if (outMenuBar) {
                *outMenuBar = (AXUIElementRef)menuBarValue;
            } else {
                CFRelease(menuBarValue);
            }
            MTMRDebugLog(@"netease-menu-ready active=%d", netEase.isActive);
            return YES;
        }
        if (menuBarValue) {
            CFRelease(menuBarValue);
        }
        CFRelease(applicationElement);
        [NSThread sleepForTimeInterval:0.05];
    }

    MTMRDebugLog(@"netease-menu-timeout active=%d", netEase.isActive);
    return NO;
}

static BOOL RunNetEaseAppleScript(NSString *command) {
    if (command.length == 0) {
        MTMRDebugLog(@"command-empty");
        return NO;
    }

    NSString *scriptPath = [[NSBundle mainBundle] pathForResource:@"netease-media-command"
                                                               ofType:@"applescript"];
    if (scriptPath.length == 0) {
        MTMRDebugLog(@"command=%@ script-missing", command);
        return NO;
    }

    MTMRDebugLog(@"command=%@ osascript-start path=%@", command, scriptPath);
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/osascript";
    task.arguments = @[scriptPath, command];
    NSPipe *outputPipe = [NSPipe pipe];
    NSPipe *errorPipe = [NSPipe pipe];
    task.standardOutput = outputPipe;
    task.standardError = errorPipe;

    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        MTMRDebugLog(@"command=%@ osascript-exception=%@", command, exception.reason ?: @"unknown");
        return NO;
    }

    NSData *outputData = outputPipe.fileHandleForReading.readDataToEndOfFile;
    NSData *errorData = errorPipe.fileHandleForReading.readDataToEndOfFile;
    NSString *stdoutText = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
    NSString *stderrText = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
    stdoutText = [stdoutText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    stderrText = [stderrText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    BOOL succeeded = task.terminationStatus == 0;
    MTMRDebugLog(@"command=%@ osascript-end status=%d success=%d stdout=%@ stderr=%@",
                 command,
                 task.terminationStatus,
                 succeeded,
                 stdoutText ?: @"",
                 stderrText ?: @"");
    return succeeded;
}

static BOOL RunAgentNetEaseCommand(NSString *command) {
    NSString *supportDirectory = MTMRSupportDirectory();
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager createDirectoryAtPath:supportDirectory
           withIntermediateDirectories:YES
                            attributes:@{NSFilePosixPermissions: @0700}
                                 error:nil];

    NSString *requestPath = [supportDirectory stringByAppendingPathComponent:kAgentCommandRequestName];
    NSString *resultPath = [supportDirectory stringByAppendingPathComponent:kAgentCommandResultName];
    NSString *requestID = NSUUID.UUID.UUIDString;
    NSDictionary *request = @{ @"id": requestID, @"command": command };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (!requestData || ![requestData writeToFile:requestPath options:NSDataWritingAtomic error:nil]) {
        MTMRDebugLog(@"command=%@ agent-request-write-failed", command);
        return NO;
    }

    MTMRDebugLog(@"command=%@ agent-request-sent", command);

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        NSData *resultData = [NSData dataWithContentsOfFile:resultPath];
        NSDictionary *result = resultData
            ? [NSJSONSerialization JSONObjectWithData:resultData options:0 error:nil]
            : nil;
        if ([result[@"id"] isEqualToString:requestID]) {
            [fileManager removeItemAtPath:resultPath error:nil];
            BOOL succeeded = [result[@"success"] boolValue];
            MTMRDebugLog(@"command=%@ agent-result success=%d", command, succeeded);
            return succeeded;
        }
        [NSThread sleepForTimeInterval:0.02];
    }
    [fileManager removeItemAtPath:requestPath error:nil];
    MTMRDebugLog(@"command=%@ agent-timeout", command);
    return NO;
}

static BOOL PerformNetEaseAccessibilityCommand(NSString *command) {
    NSLog(@"MTMR-2: command=%@ trusted=%d", command, AXIsProcessTrusted());

    NSRunningApplication *netEase = MTMRNetEaseApplication();
    if (!netEase) {
        NSLog(@"MTMR-2: 网易云进程未运行");
        return NO;
    }

    AXUIElementRef applicationElement = NULL;
    AXUIElementRef menuBar = NULL;
    if (!MTMRCopyNetEaseAccessibilityElements(&applicationElement, &menuBar)) {
        NSLog(@"MTMR-2: 无法读取网易云菜单栏，请确认 MTMR-2 已加入辅助功能");
        return NO;
    }

    AXUIElementRef controlBarItem = MTMRAXChildWithTitle(menuBar, @"控制");
    AXUIElementRef controlMenu = MTMRAXMenuForMenuBarItem(controlBarItem);
    NSLog(@"MTMR-2: control=%p menu=%p", controlBarItem, controlMenu);
    NSLog(@"MTMR-2: 控制菜单栏项目=%p 菜单=%p", controlBarItem, controlMenu);

    AXUIElementRef commandItem = NULL;
    if (controlMenu) {
        if ([command isEqualToString:@"toggle"]) {
            commandItem = MTMRAXChildWithAnyTitle(controlMenu, @[@"暂停", @"Pause"]);
            if (!commandItem) {
                commandItem = MTMRAXChildWithAnyTitle(controlMenu, @[@"播放", @"Play"]);
            }
        } else if ([command isEqualToString:@"previous"]) {
            commandItem = MTMRAXChildWithAnyTitle(controlMenu,
                                                   @[@"上一个", @"上一首", @"Previous", @"Previous Track"]);
        } else if ([command isEqualToString:@"next"]) {
            commandItem = MTMRAXChildWithAnyTitle(controlMenu,
                                                   @[@"下一个", @"下一首", @"Next", @"Next Track"]);
        }
    }

    BOOL succeeded = commandItem &&
        AXUIElementPerformAction(commandItem, kAXPressAction) == kAXErrorSuccess;
    NSLog(@"MTMR-2: command item=%p succeeded=%d", commandItem, succeeded);
    NSLog(@"MTMR-2: command=%@ item=%p press=%@", command, commandItem, succeeded ? @"成功" : @"失败");
    if (!succeeded) {
        NSLog(@"MTMR-2: 无法按下网易云菜单项 %@", command);
    }

    if (commandItem) CFRelease(commandItem);
    if (controlMenu) CFRelease(controlMenu);
    if (controlBarItem) CFRelease(controlBarItem);
    CFRelease(menuBar);
    CFRelease(applicationElement);
    return succeeded;
}

static BOOL NetEaseIsPlaying(void) {
    if (!AXIsProcessTrusted()) {
        return NO;
    }

    NSRunningApplication *netEase = nil;
    for (NSRunningApplication *application in NSWorkspace.sharedWorkspace.runningApplications) {
        if ([application.bundleIdentifier isEqualToString:@"com.netease.163music"] && !application.isTerminated) {
            netEase = application;
            break;
        }
    }
    if (!netEase) {
        return NO;
    }

    AXUIElementRef appElement = AXUIElementCreateApplication(netEase.processIdentifier);
    if (!appElement) {
        return NO;
    }
    AXUIElementSetMessagingTimeout(appElement, 0.25);

    CFTypeRef menuBarValue = NULL;
    AXError error = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute, &menuBarValue);
    AXUIElementRef menuBar = (error == kAXErrorSuccess && menuBarValue &&
                              CFGetTypeID(menuBarValue) == AXUIElementGetTypeID())
        ? (AXUIElementRef)menuBarValue : NULL;
    if (!menuBar) {
        if (menuBarValue) CFRelease(menuBarValue);
        CFRelease(appElement);
        return NO;
    }

    AXUIElementRef controlBarItem = MTMRAXChildWithTitle(menuBar, @"控制");
    AXUIElementRef controlMenu = MTMRAXChildWithRole(controlBarItem, kAXMenuRole);
    AXUIElementRef pauseItem = controlMenu ? MTMRAXChildWithTitle(controlMenu, @"暂停") : NULL;
    BOOL playing = pauseItem != NULL;

    if (pauseItem) CFRelease(pauseItem);
    if (controlMenu) CFRelease(controlMenu);
    if (controlBarItem) CFRelease(controlBarItem);
    CFRelease(menuBar);
    CFRelease(appElement);
    return playing;
}

static BOOL ReadAgentPlayingState(BOOL *hasState) {
    if (hasState) {
        *hasState = NO;
    }

    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/TouchBarLyrics-MTMR-2/state.json"];
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) {
        return NO;
    }

    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![state isKindOfClass:[NSDictionary class]] || state[@"playing"] == nil) {
        return NO;
    }
    if (hasState) {
        *hasState = YES;
    }
    return [state[@"playing"] boolValue];
}

static BOOL NetEaseStateIsCurrent(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/TouchBarLyrics-MTMR-2/state.json"];
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) {
        return NO;
    }
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [state isKindOfClass:[NSDictionary class]] &&
        [state[@"bundle"] isEqualToString:@"com.netease.163music"];
}

static NSDictionary *MTMRReadNetEaseState(void) {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Application Support/TouchBarLyrics-MTMR-2/state.json"];
    NSData *data = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
    if (!data) {
        return nil;
    }
    NSDictionary *state = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [state isKindOfClass:[NSDictionary class]] ? state : nil;
}

static BOOL MTMRStateChangedForCommand(NSString *command,
                                       NSDictionary *before,
                                       NSDictionary **outAfter) {
    if (!before || ![before isKindOfClass:[NSDictionary class]]) {
        return NO;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.25];
    while ([deadline timeIntervalSinceNow] > 0.0) {
        NSDictionary *after = MTMRReadNetEaseState();
        if (after) {
            BOOL changed = NO;
            if ([command isEqualToString:@"toggle"]) {
                changed = before && after[@"playing"] != nil &&
                    [before[@"playing"] boolValue] != [after[@"playing"] boolValue];
            } else {
                NSString *beforeTitle = [before[@"title"] isKindOfClass:[NSString class]]
                    ? before[@"title"] : @"";
                NSString *afterTitle = [after[@"title"] isKindOfClass:[NSString class]]
                    ? after[@"title"] : @"";
                NSString *beforeArtist = [before[@"artist"] isKindOfClass:[NSString class]]
                    ? before[@"artist"] : @"";
                NSString *afterArtist = [after[@"artist"] isKindOfClass:[NSString class]]
                    ? after[@"artist"] : @"";
                double beforeElapsed = [before[@"elapsed"] doubleValue];
                double afterElapsed = [after[@"elapsed"] doubleValue];
                // Elapsed time naturally advances while waiting for the new
                // state, so it cannot prove that previous/next was handled.
                // A title/artist change proves a track switch; a large rewind
                // also covers replaying the same track.
                changed = ![beforeTitle isEqualToString:afterTitle] ||
                    ![beforeArtist isEqualToString:afterArtist] ||
                    afterElapsed + 2.0 < beforeElapsed;
            }
            if (changed) {
                if (outAfter) {
                    *outAfter = after;
                }
                return YES;
            }
        }
        [NSThread sleepForTimeInterval:0.05];
    }
    if (outAfter) {
        *outAfter = MTMRReadNetEaseState();
    }
    return NO;
}

static BOOL RunBundledNetEaseMediaCommand(NSString *command) {
    if (command.length == 0 || !NetEaseStateIsCurrent()) {
        MTMRDebugLog(@"command=%@ mediaremote-skipped bundle-not-netease", command);
        return NO;
    }

    NSString *commandPath = [[NSBundle mainBundle] pathForResource:@"touchbar-media-command" ofType:nil];
    if (commandPath.length == 0) {
        MTMRDebugLog(@"command=%@ mediaremote-binary-missing", command);
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = commandPath;
    task.arguments = @[command];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        MTMRDebugLog(@"command=%@ mediaremote-exception=%@", command, exception.reason ?: @"unknown");
        return NO;
    }

    BOOL succeeded = task.terminationStatus == 0;
    MTMRDebugLog(@"command=%@ mediaremote-status=%d success=%d", command, task.terminationStatus, succeeded);
    return succeeded;
}

static BOOL RunBundledHIDMediaCommand(NSString *command) {
    if (command.length == 0 || !NetEaseStateIsCurrent()) {
        MTMRDebugLog(@"command=%@ hid-skipped bundle-not-netease", command);
        return NO;
    }

    NSString *commandPath = [[NSBundle mainBundle] pathForResource:@"hid-media-key" ofType:nil];
    if (commandPath.length == 0) {
        MTMRDebugLog(@"command=%@ hid-binary-missing", command);
        return NO;
    }

    NSString *hidCommand = [command isEqualToString:@"toggle"] ? @"play" : command;
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = commandPath;
    task.arguments = @[hidCommand];
    @try {
        [task launch];
        [task waitUntilExit];
    } @catch (NSException *exception) {
        MTMRDebugLog(@"command=%@ hid-exception=%@", command, exception.reason ?: @"unknown");
        return NO;
    }

    BOOL succeeded = task.terminationStatus == 0;
    MTMRDebugLog(@"command=%@ hid-status=%d success=%d", command, task.terminationStatus, succeeded);
    return succeeded;
}

static NSImage *WhiteTouchBarImage(NSImage *source) {
    if (!source) {
        return nil;
    }
    NSSize size = source.size;
    CGImageRef sourceImage = [source CGImageForProposedRect:NULL context:nil hints:nil];
    if (!sourceImage) {
        return source;
    }
    CGFloat scale = 2.0;
    size_t width = (size_t)ceil(size.width * scale);
    size_t height = (size_t)ceil(size.height * scale);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                                  colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        return source;
    }
    CGContextClearRect(context, CGRectMake(0.0, 0.0, width, height));
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), sourceImage);
    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    CGContextSetRGBFillColor(context, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(context, CGRectMake(0.0, 0.0, width, height));
    CGImageRef whiteImage = CGBitmapContextCreateImage(context);
    NSImage *result = whiteImage ? [[NSImage alloc] initWithCGImage:whiteImage size:size] : source;
    if (whiteImage) {
        CGImageRelease(whiteImage);
    }
    CGContextRelease(context);
    result.template = NO;
    return result;
}

static NSImage *BundledNetEaseTouchBarImage(NSString *name) {
    if (name.length == 0) {
        return nil;
    }
    NSString *path = [[NSBundle mainBundle] pathForResource:name
                                                        ofType:@"png"
                                                   inDirectory:@"netease-touchbar"];
    NSImage *image = path.length > 0 ? [[NSImage alloc] initWithContentsOfFile:path] : nil;
    if (!image) {
        return nil;
    }
    // The catalog rendition is 44x44 pixels for a 22x22 point Touch Bar icon.
    image.size = NSMakeSize(22.0, 22.0);
    image.template = NO;
    return image;
}

@interface MTMRMediaButton : NSButton
@property(nonatomic, strong) NSImage *normalAsset;
@property(nonatomic, strong) NSImage *pressedAsset;
- (instancetype)initWithNormalAsset:(NSImage *)normalAsset
                        pressedAsset:(NSImage *)pressedAsset
                              target:(id)target
                              action:(SEL)action;
@end

@implementation MTMRMediaButton

- (instancetype)initWithNormalAsset:(NSImage *)normalAsset
                        pressedAsset:(NSImage *)pressedAsset
                              target:(id)target
                              action:(SEL)action {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _normalAsset = normalAsset;
        _pressedAsset = pressedAsset ?: normalAsset;
        self.target = target;
        self.action = action;
        self.bordered = NO;
        self.transparent = NO;
        self.buttonType = NSButtonTypeMomentaryLight;
        self.focusRingType = NSFocusRingTypeNone;
        self.imagePosition = NSImageOnly;
        self.imageScaling = NSImageScaleNone;
        self.title = @"";
        self.translatesAutoresizingMaskIntoConstraints = NO;
    }
    return self;
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.isHighlighted) {
        [[NSColor colorWithWhite:1.0 alpha:0.12] setFill];
        NSRectFill(self.bounds);
    }

    NSImage *asset = self.isHighlighted ? self.pressedAsset : self.normalAsset;
    if (!asset) {
        return;
    }
    NSSize imageSize = NSMakeSize(22.0, 22.0);
    NSRect imageRect = NSMakeRect(floor((NSWidth(self.bounds) - imageSize.width) / 2.0),
                                  floor((NSHeight(self.bounds) - imageSize.height) / 2.0),
                                  imageSize.width,
                                  imageSize.height);
    [asset drawInRect:imageRect
             fromRect:NSZeroRect
            operation:NSCompositingOperationSourceOver
             fraction:1.0
       respectFlipped:YES
                hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
}

@end

@interface MTMRMediaSeparatorView : NSView
@end

@implementation MTMRMediaSeparatorView

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithWhite:0.08 alpha:1.0] setFill];
    NSRectFill(self.bounds);
}

- (NSView *)hitTest:(NSPoint)point {
    (void)point;
    return nil;
}

@end

@interface MTMRMediaControlsView : NSView
@property(nonatomic, assign, getter=isPlaying) BOOL playing;
@property(nonatomic, strong) MTMRMediaButton *playButton;
- (instancetype)initWithFrame:(NSRect)frame target:(id)target;
@end

@implementation MTMRMediaControlsView

- (instancetype)initWithFrame:(NSRect)frame target:(id)target {
    self = [super initWithFrame:frame];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.wantsLayer = YES;
        self.layer.cornerRadius = 7.0;
        self.layer.masksToBounds = YES;
        self.accessibilityRole = NSAccessibilityGroupRole;
        self.accessibilityLabel = @"网易云音乐控制";

        BOOL hasPlayingState = NO;
        BOOL playingState = ReadAgentPlayingState(&hasPlayingState);
        self.playing = hasPlayingState && playingState;

        NSArray<NSDictionary *> *definitions = @[
            @{
                @"label": @"上一首",
                @"assetName": @"TouchBarLast",
                @"action": NSStringFromSelector(@selector(previous:))
            },
            @{
                @"label": @"播放或暂停",
                @"assetName": self.playing ? @"TouchBarPause" : @"TouchBarPlay",
                @"action": NSStringFromSelector(@selector(toggle:))
            },
            @{
                @"label": @"下一首",
                @"assetName": @"TouchBarNext",
                @"action": NSStringFromSelector(@selector(next:))
            }
        ];

        NSMutableArray<NSView *> *buttons = [NSMutableArray arrayWithCapacity:definitions.count];
        for (NSDictionary *definition in definitions) {
            NSImage *image = BundledNetEaseTouchBarImage(definition[@"assetName"]);
            MTMRMediaButton *button = [[MTMRMediaButton alloc]
                initWithNormalAsset:image
                        pressedAsset:image
                              target:target
                              action:NSSelectorFromString(definition[@"action"])];
            button.title = definition[@"label"];
            button.accessibilityLabel = definition[@"label"];
            button.accessibilityRole = NSAccessibilityButtonRole;
            if ([definition[@"action"] isEqualToString:NSStringFromSelector(@selector(toggle:))]) {
                self.playButton = button;
            }
            [self addSubview:button];
            [buttons addObject:button];
        }

        for (NSUInteger index = 0; index < buttons.count; index++) {
            NSView *button = buttons[index];
            [NSLayoutConstraint activateConstraints:@[
                [button.widthAnchor constraintEqualToConstant:kNativeControlStripButtonWidth],
                [button.heightAnchor constraintEqualToConstant:kNativeControlStripButtonHeight],
                [button.topAnchor constraintEqualToAnchor:self.topAnchor],
                [button.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
            ]];
            if (index == 0) {
                [button.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
            } else {
                [button.leadingAnchor constraintEqualToAnchor:buttons[index - 1].trailingAnchor].active = YES;
            }
            if (index == buttons.count - 1) {
                [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
            }
        }

        for (NSUInteger index = 1; index < buttons.count; index++) {
            MTMRMediaSeparatorView *separator = [[MTMRMediaSeparatorView alloc] initWithFrame:NSZeroRect];
            separator.translatesAutoresizingMaskIntoConstraints = NO;
            [self addSubview:separator];
            [NSLayoutConstraint activateConstraints:@[
                [separator.widthAnchor constraintEqualToConstant:1.0],
                [separator.topAnchor constraintEqualToAnchor:self.topAnchor],
                [separator.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
                [separator.leadingAnchor constraintEqualToAnchor:buttons[index - 1].trailingAnchor]
            ]];
        }
    }
    return self;
}

- (void)setPlaying:(BOOL)playing {
    _playing = playing;
    if (!self.playButton) {
        return;
    }
    NSString *assetName = playing ? @"TouchBarPause" : @"TouchBarPlay";
    NSImage *asset = BundledNetEaseTouchBarImage(assetName);
    if (asset) {
        self.playButton.normalAsset = asset;
        self.playButton.pressedAsset = asset;
        [self.playButton setNeedsDisplay:YES];
    }
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[NSColor colorWithWhite:0.20 alpha:1.0] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:7.0 yRadius:7.0] fill];
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
@property(nonatomic, strong) NSButtonTouchBarItem *controlStripItem;
@property(nonatomic, strong) MTMRMediaControlsView *mediaControls;
@property(nonatomic, strong) NSMenuItem *screenSyncMenuItem;
@property(nonatomic, assign) BOOL screenSyncEnabled;
@property(nonatomic, assign) BOOL screensSleeping;
@property(nonatomic, assign) NSTimeInterval lastMediaStateRefresh;
@property(nonatomic, assign) BOOL mediaStateRefreshInFlight;
@property(nonatomic, strong) dispatch_queue_t mediaCommandQueue;
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
    self.mediaCommandQueue = dispatch_queue_create("com.ahs.mtmr2.media-command", DISPATCH_QUEUE_SERIAL);
    RequestAccessibilityPermission();
}

- (void)installStatusItem {
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    NSImage *logo = [self logoImageWhiteOnly:NO rounded:YES displaySize:NSMakeSize(18.0, 18.0)];
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

- (void)restoreTouchBar:(id)sender {
    (void)sender;
    if (!self.touchBar || self.screensSleeping) {
        return;
    }
    [NSTouchBar presentSystemModalTouchBar:self.touchBar
                  systemTrayItemIdentifier:kControlStripIdentifier];
}

- (NSImage *)logoImageWhiteOnly:(BOOL)whiteOnly rounded:(BOOL)useRoundedCorners displaySize:(NSSize)displaySize {
    NSString *logoPath = [[NSBundle mainBundle] pathForResource:@"mtmr-logo" ofType:@"png"];
    NSImage *source = [[NSImage alloc] initWithContentsOfFile:logoPath];
    if (!source) {
        return nil;
    }

    NSSize outputSize = NSMakeSize(32.0, 32.0);
    NSImage *sourceToDraw = source;
    if (whiteOnly) {
        CGImageRef sourceCGImage = [source CGImageForProposedRect:NULL context:nil hints:nil];
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmapContext = CGBitmapContextCreate(NULL,
                                                            (size_t)outputSize.width,
                                                            (size_t)outputSize.height,
                                                            8,
                                                            (size_t)outputSize.width * 4,
                                                            colorSpace,
                                                            kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorSpace);
        if (sourceCGImage && bitmapContext) {
            CGContextSetInterpolationQuality(bitmapContext, kCGInterpolationHigh);
            CGContextDrawImage(bitmapContext,
                               CGRectMake(0.0, 0.0, outputSize.width, outputSize.height),
                               sourceCGImage);

            uint8_t *pixels = CGBitmapContextGetData(bitmapContext);
            if (pixels) {
                size_t pixelCount = (size_t)outputSize.width * (size_t)outputSize.height;
                for (size_t index = 0; index < pixelCount; index++) {
                    uint8_t *pixel = pixels + (index * 4);
                    uint8_t luminance = (uint8_t)(((uint16_t)pixel[0] * 77
                                                 + (uint16_t)pixel[1] * 150
                                                 + (uint16_t)pixel[2] * 29) / 256);
                    // The source is an RGB logo with a white background. Use
                    // darkness as the alpha mask and paint the mark white;
                    // do not carry the white background into the Touch Bar.
                    uint8_t alpha = (uint8_t)(((uint16_t)(255 - luminance) * pixel[3]) / 255);
                    pixel[0] = 255;
                    pixel[1] = 255;
                    pixel[2] = 255;
                    pixel[3] = alpha;
                }

                CGImageRef whiteCGImage = CGBitmapContextCreateImage(bitmapContext);
                if (whiteCGImage) {
                    sourceToDraw = [[NSImage alloc] initWithCGImage:whiteCGImage size:outputSize];
                    CGImageRelease(whiteCGImage);
                }
            }
        }
        if (bitmapContext) {
            CGContextRelease(bitmapContext);
        }
    }

    NSImage *result = [[NSImage alloc] initWithSize:outputSize];
    [result lockFocus];
    [[NSColor clearColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, outputSize.width, outputSize.height));

    if (useRoundedCorners) {
        NSBezierPath *clipPath = [NSBezierPath bezierPathWithRoundedRect:
            NSMakeRect(0.0, 0.0, outputSize.width, outputSize.height)
            xRadius:7.0
            yRadius:7.0];
        [clipPath addClip];
    }
    [sourceToDraw drawInRect:NSMakeRect(0.0, 0.0, outputSize.width, outputSize.height)
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0];
    [result unlockFocus];
    result.template = NO;
    result.size = displaySize;
    return result;
}

- (void)dealloc {
    [[NSWorkspace sharedWorkspace].notificationCenter removeObserver:self];
}

- (void)installTouchBar {
    self.touchBar = [[NSTouchBar alloc] init];
    self.touchBar.delegate = self;
    self.touchBar.defaultItemIdentifiers = @[
        kMediaControlsIdentifier,
        NSTouchBarItemIdentifierFlexibleSpace,
        kLyricsIdentifier,
        NSTouchBarItemIdentifierFlexibleSpace
    ];

    NSImage *controlStripLogo = [self logoImageWhiteOnly:YES rounded:NO displaySize:NSMakeSize(20.0, 20.0)];
    self.controlStripItem = [NSButtonTouchBarItem
        buttonTouchBarItemWithIdentifier:kControlStripIdentifier
                                  image:controlStripLogo
                                  target:self
                                  action:@selector(restoreTouchBar:)];
    self.controlStripItem.view.accessibilityLabel = @"恢复 MTMR-2 歌词";
    self.controlStripItem.customizationLabel = @"MTMR-2";
    [NSTouchBarItem addSystemTrayItem:self.controlStripItem];
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
    if ([identifier isEqualToString:kMediaControlsIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        MTMRMediaControlsView *controls = [[MTMRMediaControlsView alloc]
            initWithFrame:NSMakeRect(0.0, 0.0,
                                     kNativeControlStripButtonWidth * 3.0,
                                     kNativeControlStripButtonHeight)
                   target:self];
        self.mediaControls = controls;
        item.view = controls;
        [NSLayoutConstraint activateConstraints:@[
            [controls.widthAnchor constraintEqualToConstant:kNativeControlStripButtonWidth * 3.0],
            [controls.heightAnchor constraintEqualToConstant:kNativeControlStripButtonHeight]
        ]];
        item.customizationLabel = @"网易云音乐控制";
        return item;
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

- (void)runNetEaseCommand:(NSString *)command {
    MTMRDebugLog(@"run-command=%@", command);
    dispatch_queue_t commandQueue = self.mediaCommandQueue;
    if (!commandQueue) {
        commandQueue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    }
    dispatch_async(commandQueue, ^{
        NSDictionary *before = MTMRReadNetEaseState();
        MTMRDebugLog(@"command=%@ accessibility-trusted=%d before-title=%@ before-playing=%@ before-elapsed=%@",
                     command,
                     AXIsProcessTrusted(),
                     before[@"title"] ?: @"",
                     before[@"playing"] ?: @"",
                     before[@"elapsed"] ?: @"");

        // The Accessibility path is explicitly targeted at NetEase. The HID
        // fallback below is only enabled while the agent identifies NetEase
        // as the current player, because macOS can otherwise route a media
        // key to another active player.
        if (AXIsProcessTrusted()) {
            BOOL accessibilityAccepted = PerformNetEaseAccessibilityCommand(command);
            if (accessibilityAccepted) {
                BOOL changed = MTMRStateChangedForCommand(command, before, NULL);
                MTMRDebugLog(@"command=%@ accessibility-press-accepted state-changed=%d",
                             command, changed ? 1 : 0);
                return;
            }
        } else {
            MTMRDebugLog(@"command=%@ accessibility-not-trusted", command);
        }

        // HID media keys do not require Accessibility permission and do not
        // activate NetEase. Only reach this path while the agent still
        // identifies NetEase as the current player; otherwise a system media
        // key could be delivered to an unrelated player. Keep this before
        // the slower AppleScript/agent fallbacks so a click never waits on a
        // known TCC failure.
        BOOL hidAccepted = RunBundledHIDMediaCommand(command);
        if (hidAccepted) {
            BOOL changed = MTMRStateChangedForCommand(command, before, NULL);
            MTMRDebugLog(@"command=%@ hid-accepted state-changed=%d",
                         command, changed ? 1 : 0);
            return;
        }

        // AppleScript is a targeted fallback for installations where
        // osascript has already been granted UI scripting permission.
        BOOL appleScriptAccepted = RunNetEaseAppleScript(command);
        if (appleScriptAccepted) {
            BOOL changed = MTMRStateChangedForCommand(command, before, NULL);
            MTMRDebugLog(@"command=%@ applescript-accepted state-changed=%d",
                         command, changed ? 1 : 0);
            return;
        }

        // The long-lived agent is kept as a second targeted fallback. It is
        // useful when the agent, rather than MTMR-2, owns the UI permission.
        BOOL agentAccepted = RunAgentNetEaseCommand(command);
        if (agentAccepted) {
            BOOL changed = MTMRStateChangedForCommand(command, before, NULL);
            MTMRDebugLog(@"command=%@ agent-accepted state-changed=%d",
                         command, changed ? 1 : 0);
            return;
        }

        MTMRDebugLog(@"run-command=%@ failed: targeted NetEase command unavailable; no generic fallback sent",
                     command);
    });
}

- (void)previous:(id)sender {
    (void)sender;
    MTMRDebugLog(@"callback=previous");
    [self runNetEaseCommand:@"previous"];
}

- (void)toggle:(id)sender {
    (void)sender;
    MTMRDebugLog(@"callback=toggle");
    [self runNetEaseCommand:@"toggle"];
}

- (void)next:(id)sender {
    (void)sender;
    MTMRDebugLog(@"callback=next");
    [self runNetEaseCommand:@"next"];
}

- (void)refreshLyrics {
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/TouchBarLyrics-MTMR-2/display.txt"];
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    self.lyricsField.text = value ?: @"";

    BOOL hasPlayingState = NO;
    BOOL playing = ReadAgentPlayingState(&hasPlayingState);
    if (hasPlayingState) {
        self.mediaControls.playing = playing;
    }
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
