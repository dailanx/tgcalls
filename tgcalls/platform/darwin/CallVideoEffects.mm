#ifdef WEBRTC_IOS
#import "CallVideoEffects.h"
#import <CoreImage/CoreImage.h>
#include <cmath>
#include <initializer_list>

@implementation CallVideoEffectsProcessor {
    int32_t _filter;
    float _intensity;
    int32_t _mask;
    CIContext *_context;
    CIDetector *_detector;
    CIImage *_maskImage;
    CVPixelBufferPoolRef _pool;
    size_t _width;
    size_t _height;
    OSType _format;
}

- (void)dealloc {
    if (_pool) CVPixelBufferPoolRelease(_pool);
}

- (void)setFilter:(int32_t)filter intensity:(float)intensity mask:(int32_t)mask {
    _filter = filter >= 0 && filter <= 4 ? filter : 0;
    _intensity = std::isfinite(intensity) ? fmaxf(0.0f, fminf(1.0f, intensity)) : 1.0f;
    mask = mask >= 0 && mask <= 2 ? mask : 0;
    if (_mask != mask) {
        _mask = mask;
        _maskImage = nil;
    }
    if (_mask == 0) _detector = nil;
    if (_filter == 0 && _mask == 0) {
        _context = nil;
        if (_pool) CVPixelBufferPoolRelease(_pool);
        _pool = nil;
    }
}

- (CIImage *)maskImage {
    if (_maskImage) return _maskImage;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef drawing = CGBitmapContextCreate(NULL, 320, 160, 8, 0, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!drawing) return nil;
    if (_mask == 1) {
        CGContextSetRGBFillColor(drawing, 0.04, 0.05, 0.09, 0.96);
        CGContextFillEllipseInRect(drawing, CGRectMake(52, 38, 96, 64));
        CGContextFillEllipseInRect(drawing, CGRectMake(172, 38, 96, 64));
        CGContextFillRect(drawing, CGRectMake(140, 68, 40, 10));
        CGContextFillRect(drawing, CGRectMake(30, 76, 30, 8));
        CGContextFillRect(drawing, CGRectMake(260, 76, 30, 8));
        CGContextSetRGBStrokeColor(drawing, 0.5, 0.8, 1.0, 0.8);
        CGContextSetLineWidth(drawing, 5);
        for (CGFloat x : {80.0, 200.0}) {
            CGContextMoveToPoint(drawing, x, 80);
            CGContextAddLineToPoint(drawing, x + 24, 92);
            CGContextStrokePath(drawing);
        }
    } else {
        CGContextSetRGBFillColor(drawing, 1.0, 0.12, 0.35, 1.0);
        for (CGFloat x : {100.0, 220.0}) {
            CGContextMoveToPoint(drawing, x, 32);
            CGContextAddCurveToPoint(drawing, x - 88, 90, x - 26, 130, x, 92);
            CGContextAddCurveToPoint(drawing, x + 26, 130, x + 88, 90, x, 32);
            CGContextFillPath(drawing);
        }
    }
    CGImageRef image = CGBitmapContextCreateImage(drawing);
    if (image) {
        _maskImage = [CIImage imageWithCGImage:image];
        CGImageRelease(image);
    }
    CGContextRelease(drawing);
    return _maskImage;
}

