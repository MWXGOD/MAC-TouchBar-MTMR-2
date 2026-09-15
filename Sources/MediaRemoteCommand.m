#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef bool (*MRMediaRemoteSendCommandFunction)(NSInteger command, NSDictionary *userInfo);

static NSInteger commandForName(const char *name) {
    if (strcmp(name, "play") == 0) return 0;
    if (strcmp(name, "pause") == 0) return 1;
    if (strcmp(name, "toggle") == 0) return 2;
    if (strcmp(name, "next") == 0) return 4;
    if (strcmp(name, "previous") == 0) return 5;
    return -1;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 2;
        NSInteger command = commandForName(argv[1]);
        if (command < 0) return 2;

        void *framework = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW | RTLD_GLOBAL);
        if (!framework) return 1;
        MRMediaRemoteSendCommandFunction send = (MRMediaRemoteSendCommandFunction)dlsym(framework, "MRMediaRemoteSendCommand");
        if (!send) {
            dlclose(framework);
            return 1;
        }
        bool accepted = send(command, nil);
        dlclose(framework);
        return accepted ? 0 : 1;
    }
}
