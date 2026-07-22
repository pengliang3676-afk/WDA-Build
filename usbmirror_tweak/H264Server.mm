#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <unistd.h>
#include <atomic>
#include "Screen.h"

static const int ZXH264Port = 6002;
static const int ZXWidth = 360;
static const int ZXHeight = 640;
static const int ZXFps = 12;
static const int ZXBitrate = 650000;

typedef struct {
    int socketHandle;
    std::atomic_bool connected;
} ZXEncoderContext;

static BOOL ZXH264WriteAll(int socketHandle, const void *buffer, size_t length)
{
    const uint8_t *bytes = (const uint8_t *)buffer;
    size_t offset = 0;
    while (offset < length) {
        ssize_t written = send(socketHandle, bytes + offset, length - offset, MSG_NOSIGNAL);
        if (written <= 0) return NO;
        offset += (size_t)written;
    }
    return YES;
}

static void ZXAppendStartCode(NSMutableData *data)
{
    const uint8_t startCode[] = {0, 0, 0, 1};
    [data appendBytes:startCode length:sizeof(startCode)];
}

static void ZXEncoderCallback(void *outputCallbackRefCon,
                              void *sourceFrameRefCon,
                              OSStatus status,
                              VTEncodeInfoFlags infoFlags,
                              CMSampleBufferRef sampleBuffer)
{
    (void)sourceFrameRefCon;
    (void)infoFlags;
    ZXEncoderContext *context = (ZXEncoderContext *)outputCallbackRefCon;
    if (!context || !context->connected.load() || status != noErr || !sampleBuffer || !CMSampleBufferDataIsReady(sampleBuffer)) return;

    NSMutableData *packet = [NSMutableData data];
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    BOOL keyFrame = YES;
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachment = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        keyFrame = !CFDictionaryContainsKey(attachment, kCMSampleAttachmentKey_NotSync);
    }

    if (keyFrame) {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        for (size_t index = 0; index < 2; index++) {
            const uint8_t *parameter = NULL;
            size_t parameterSize = 0;
            size_t count = 0;
            int headerLength = 0;
            if (CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, index, &parameter, &parameterSize, &count, &headerLength) == noErr) {
                ZXAppendStartCode(packet);
                [packet appendBytes:parameter length:parameterSize];
            }
        }
    }

    CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t totalLength = 0;
    char *dataPointer = NULL;
    if (!block || CMBlockBufferGetDataPointer(block, 0, NULL, &totalLength, &dataPointer) != kCMBlockBufferNoErr) return;
    size_t offset = 0;
    while (offset + 4 <= totalLength) {
        uint32_t nalLength = 0;
        memcpy(&nalLength, dataPointer + offset, 4);
        nalLength = CFSwapInt32BigToHost(nalLength);
        offset += 4;
        if (nalLength == 0 || offset + nalLength > totalLength) break;
        ZXAppendStartCode(packet);
        [packet appendBytes:dataPointer + offset length:nalLength];
        offset += nalLength;
    }

    if (packet.length == 0) return;
    uint32_t networkLength = htonl((uint32_t)packet.length);
    if (!ZXH264WriteAll(context->socketHandle, &networkLength, sizeof(networkLength)) ||
        !ZXH264WriteAll(context->socketHandle, packet.bytes, packet.length)) {
        context->connected.store(false);
    }
}

static CVPixelBufferRef ZXCreatePixelBuffer(CGImageRef image)
{
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    CVPixelBufferRef pixelBuffer = NULL;
    CVReturn result = CVPixelBufferCreate(kCFAllocatorDefault, ZXWidth, ZXHeight,
                                           kCVPixelFormatType_32BGRA,
                                           (__bridge CFDictionaryRef)attributes,
                                           &pixelBuffer);
    if (result != kCVReturnSuccess || !pixelBuffer) return NULL;
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(baseAddress, ZXWidth, ZXHeight, 8, bytesPerRow,
                                                  colorSpace,
                                                  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGColorSpaceRelease(colorSpace);
    if (!context) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextTranslateCTM(context, 0, ZXHeight);
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, ZXWidth, ZXHeight), image);
    CGContextRelease(context);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}