- (CVPixelBufferRef)copyPixelBuffer:(CVPixelBufferRef)buffer rotation:(int)rotation {
    // Disabled effects retain the original frame; no GPU work or detection.
    if ((_filter == 0 || _intensity == 0.0f) && _mask == 0) return CVPixelBufferRetain(buffer);
    OSType format = CVPixelBufferGetPixelFormatType(buffer);
    if (format != kCVPixelFormatType_420YpCbCr8BiPlanarFullRange &&
        format != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange &&
        format != kCVPixelFormatType_32BGRA && format != kCVPixelFormatType_32ARGB) return CVPixelBufferRetain(buffer);
    // External/simulator camera frames can be RGB; the call encoder accepts NV12.
    if (format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB) format = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange;
    if (!_context) _context = [CIContext contextWithOptions:@{kCIContextCacheIntermediates: @NO}];
    size_t width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer);
    if (!_pool || _width != width || _height != height || _format != format) {
        if (_pool) CVPixelBufferPoolRelease(_pool);
        _pool = nil;
        _width = width; _height = height; _format = format;
        NSDictionary *attributes = @{
            (id)kCVPixelBufferWidthKey: @(width), (id)kCVPixelBufferHeightKey: @(height),
            (id)kCVPixelBufferPixelFormatTypeKey: @(format),
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };
        CVPixelBufferPoolCreate(NULL, NULL, (__bridge CFDictionaryRef)attributes, &_pool);
    }
    CVPixelBufferRef output = NULL;
    NSDictionary *limits = @{(id)kCVPixelBufferPoolAllocationThresholdKey: @6};
    if (!_pool || CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(NULL, _pool,
        (__bridge CFDictionaryRef)limits, &output) != kCVReturnSuccess) return CVPixelBufferRetain(buffer);

    @autoreleasepool {
        // Work upright for face landmarks, then restore the original pixel geometry.
        int orientation = rotation == 90 ? 6 : rotation == 180 ? 3 : rotation == 270 ? 8 : 1;
        int inverseOrientation = rotation == 90 ? 8 : rotation == 270 ? 6 : orientation;
        CIImage *original = [[CIImage imageWithCVPixelBuffer:buffer] imageByApplyingOrientation:orientation];
        CIImage *image = original;
        if (_filter != 0 && _intensity > 0.0f) {
            switch (_filter) {
                case 1: image = [image imageByApplyingFilter:@"CIPhotoEffectNoir"]; break;
                case 2: image = [image imageByApplyingFilter:@"CISepiaTone" withInputParameters:@{kCIInputIntensityKey: @0.65}]; break;
                case 3: image = [image imageByApplyingFilter:@"CIPhotoEffectProcess"]; break;
                case 4: image = [image imageByApplyingFilter:@"CIPhotoEffectInstant"]; break;
            }
            image = [original imageByApplyingFilter:@"CIDissolveTransition" withInputParameters:@{
                kCIInputTargetImageKey: image, kCIInputTimeKey: @(_intensity)
            }];
        }
        if (_mask != 0) {
            if (!_detector) _detector = [CIDetector detectorOfType:CIDetectorTypeFace context:_context options:@{
                CIDetectorAccuracy: CIDetectorAccuracyLow, CIDetectorTracking: @YES
            }];
            // Bound detector cost without retaining landmarks after a face disappears.
            CGFloat scale = fmin(1.0, 480.0 / fmax(original.extent.size.width, original.extent.size.height));
            CIImage *small = [original imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
            for (CIFaceFeature *face in [_detector featuresInImage:small]) {
                if (!face.hasLeftEyePosition || !face.hasRightEyePosition) continue;
                CGPoint a = CGPointMake(face.leftEyePosition.x / scale, face.leftEyePosition.y / scale);
                CGPoint b = CGPointMake(face.rightEyePosition.x / scale, face.rightEyePosition.y / scale);
                if (a.x > b.x) { CGPoint temporary = a; a = b; b = temporary; }
                CGFloat dx = b.x - a.x, dy = b.y - a.y;
                CGFloat distance = hypot(dx, dy);
                if (distance < 8.0) continue;
                CGFloat s = distance / 120.0;
                CGFloat c = dx / distance, sine = dy / distance;
                CGAffineTransform transform = CGAffineTransformMake(s * c, s * sine, -s * sine, s * c,
                    a.x - s * c * 100.0 + s * sine * 70.0,
                    a.y - s * sine * 100.0 - s * c * 70.0);
                CIImage *overlay = [[self maskImage] imageByApplyingTransform:transform];
                if (overlay) image = [overlay imageByCompositingOverImage:image];
            }
        }
        image = [[image imageByCroppingToRect:original.extent] imageByApplyingOrientation:inverseOrientation];
        CVBufferPropagateAttachments(buffer, output);
        [_context render:image toCVPixelBuffer:output];
    }
    return output;
}
@end
#endif
