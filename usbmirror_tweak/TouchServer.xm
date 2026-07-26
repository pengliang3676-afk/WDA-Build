#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <string.h>
#include <unistd.h>
#include "Screen.h"
#include "Touch.h"

static const int ZXTouchPort = 6000;

static void ZXPressHomeButton(void)
{
    static IOHIDEventSystemClientRef client = NULL;
    if (!client) client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    IOHIDEventRef down = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C, 0x40, true, 0);
    IOHIDEventRef up = IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), 0x0C, 0x40, false, 0);
    if (down) {
        IOHIDEventSystemClientDispatchEvent(client, down);
        CFRelease(down);
    }
    usleep(50000);
    if (up) {
        IOHIDEventSystemClientDispatchEvent(client, up);
        CFRelease(up);
    }
}

static void ZXHandleTouchClient(int client)
{
    @autoreleasepool {
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        char buffer[2048];
        while (true) {
            ssize_t length = recv(client, buffer, sizeof(buffer) - 1, 0);
            if (length <= 0) break;
            buffer[length] = 0;
            char *line = buffer;
            char *end = NULL;
            while (line < buffer + length) {
                end = strstr(line, "\r\n");
                if (end) *end = 0;
                if (line[0] == '1' && line[1] == '0' && line[2] != 0) {
                    performTouchFromRawData((UInt8 *)(line + 2));
                }
                else if (line[0] == '1' && line[1] == '1' && line[2] != 0) {
                    NSString *encoded = [NSString stringWithUTF8String:(line + 2)];
                    NSData *data = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
                    NSString *text = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
                    if (text) {
                        [[NSDistributedNotificationCenter defaultCenter]
                            postNotificationName:@"com.jibeib.usbmirror.keyboard"
                            object:nil
                            userInfo:@{@"action": @"insert", @"text": text}
                            deliverImmediately:YES];
                    }
                }
                else if (line[0] == '1' && line[1] == '2') {
                    NSInteger count = MAX(1, atoi(line + 2));
                    [[NSDistributedNotificationCenter defaultCenter]
                        postNotificationName:@"com.jibeib.usbmirror.keyboard"
                        object:nil
                        userInfo:@{@"action": @"delete", @"count": @(count)}
                        deliverImmediately:YES];
                }
                else if (line[0] == '1' && line[1] == '3') {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        ZXPressHomeButton();
                    });
                }
                if (!end) break;
                line = end + 2;
            }
        }
        shutdown(client, SHUT_RDWR);
        close(client);
    }
}

static void ZXRunTouchServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int enabled = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(ZXTouchPort);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 16) != 0) {
        close(server);
        return;
    }
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{
            ZXHandleTouchClient(client);
        });
    }
}

%hook SBHomeScreenViewController

- (void)viewDidLoad
{
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Match ZXTouch's proven lifecycle: do not touch IOHID from %ctor.
        // Sender-ID discovery must be registered on SpringBoard's main run loop.
        // A GCD worker thread has no continuously running CFRunLoop, so after a
        // reboot the callback never receives a real digitizer event and every
        // injected touch is silently discarded while senderID remains zero.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            @autoreleasepool {
                CGRect bounds = UIScreen.mainScreen.nativeBounds;
                CGFloat width = MIN(bounds.size.width, bounds.size.height);
                CGFloat height = MAX(bounds.size.width, bounds.size.height);
                [Screen setScreenSize:width height:height];
                initSenderId();
                initTouchGetScreenSize();
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    ZXRunTouchServer();
                });
            }
        });
    });
}

%end

%ctor
{
    %init;
}
