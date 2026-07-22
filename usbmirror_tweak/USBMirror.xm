#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include "Touch.h"
#include "Screen.h"

extern void ZXStartH264Server(void);

static const int ZXMirrorPort = 6001;

static BOOL ZXWriteAll(int socketHandle, const void *buffer, size_t length)
{
    const uint8_t *bytes = (const uint8_t *)buffer;
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = send(socketHandle, bytes + offset, length - offset, 0);
        if (written <= 0) return NO;
        offset += (size_t)written;
    }
    return YES;
}

static void ZXSendFrame(int client, const char *request)
{
    NSString *raw = request ? [NSString stringWithUTF8String:request] : @"35;;540";
    NSArray *parts = [raw componentsSeparatedByString:@";;"];
    CGFloat quality = parts.count > 0 ? [parts[0] doubleValue] / 100.0 : 0.35;
    CGFloat width = parts.count > 1 ? [parts[1] doubleValue] : 540.0;
    NSData *jpeg = [Screen screenFrameJPEGWithQuality:quality maxWidth:width];
    if (!jpeg.length) {
        const char *error = "-1;;Unable to capture screen\r\n";
        ZXWriteAll(client, error, strlen(error));
        return;
    }
    NSString *header = [NSString stringWithFormat:@"0;;%lu\r\n", (unsigned long)jpeg.length];
    ZXWriteAll(client, header.UTF8String, strlen(header.UTF8String));
    ZXWriteAll(client, jpeg.bytes, jpeg.length);
}

static void ZXHandleClient(int client)
{
    @autoreleasepool {
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        char buffer[2048] = {0};
        ssize_t length = recv(client, buffer, sizeof(buffer) - 1, 0);
        if (length > 2) {
            buffer[length] = 0;
            if (buffer[0] == '1' && buffer[1] == '0') {
                performTouchFromRawData((UInt8 *)(buffer + 2));
            } else if (buffer[0] == '3' && buffer[1] == '0') {
                ZXSendFrame(client, buffer + 2);
            }
        }
        close(client);
    }
}

static void ZXRunMirrorServer(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int enabled = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(ZXMirrorPort);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 32) != 0) {
        close(server);
        return;
    }
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ ZXHandleClient(client); });
    }
}

%ctor {
    @autoreleasepool {
        CGSize size = UIScreen.mainScreen.bounds.size;
        [Screen setScreenSize:size.width height:size.height];
        initTouchGetScreenSize();
        initSenderId();
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ ZXRunMirrorServer(); });
        ZXStartH264Server();
    }
}
