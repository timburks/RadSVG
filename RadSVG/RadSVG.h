//
// RadSVG.h
//
// Created by Tim Burks on 3/4/11.
// Copyright 2011 Radtastical Inc. All rights reserved.
//
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

typedef enum {    
    RadSVGVerticalAlignmentTop,
    RadSVGVerticalAlignmentCenter,
    RadSVGVerticalAlignmentBottom
} RadSVGVerticalAlignment;

typedef enum {
    RadSVGHorizontalAlignmentLeft,
    RadSVGHorizontalAlignmentCenter,
    RadSVGHorizontalAlignmentRight
} RadSVGHorizontalAlignment;

@interface RadSVGObject : NSObject
@property (nonatomic, readonly) int width;
@property (nonatomic, readonly) int height;
@property (nonatomic, readonly) CGRect viewBox;

+ (RadSVGObject *) SVGObjectWithFile:(NSString *) filename;
+ (RadSVGObject *) SVGObjectWithString:(NSString *) string;
+ (RadSVGObject *) SVGObjectWithData:(NSData *) data;
+ (RadSVGObject *) SVGObjectWithName:(NSString *) name;

- (void) drawInContext:(CGContextRef) context
              withRect:(CGRect) rect
     verticalAlignment:(RadSVGVerticalAlignment) valign
   horizontalAlignment:(RadSVGHorizontalAlignment) halign
        colorOverrides:(NSDictionary *) colorOverrides;

#if TARGET_OS_IPHONE
- (UIImage *) imageWithSize:(CGSize) size
             colorOverrides:(NSDictionary *) colorOverrides
                      scale:(CGFloat) scale;

- (NSData *) pngImageDataWithSize:(CGSize) size
                   colorOverrides:(NSDictionary *) colorOverrides
                  backgroundColor:(CGColorRef) backgroundColor;

- (NSData *) pngImageDataWithSize:(CGSize) size;
#endif

@end

#if TARGET_OS_IPHONE

@interface RadSVGView : UIView
@property (nonatomic, strong) RadSVGObject *svgObject;
@property (nonatomic, assign) RadSVGVerticalAlignment verticalAlignment;
@property (nonatomic, assign) RadSVGHorizontalAlignment horizontalAlignment;
@property (nonatomic, strong) NSDictionary *colorOverrides;
@end

#endif

