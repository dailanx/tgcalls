#ifdef WEBRTC_IOS
#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>

// Confined to the camera's serial frame queue. IDs match CallVideoEffects in AccountContext.
@interface CallVideoEffectsProcessor : NSObject
- (void)setFilter:(int32_t)filter intensity:(float)intensity mask:(int32_t)mask;
- (CVPixelBufferRef)copyPixelBuffer:(CVPixelBufferRef)buffer rotation:(int)rotation CF_RETURNS_RETAINED;
@end
#endif
