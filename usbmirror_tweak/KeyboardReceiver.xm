#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface USBMirrorKeyboardReceiver : NSObject
@end

static void USBMirrorKeyboardNotification(
    CFNotificationCenterRef center,
    void *observer,
    CFStringRef name,
    const void *object,
    CFDictionaryRef userInfo)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = UIApplication.sharedApplication;
        if (CFStringCompare(name, CFSTR("com.jibeib.usbmirror.keyboard.paste"), 0) == kCFCompareEqualTo) {
            BOOL pasted = [application sendAction:@selector(paste:) to:nil from:nil forEvent:nil];
            if (!pasted) {
                NSString *text = [UIPasteboard generalPasteboard].string ?: @"";
                if (text.length) {
                    [application sendAction:@selector(insertText:) to:nil from:text forEvent:nil];
                }
            }
        }
        else if (CFStringCompare(name, CFSTR("com.jibeib.usbmirror.keyboard.delete"), 0) == kCFCompareEqualTo) {
            [application sendAction:@selector(deleteBackward) to:nil from:nil forEvent:nil];
        }
    });
}

@implementation USBMirrorKeyboardReceiver

- (instancetype)init
{
    self = [super init];
    if (self) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            USBMirrorKeyboardNotification,
            CFSTR("com.jibeib.usbmirror.keyboard.paste"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            (__bridge const void *)self,
            USBMirrorKeyboardNotification,
            CFSTR("com.jibeib.usbmirror.keyboard.delete"),
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    return self;
}

- (void)dealloc
{
    CFNotificationCenterRemoveObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge const void *)self,
        NULL,
        NULL);
}

@end

%ctor
{
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            static USBMirrorKeyboardReceiver *receiver;
            receiver = [USBMirrorKeyboardReceiver new];
        }
    }
}
