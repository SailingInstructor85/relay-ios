#import "ObjCTry.h"

@implementation ObjCTry

+ (BOOL)run:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable __autoreleasing * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            NSString *reason = exception.reason ?: exception.name;
            *error = [NSError errorWithDomain:@"dev.relay.objc-exception"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: reason, @"name": exception.name}];
        }
        return NO;
    }
}

@end