static VTCompressionSessionRef ZXCreateEncoder(ZXEncoderContext *context)
{
    VTCompressionSessionRef encoder = NULL;
    OSStatus status = VTCompressionSessionCreate(kCFAllocatorDefault, ZXWidth, ZXHeight,
                                                  kCMVideoCodecType_H264, NULL, NULL, NULL,
                                                  ZXEncoderCallback, context, &encoder);
    if (status != noErr || !encoder) return NULL;
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    int fps = ZXFps;
    int bitrate = ZXBitrate;
    int keyInterval = ZXFps * 2;
    CFNumberRef fpsNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
    CFNumberRef bitrateNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &bitrate);
    CFNumberRef keyNumber = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &keyInterval);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_ExpectedFrameRate, fpsNumber);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_AverageBitRate, bitrateNumber);
    VTSessionSetProperty(encoder, kVTCompressionPropertyKey_MaxKeyFrameInterval, keyNumber);
    CFRelease(fpsNumber);
    CFRelease(bitrateNumber);
    CFRelease(keyNumber);
    VTCompressionSessionPrepareToEncodeFrames(encoder);
    return encoder;
}

static void ZXHandleH264Client(int client)
{
    @autoreleasepool {
        int noSignal = 1;
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        struct timeval timeout = {3, 0};
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        const uint8_t hello[12] = {'Z','X','H','2', 0,1, 0,0, 0,0,0,0};
        uint8_t header[12];
        memcpy(header, hello, sizeof(header));
        uint16_t width = htons(ZXWidth);
        uint16_t height = htons(ZXHeight);
        uint16_t fps = htons(ZXFps);
        memcpy(header + 4, &width, 2);
        memcpy(header + 6, &height, 2);
        memcpy(header + 8, &fps, 2);
        if (!ZXH264WriteAll(client, header, sizeof(header))) { close(client); return; }

        ZXEncoderContext context;
        context.socketHandle = client;
        context.connected.store(true);
        VTCompressionSessionRef encoder = ZXCreateEncoder(&context);
        if (!encoder) { close(client); return; }
        int64_t frameIndex = 0;
        while (context.connected.load()) {
            @autoreleasepool {
                CFTimeInterval start = CFAbsoluteTimeGetCurrent();
                CGImageRef image = [Screen createScreenShotCGImageRef];
                if (image) {
                    CVPixelBufferRef pixelBuffer = ZXCreatePixelBuffer(image);
                    CGImageRelease(image);
                    if (pixelBuffer) {
                        CMTime timestamp = CMTimeMake(frameIndex++, ZXFps);
                        VTCompressionSessionEncodeFrame(encoder, pixelBuffer, timestamp,
                                                        CMTimeMake(1, ZXFps), NULL, NULL, NULL);
                        CVPixelBufferRelease(pixelBuffer);
                    }
                }
                CFTimeInterval elapsed = CFAbsoluteTimeGetCurrent() - start;
                CFTimeInterval delay = (1.0 / ZXFps) - elapsed;
                if (delay > 0) usleep((useconds_t)(delay * 1000000.0));
            }
        }
        VTCompressionSessionCompleteFrames(encoder, kCMTimeInvalid);
        VTCompressionSessionInvalidate(encoder);
        CFRelease(encoder);
        shutdown(client, SHUT_RDWR);
        close(client);
    }
}

static void ZXRunH264Server(void)
{
    int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return;
    int enabled = 1;
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    struct sockaddr_in address = {0};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(ZXH264Port);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(server, 4) != 0) {
        close(server);
        return;
    }
    while (true) {
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ ZXHandleH264Client(client); });
    }
}

void ZXStartH264Server(void)
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ ZXRunH264Server(); });
}
