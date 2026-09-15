#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *StringValue(CFTypeRef value) {
    if (!value) {
        return @"";
    }
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        return [(__bridge NSString *)value copy];
    }
    if (CFGetTypeID(value) == CFNumberGetTypeID()) {
        return [(__bridge NSNumber *)value stringValue];
    }
    return [(__bridge id)value description] ?: @"";
}

static NSString *pressTitle = nil;

static NSString *AttributeString(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, attribute, &value);
    if (error != kAXErrorSuccess || !value) {
        return @"";
    }
    NSString *result = StringValue(value);
    CFRelease(value);
    return result;
}

static BOOL IsCandidate(NSDictionary *record) {
    NSString *text = [[NSString stringWithFormat:@"%@ %@ %@ %@ %@",
                       record[@"role"] ?: @"",
                       record[@"subrole"] ?: @"",
                       record[@"title"] ?: @"",
                       record[@"description"] ?: @"",
                       record[@"identifier"] ?: @""] lowercaseString];
    NSArray<NSString *> *keywords = @[
        @"touchbar", @"touch bar", @"lyric", @"歌词", @"play", @"pause",
        @"next", @"previous", @"上一个", @"下一个"
    ];
    for (NSString *keyword in keywords) {
        if ([text containsString:keyword]) {
            return YES;
        }
    }
    return NO;
}

static void WalkElement(AXUIElementRef element,
                        NSInteger depth,
                        NSInteger maxDepth,
                        NSString *path,
                        NSMutableArray<NSDictionary *> *records) {
    NSString *role = AttributeString(element, kAXRoleAttribute);
    NSString *subrole = AttributeString(element, kAXSubroleAttribute);
    NSString *title = AttributeString(element, kAXTitleAttribute);
    NSString *description = AttributeString(element, kAXDescriptionAttribute);
    NSString *identifier = AttributeString(element, kAXIdentifierAttribute);
    NSMutableDictionary *record = [@{
        @"depth": @(depth),
        @"path": path ?: @"",
        @"role": role ?: @"",
        @"subrole": subrole ?: @"",
        @"title": title ?: @"",
        @"description": description ?: @"",
        @"identifier": identifier ?: @"",
        @"candidate": @(IsCandidate(@{
            @"role": role ?: @"",
            @"subrole": subrole ?: @"",
            @"title": title ?: @"",
            @"description": description ?: @"",
            @"identifier": identifier ?: @""
        }))
    } mutableCopy];
    if (pressTitle && [role isEqualToString:@"AXButton"] && [title isEqualToString:pressTitle]) {
        AXError pressError = AXUIElementPerformAction(element, kAXPressAction);
        record[@"pressed"] = @(pressError == kAXErrorSuccess);
        record[@"pressError"] = @(pressError);
    }
    [records addObject:record];

    if (depth >= maxDepth) {
        return;
    }

    CFTypeRef childrenValue = NULL;
    AXError error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute, &childrenValue);
    if (error != kAXErrorSuccess || !childrenValue ||
        CFGetTypeID(childrenValue) != CFArrayGetTypeID()) {
        if (childrenValue) {
            CFRelease(childrenValue);
        }
        return;
    }

    CFArrayRef children = (CFArrayRef)childrenValue;
    CFIndex count = CFArrayGetCount(children);
    for (CFIndex index = 0; index < count; index++) {
        const void *value = CFArrayGetValueAtIndex(children, index);
        if (!value || CFGetTypeID(value) != AXUIElementGetTypeID()) {
            continue;
        }
        NSString *childPath = [NSString stringWithFormat:@"%@.%ld", path ?: @"0", index];
        WalkElement((AXUIElementRef)value, depth + 1, maxDepth, childPath, records);
    }
    CFRelease(childrenValue);
}

static void PrintUsage(void) {
    fprintf(stderr, "Usage: ax-touchbar-probe [--bundle BUNDLE_ID] [--depth N] [--json] [--press-title TITLE]\n");
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *bundleID = @"com.netease.163music";
        NSInteger maxDepth = 7;
        BOOL jsonOutput = NO;

        for (int index = 1; index < argc; index++) {
            if (strcmp(argv[index], "--json") == 0) {
                jsonOutput = YES;
            } else if (strcmp(argv[index], "--bundle") == 0 && index + 1 < argc) {
                bundleID = [NSString stringWithUTF8String:argv[++index]];
            } else if (strcmp(argv[index], "--depth") == 0 && index + 1 < argc) {
                maxDepth = MAX(0, atoi(argv[++index]));
            } else if (strcmp(argv[index], "--press-title") == 0 && index + 1 < argc) {
                pressTitle = [NSString stringWithUTF8String:argv[++index]];
            } else {
                PrintUsage();
                return 2;
            }
        }

        NSArray<NSRunningApplication *> *applications =
            [[NSWorkspace sharedWorkspace] runningApplications];
        NSRunningApplication *target = nil;
        for (NSRunningApplication *application in applications) {
            if ([application.bundleIdentifier isEqualToString:bundleID] && !application.isTerminated) {
                target = application;
                break;
            }
        }

        NSMutableDictionary *result = [@{
            @"bundleIdentifier": bundleID,
            @"accessibilityTrusted": @(AXIsProcessTrusted()),
            @"running": @(target != nil),
            @"frontmost": @(target.isActive),
            @"pid": target ? @(target.processIdentifier) : @0,
            @"records": @[]
        } mutableCopy];

        if (!target) {
            result[@"error"] = @"target application is not running";
        } else {
            AXUIElementRef applicationElement = AXUIElementCreateApplication(target.processIdentifier);
            AXUIElementSetMessagingTimeout(applicationElement, 0.5);
            NSMutableArray<NSDictionary *> *records = [NSMutableArray array];
            WalkElement(applicationElement, 0, maxDepth, @"0", records);
            result[@"records"] = records;
            if (records.count == 0) {
                result[@"error"] = @"no accessibility records returned";
            }
            CFRelease(applicationElement);
        }

        if (jsonOutput) {
            NSError *error = nil;
            NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:&error];
            if (!data) {
                fprintf(stderr, "failed to encode JSON: %s\n", error.localizedDescription.UTF8String);
                return 1;
            }
            fwrite(data.bytes, 1, data.length, stdout);
            fputc('\n', stdout);
        } else {
            printf("bundle: %s\n", bundleID.UTF8String);
            printf("running: %s\n", [result[@"running"] boolValue] ? "yes" : "no");
            printf("frontmost: %s\n", [result[@"frontmost"] boolValue] ? "yes" : "no");
            printf("accessibility trusted: %s\n",
                   [result[@"accessibilityTrusted"] boolValue] ? "yes" : "no");
            if (result[@"error"]) {
                printf("error: %s\n", [result[@"error"] UTF8String]);
            }
            for (NSDictionary *record in result[@"records"]) {
                NSString *indent = [@"  " stringByPaddingToLength:MIN(40, [record[@"depth"] integerValue] * 2)
                                                  withString:@" "
                                             startingAtIndex:0];
                printf("%s%s title=%s description=%s identifier=%s%s\n",
                       indent.UTF8String,
                       [record[@"role"] UTF8String],
                       [record[@"title"] UTF8String],
                       [record[@"description"] UTF8String],
                       [record[@"identifier"] UTF8String],
                       [record[@"candidate"] boolValue] ? " [candidate]" : "");
            }
        }
        return target ? 0 : 3;
    }
}
