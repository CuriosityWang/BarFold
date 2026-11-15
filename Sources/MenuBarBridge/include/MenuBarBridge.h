#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// All methods must be called on the main thread. Assertions belong to this process.
@interface BFMenuBarSession : NSObject
@property(class, nonatomic, readonly) BOOL supported;
- (void)applyAllowedBundles:(NSArray<NSString *> *)bundles completion:(void (^)(NSError * _Nullable))completion;
- (void)restore;
@end
NS_ASSUME_NONNULL_END
