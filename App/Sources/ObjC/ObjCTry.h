#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Fängt eine Objective-C-Ausnahme (NSException) und macht daraus einen Fehler, den Swift behandeln kann.
/// Swift selbst kann NSException nicht fangen: Wirft etwa AVFAudio beim Setzen eines Taps („format mismatch“),
/// beendet das sonst die App. In Swift: `try ObjCTry.run { ... }`.
/// Im Block sollen nur die Aufrufe stehen, die werfen können.
@interface ObjCTry : NSObject

+ (BOOL)run:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable __autoreleasing * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
