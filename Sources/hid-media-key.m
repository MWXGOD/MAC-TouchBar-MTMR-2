#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/graphics/IOGraphicsTypes.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <IOKit/hidsystem/IOHIDShared.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#import <IOKit/hidsystem/ev_keymap.h>

static io_connect_t EventDriver(void) {
    mach_port_t masterPort = MACH_PORT_NULL;
    io_iterator_t iterator = IO_OBJECT_NULL;
    io_service_t service = IO_OBJECT_NULL;
    io_connect_t connection = IO_OBJECT_NULL;

    if (IOMasterPort(bootstrap_port, &masterPort) != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }
    if (IOServiceGetMatchingServices(masterPort,
                                     IOServiceMatching(kIOHIDSystemClass),
                                     &iterator) != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }
    service = IOIteratorNext(iterator);
    if (service != IO_OBJECT_NULL) {
        IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &connection);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return connection;
}

static BOOL PostAuxKey(UInt8 keyCode) {
    io_connect_t driver = EventDriver();
    if (driver == IO_OBJECT_NULL) {
        return NO;
    }

    IOGPoint location = {0, 0};
    UInt32 keyStates[] = {NX_KEYDOWN, NX_KEYUP};
    for (NSUInteger index = 0; index < 2; index++) {
        UInt32 keyState = keyStates[index];
        NXEventData event;
        bzero(&event, sizeof(event));
        event.compound.subType = NX_SUBTYPE_AUX_CONTROL_BUTTONS;
        event.compound.misc.L[0] = ((UInt32)keyCode << 16) | (keyState << 8);
        IOHIDPostEvent(driver, NX_SYSDEFINED, location, &event,
                       kNXEventDataVersion, 0, FALSE);
    }
    IOServiceClose(driver);
    return YES;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) {
            fprintf(stderr, "Usage: hid-media-key play|previous|next\n");
            return 2;
        }

        UInt8 keyCode = 0;
        if (strcmp(argv[1], "play") == 0) {
            keyCode = NX_KEYTYPE_PLAY;
        } else if (strcmp(argv[1], "previous") == 0) {
            keyCode = NX_KEYTYPE_PREVIOUS;
        } else if (strcmp(argv[1], "next") == 0) {
            keyCode = NX_KEYTYPE_NEXT;
        } else {
            fprintf(stderr, "unknown key: %s\n", argv[1]);
            return 2;
        }
        return PostAuxKey(keyCode) ? 0 : 1;
    }
}
