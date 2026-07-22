#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <string.h>
#include <unistd.h>
#include "Screen.h"
#include "Touch.h"

static const int ZXTouchPort = 6000;

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
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                       dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                CGRect bounds = UIScreen.mainScreen.nativeBounds;
                CGFloat width = MIN(bounds.size.width, bounds.size.height);
                CGFloat height = MAX(bounds.size.width, bounds.size.height);
                [Screen setScreenSize:width height:height];
                initSenderId();
                initTouchGetScreenSize();
                ZXRunTouchServer();
            }
        });
    });
}

%end

%ctor
{
    %init;
}
