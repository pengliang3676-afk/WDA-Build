#import <Foundation/Foundation.h>
#import <Foundation/NSDistributedNotificationCenter.h>
#import <UIKit/UIKit.h>

@interface USBMirrorKeyboardReceiver : NSObject
@end

@implementation USBMirrorKeyboardReceiver

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSDistributedNotificationCenter defaultCenter]
            addObserver:self
            selector:@selector(receiveKeyboardCommand:)
            name:@"com.jibeib.usbmirror.keyboard"
            object:nil];
    }
    return self;
}

- (void)receiveKeyboardCommand:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    NSString *action = info[@"action"];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication *application = UIApplication.sharedApplication;
        if ([action isEqualToString:@"insert"]) {
            NSString *text = info[@"text"] ?: @"";
            [application sendAction:@selector(insertText:) to:nil from:text forEvent:nil];
        }
        else if ([action isEqualToString:@"delete"]) {
            NSInteger count = MAX(1, [info[@"count"] integerValue]);
            for (NSInteger i = 0; i < count; i++) {
                [application sendAction:@selector(deleteBackward) to:nil from:nil forEvent:nil];
            }
        }
    });
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
