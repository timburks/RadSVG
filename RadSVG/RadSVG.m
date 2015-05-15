//
// RadSVG.m
//
// Created by Tim Burks on 3/5/11.
// Copyright 2011 Radtastical Inc. All rights reserved.
//
// Follows documentation at http://www.w3.org/TR/SVGTiny12/
//
#import "RadSVG.h"
#include <libxml/xmlreader.h>

#pragma mark - Internal class declarations

@interface RadSVGDrawable : NSObject
{
    CGMutablePathRef _cgpath;
    CGColorRef _fillColor;
    CGColorRef _strokeColor;
}
@property (nonatomic, assign) CGFloat strokeWidth;
@property (nonatomic, strong) NSMutableDictionary *attributes;
- (CGRect) bounds;
@end

@interface RadSVGGroup : NSObject
@property (nonatomic, assign) CGAffineTransform transform;
@property (nonatomic, strong) NSMutableArray *children;
@property (nonatomic, strong) NSMutableDictionary *attributes;
- (CGRect) bounds;
@end

@interface RadSVGObject () {
@public
    int _width;
    int _height;
}
@property (nonatomic, strong) NSMutableArray *children;
@end

@interface RadSVGReader : NSObject {
    NSMutableArray *svgStack;
}

- (id) readSVGFromFile:(NSString *) filename;
- (id) readSVGFromString:(NSString *) string;
- (id) readSVGFromData:(NSData *) data;

@end

#pragma mark - Static helper functions for drawing SVGs

static CGColorRef CGColorForName(NSString *name);

static int CGColorGrayValue(CGColorRef color);

static CGFloat CGColorAlphaValue(CGColorRef color);

static CGFloat parsePathNumber(const char **cp);

static void parsePathText(CGMutablePathRef cgpath,
                          CGAffineTransform *transform,
                          NSString *pathText);

static void parsePolyText(CGMutablePathRef cgpath,
                          CGAffineTransform *transform,
                          NSString *polygonText,
                          BOOL closePath);

static CGColorRef CGColorForName(NSString *name) {
    @autoreleasepool {
        CGFloat r, g, b, a = 1.0;
        
        // NSLog(@"color name: %@", name);
        if ([name characterAtIndex:0] == '#') {
            if ([name length] == 7) {
                NSString *colorString = [NSString stringWithFormat:@"0x%@",
                                         [name substringWithRange:NSMakeRange(1,6)]];
                int colorValue = strtod([colorString cStringUsingEncoding:NSUTF8StringEncoding], NULL);
                r = ((colorValue & 0xFF0000) >> 16)/255.0;
                g = ((colorValue & 0x00FF00) >>  8)/255.0;
                b = ((colorValue & 0x0000FF) >>  0)/255.0;
            } else if ([name length] == 4) {
                NSString *colorString = [NSString stringWithFormat:@"0x%@",
                                         [name substringWithRange:NSMakeRange(1,3)]];
                int colorValue = strtod([colorString cStringUsingEncoding:NSUTF8StringEncoding], NULL);
                r = ((colorValue & 0xF00) >> 8)/15.0;
                g = ((colorValue & 0x0F0) >> 4)/15.0;
                b = ((colorValue & 0x00F) >> 0)/15.0;
            } else {
                r = g = b = 0;
            }
        } else if ([name isEqualToString:@"black"]) {
            r = g = b = 0;
        } else if ([name isEqualToString:@"silver"]) {
            r = g = b = 0.75;
        } else if ([name isEqualToString:@"gray"]) {
            r = g = b = 0.5;
        } else if ([name isEqualToString:@"white"]) {
            r = g = b = 1;            
        } else if ([name isEqualToString:@"maroon"]) {
            r = 0.5; g = 0; b = 0;
        } else if ([name isEqualToString:@"red"]) {
            r = 1; g = 0; b = 0;
        } else if ([name isEqualToString:@"purple"]) {
            r = 0.5; g = 0; b = 0.5;
        } else if ([name isEqualToString:@"fuchsia"]) {
            r = 1; g = 0; b = 1;
        } else if ([name isEqualToString:@"green"]) {
            r = 0; g = 0.5; b = 0;
        } else if ([name isEqualToString:@"lime"]) {
            r = 0; g = 1; b = 0;
        } else if ([name isEqualToString:@"olive"]) {
            r = 0.5; g = 0.5; b = 0;
        } else if ([name isEqualToString:@"yellow"]) {
            r = 1; g = 1; b = 0;
        } else if ([name isEqualToString:@"navy"]) {
            r = 0; g = 0; b = 0.5;
        } else if ([name isEqualToString:@"blue"]) {
            r = 0; g = 0; b = 1;
        } else if ([name isEqualToString:@"blue"]) {
            r = 0; g = 0.5; b = 0.5;
        } else if ([name isEqualToString:@"blue"]) {
            r = 0; g = 1; b = 1;
        } else if ([name isEqualToString:@"none"]) {
            r = 0; g = 0; b = 0; a = 0;
        } else if ([[name substringToIndex:4] isEqualToString:@"rgb("] &&
                   ([name characterAtIndex:([name length] - 1)] == ')')) {
            NSString *numbers = [name substringWithRange:NSMakeRange(4, [name length] - 5)];
            NSArray *parts = [numbers componentsSeparatedByString:@","];
            r = [[parts objectAtIndex:0] floatValue] / 100.0;
            g = [[parts objectAtIndex:1] floatValue] / 100.0;
            b = [[parts objectAtIndex:2] floatValue] / 100.0;
        } else {
            r = g = b = 0.5;
            NSLog(@"UNKNOWN COLOR NAME: %@", name);
        }
        CGFloat components[4];
        components[0] = r;
        components[1] = g;
        components[2] = b;
        components[3] = a;
        static CGColorSpaceRef colorSpace = NULL;
        if (!colorSpace) {
            colorSpace = CGColorSpaceCreateDeviceRGB();
        }
        return CGColorCreate(colorSpace, components);
    }
}

static int CGColorGrayValue(CGColorRef color) {
    const CGFloat *c = CGColorGetComponents(color);
    if ((c[0] == c[1]) && (c[1] == c[2]) && (c[3] == 1.0)) {
        return (int) (100 * c[0]);
    } else {
        return -1;
    }
}

static CGFloat CGColorAlphaValue(CGColorRef color) {
    const CGFloat *c = CGColorGetComponents(color);
    return c[3];
}

static char *trim(char *s) {
    while (strlen(s) && isblank(*s)) {
        s++;
    }
    return strdup(s);
}

static CGAffineTransform parseTransform(NSString *transformText)
{
    CGAffineTransform fullTransform = CGAffineTransformIdentity;
    
    char *toparse = strdup([transformText cStringUsingEncoding:NSUTF8StringEncoding]);
    char *remainder = (char *) malloc(strlen(toparse+1));
    
    while (strlen(toparse)) {
        remainder[0] = 0;
        float a, b, c, d, tx, ty;
        if (sscanf(toparse, "matrix(%f %f %f %f %f %f)%s", &a, &b, &c, &d, &tx, &ty, remainder)) {
            CGAffineTransform transform = CGAffineTransformMake(a,b,c,d,tx,ty);
            fullTransform = CGAffineTransformConcat(transform, fullTransform);
            free(toparse);
            toparse = trim(remainder);
        } else if (sscanf(toparse, "translate(%f %f)%s", &tx, &ty, remainder)) {
            CGAffineTransform transform = CGAffineTransformMakeTranslation(tx, ty);
            fullTransform = CGAffineTransformConcat(transform, fullTransform);
            free(toparse);
            toparse = trim(remainder);
        } else if (sscanf(toparse, "rotate(%f)%s", &a, remainder)) {
            a = a / 360.0 * 2 * M_PI;
            CGAffineTransform transform = CGAffineTransformMakeRotation(a);
            fullTransform = CGAffineTransformConcat(transform, fullTransform);
            free(toparse);
            toparse = trim(remainder);
        } else {
            NSLog(@"failed to parse %s", toparse);
            break;
        }
    }
    free(remainder);
    free(toparse);
    
    return fullTransform;
}

#pragma mark - Drawable primitives (path, polygon, rect, circle, line, polyline, ellipse)

@implementation RadSVGDrawable

- (id) init {
    if ((self = [super init])) {
        self.attributes = [[NSMutableDictionary alloc] init];
        _cgpath = CGPathCreateMutable();
        _fillColor = NULL;
        _strokeColor = NULL;
    }
    return self;
}

- (void) dealloc {
    CGPathRelease(_cgpath);
    CGColorRelease(_fillColor);
    CGColorRelease(_strokeColor);
}

- (void) process {
    CGAffineTransform transform = CGAffineTransformIdentity;
    id transformText = [_attributes objectForKey:@"transform"];
    if (transformText) {
        transform = parseTransform(transformText);
    }
    
    NSString *typeName = [_attributes objectForKey:@"type"];
    if ([typeName isEqualToString:@"path"]) {
        id pathText = [_attributes objectForKey:@"d"];
        if (pathText) {
            parsePathText(_cgpath, &transform, pathText);
        }
    } else if ([typeName isEqualToString:@"polygon"]) {
        NSString *points = [_attributes objectForKey:@"points"];
        if (points) {
            parsePolyText(_cgpath, &transform, points, YES);
        }
    } else if ([typeName isEqualToString:@"rect"]) {
        CGRect rect;
        rect.origin.x = [[_attributes objectForKey:@"x"] floatValue];
        rect.origin.y = [[_attributes objectForKey:@"y"] floatValue];
        rect.size.width = [[_attributes objectForKey:@"width"] floatValue];
        rect.size.height = [[_attributes objectForKey:@"height"] floatValue];
        CGFloat cornerRadius = [[_attributes objectForKey:@"rx"] floatValue];
        if (cornerRadius == 0.0) {
            CGPathAddRect(_cgpath, &transform, rect);
        } else {
            CGPathAddRoundedRect(_cgpath, &transform, rect, cornerRadius, cornerRadius);
        }
    } else if ([typeName isEqualToString:@"circle"]) {
        CGFloat cx = [[_attributes objectForKey:@"cx"] floatValue];
        CGFloat cy = [[_attributes objectForKey:@"cy"] floatValue];
        CGFloat r  = [[_attributes objectForKey:@"r"] floatValue];
        CGRect rect;
        rect.origin.x = cx-r;
        rect.origin.y = cy-r;
        rect.size.width = 2*r;
        rect.size.height = 2*r;
        CGPathAddEllipseInRect(_cgpath, &transform, rect);
    } else if ([typeName isEqualToString:@"line"]) {
        CGFloat x1 = [[_attributes objectForKey:@"x1"] floatValue];
        CGFloat y1 = [[_attributes objectForKey:@"y1"] floatValue];
        CGFloat x2 = [[_attributes objectForKey:@"x2"] floatValue];
        CGFloat y2 = [[_attributes objectForKey:@"y2"] floatValue];
        CGPathMoveToPoint(_cgpath, &transform, x1, y1);
        CGPathAddLineToPoint(_cgpath, &transform, x2, y2);
    } else if ([typeName isEqualToString:@"polyline"]) {
        NSString *points = [_attributes objectForKey:@"points"];
        parsePolyText(_cgpath, &transform, points, NO);
    } else if ([typeName isEqualToString:@"ellipse"]) {
        CGFloat cx = [[_attributes objectForKey:@"cx"] floatValue];
        CGFloat cy = [[_attributes objectForKey:@"cy"] floatValue];
        CGFloat rx = [[_attributes objectForKey:@"rx"] floatValue];
        CGFloat ry = [[_attributes objectForKey:@"ry"] floatValue];
        CGRect rect = CGRectMake(cx-rx, cy-ry, 2*rx, 2*ry);
        CGPathAddEllipseInRect(_cgpath, &transform, rect);
    } else {
        NSLog(@"ERROR: UNRECOGNIZED ELEMENT: %@", typeName);
        NSLog(@"attributes: %@", self.attributes);
    }
    
    id strokeColorName = [_attributes objectForKey:@"stroke"];
    if (strokeColorName) {
        if (_strokeColor) {
            CGColorRelease(_strokeColor);
        }
        _strokeColor = CGColorForName(strokeColorName);
    }
    
    id fillColorName = [_attributes objectForKey:@"fill"];
    if (!fillColorName) {
        if (strokeColorName) {
            fillColorName = @"none";
        } else {
            fillColorName = @"black";
        }
    }
    if (fillColorName) {
        if (_fillColor) {
            CGColorRelease(_fillColor);
        }
        _fillColor = CGColorForName(fillColorName);
    }
    
    id strokeWidthText = [_attributes objectForKey:@"stroke-width"];
    if (strokeWidthText) {
        self.strokeWidth = [strokeWidthText floatValue];
    }
    
}

- (void) drawInContext:(CGContextRef) context
             withAlpha:(CGFloat) p_alpha
             transform:(CGAffineTransform) transform
        colorOverrides:(NSDictionary *) colorOverrides {
    
    CGContextSaveGState(context);
    CGContextConcatCTM(context, transform);
    
    CGFloat alpha = p_alpha;
    if ([self.attributes objectForKey:@"opacity"]) {
        alpha = [[self.attributes objectForKey:@"opacity"] floatValue];
    }
    
    if (_fillColor) {
        CGColorRef finalFillColor;
        if (colorOverrides) {
            int c = CGColorGrayValue(_fillColor);
            CGColorRef overrideColor = (__bridge CGColorRef) [colorOverrides objectForKey:[NSNumber numberWithInt:c]];
            if (overrideColor) {
                finalFillColor = overrideColor;
            } else {
                finalFillColor = _fillColor;
            }
        } else {
            finalFillColor = _fillColor;
        }
        
        finalFillColor = CGColorCreateCopyWithAlpha(finalFillColor,
                                                    alpha*CGColorAlphaValue(finalFillColor));
        CGContextSetFillColorWithColor(context, finalFillColor);
        CGColorRelease(finalFillColor);
        
        CGContextAddPath(context, _cgpath);
        CGContextFillPath(context);
    }
    if (_strokeColor) {
        CGFloat linewidth = self.strokeWidth;
        if (linewidth == 0) {
            linewidth = 1;
        }
        CGContextSetLineWidth(context, linewidth);
        CGColorRef finalStrokeColor;
        if (colorOverrides) {
            int c = CGColorGrayValue(_strokeColor);
            CGColorRef overrideColor = (__bridge CGColorRef) [colorOverrides objectForKey:[NSNumber numberWithInt:c]];
            if (overrideColor) {
                finalStrokeColor = overrideColor;
            } else {
                finalStrokeColor = _strokeColor;
            }
        } else {
            finalStrokeColor = _strokeColor;
        }
        
        finalStrokeColor = CGColorCreateCopyWithAlpha(finalStrokeColor,
                                                      alpha*CGColorAlphaValue(finalStrokeColor));
        CGContextSetStrokeColorWithColor(context, finalStrokeColor);
        CGColorRelease(finalStrokeColor);
        
        
        id strokeLineCap = [self.attributes objectForKey:@"stroke-linecap"];
        if (strokeLineCap) {
            if ([strokeLineCap isEqualToString:@"round"]) {
                CGContextSetLineCap(context, kCGLineCapRound);
            } else {
                NSLog(@"unknown line cap %@", strokeLineCap);
            }
            //            kCGLineCapButt,
            //            kCGLineCapSquare
        }
        id strokeLineJoin = [self.attributes objectForKey:@"stroke-linecap"];
        if (strokeLineJoin) {
            if ([strokeLineJoin isEqualToString:@"round"]) {
                CGContextSetLineJoin(context, kCGLineJoinRound);
            } else {
                NSLog(@"unknown line join %@", strokeLineJoin);
            }
        }
        
        id strokeDashArray = [self.attributes objectForKey:@"stroke-dasharray"];
        if (strokeDashArray) {
            NSArray *dashes = [strokeDashArray componentsSeparatedByString:@","];
            NSUInteger dash_count = [dashes count];
            CGFloat *dash_lengths = (CGFloat *) malloc(dash_count * sizeof(CGFloat));
            for (NSUInteger i = 0; i < dash_count; i++) {
                dash_lengths[i] = [[dashes objectAtIndex:i] floatValue];
            }
            CGContextSetLineDash (context,
                                  0, /* phase */
                                  dash_lengths,
                                  dash_count);
            free(dash_lengths);
        }
        
        CGContextAddPath(context, _cgpath);
        CGContextStrokePath(context);
        
    }
    CGContextRestoreGState(context);
}

- (CGRect) bounds {
    return CGPathGetBoundingBox(_cgpath);
}

@end

#pragma mark - Groups (may be nested)

@implementation RadSVGGroup

- (NSString *) description {
    return [NSString stringWithFormat:@"Group: children=%@", [_children description]];
}

- (id) init {
    if ((self = [super init])) {
        self.children = [[NSMutableArray alloc] init];
        self.attributes = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) drawInContext:(CGContextRef) context
             withAlpha:(CGFloat) alpha
             transform:(CGAffineTransform)transform
        colorOverrides:(NSDictionary *)colorOverrides
{
    CGAffineTransform innerTransform = transform;
    if ([self.attributes objectForKey:@"opacity"]) {
        alpha = [[self.attributes objectForKey:@"opacity"] floatValue];
    }
    if ([self.attributes objectForKey:@"transform"]) {
        NSString *transformText = [self.attributes objectForKey:@"transform"];
        CGAffineTransform transform = parseTransform(transformText);
        innerTransform = CGAffineTransformConcat(innerTransform, transform);
    }
    for (id child in self.children) {
        [child drawInContext:context
                   withAlpha:alpha
                   transform:innerTransform
              colorOverrides:colorOverrides];
    }
}

- (CGRect) bounds {
    CGRect rect;
    int count = 0;
    for (id child in self.children) {
        if (count++) {
            rect = CGRectUnion(rect, [child bounds]);
        } else {
            rect = [child bounds];
        }
    }
    return rect;
}

@end

#pragma mark - SVG objects, each corresponds to an SVG file

@implementation RadSVGObject

+ (id) SVGObjectWithFile:(NSString *) filename
{
    @autoreleasepool {
        RadSVGReader *reader = [[RadSVGReader alloc] init];
        return [reader readSVGFromFile:filename];
    }
}

+ (id) SVGObjectWithString:(NSString *) string
{
    @autoreleasepool {
        RadSVGReader *reader = [[RadSVGReader alloc] init];
        return [reader readSVGFromString:string];
    }
}

+ (id) SVGObjectWithData:(NSData *) data
{
    @autoreleasepool {
        RadSVGReader *reader = [[RadSVGReader alloc] init];
        return [reader readSVGFromData:data];
    }
}

+ (RadSVGObject *) SVGObjectWithName:(NSString *) name
{
    if (!name)
        return nil;
    
    static NSMutableDictionary *svgCache = nil;
    if (!svgCache) {
        svgCache = [[NSMutableDictionary alloc] init];
    }
    
    RadSVGObject *svgObject = [svgCache objectForKey:name];
    if (!svgObject) {
        RadSVGReader *svgReader = [[RadSVGReader alloc] init];
        // look in the app resource directory
        if (!svgObject) {
            svgObject = [svgReader readSVGFromFile:[[NSBundle mainBundle]
                                                    pathForResource:name ofType:@"svg"]];
        }
        if (svgObject) {
            [svgCache setObject:svgObject forKey:name];
        }
    }
    return svgObject;
}

- (NSString *) description {
    return [NSString stringWithFormat:@"SVG: w=%d h=%d children=%@", _width, _height, [_children description]];
}

- (id) init {
    if ((self = [super init])) {
        self.children = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void) setViewBox:(CGRect)viewBox
{
    _viewBox = viewBox;
    if (_width == 0) {
        _width = viewBox.size.width;
    }
    if (_height == 0) {
        _height = viewBox.size.height;
    }
}

- (void) drawInContext:(CGContextRef) context
              withRect:(CGRect) rect
     verticalAlignment:(RadSVGVerticalAlignment) valign
   horizontalAlignment:(RadSVGHorizontalAlignment) halign
        colorOverrides:(NSDictionary *) colorOverrides{
    
    CGFloat xs = rect.size.width / self.width;
    CGFloat ys = rect.size.height / self.height;
    CGFloat s = fmin(xs,ys);
    
    CGFloat ym = (valign == RadSVGVerticalAlignmentCenter) ? 0.5 : (valign == RadSVGVerticalAlignmentTop) ? 0.0 : 1.0;
    CGFloat xm = (halign == RadSVGHorizontalAlignmentCenter) ? 0.5 : (halign == RadSVGHorizontalAlignmentLeft) ? 0.0 : 1.0;
    
    CGFloat y0 = rect.origin.y+ym*(rect.size.height - s*self.height);
    CGFloat x0 = rect.origin.x+xm*(rect.size.width - s*self.width);
    CGContextSaveGState(context);
    CGContextConcatCTM(context, CGAffineTransformMakeTranslation(x0,y0));
    CGContextConcatCTM (context, CGAffineTransformMakeScale(s, s));
    
    CGAffineTransform transform = CGAffineTransformIdentity;
    for (id child in self.children) {
        [child drawInContext:context withAlpha:1.0 transform:transform colorOverrides:colorOverrides];
    }
    CGContextRestoreGState(context);
}

#if TARGET_OS_IPHONE
- (NSData *) pngImageDataWithSize:(CGSize)size
{
    return [self pngImageDataWithSize:size colorOverrides:nil backgroundColor:nil];
}

- (NSData *) pngImageDataWithSize:(CGSize)size backgroundColor:(CGColorRef) backgroundColor
{
    return [self pngImageDataWithSize:size colorOverrides:nil backgroundColor:backgroundColor];
}
#endif

#if TARGET_OS_IPHONE

- (UIImage *) imageWithSize:(CGSize) size
             colorOverrides:(NSDictionary *) colorOverrides
                      scale:(CGFloat) scale
{
    if (CGSizeEqualToSize(size, CGSizeZero)) {
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate (NULL,
                                                  size.width*scale,
                                                  size.height*scale,
                                                  8,
                                                  0,
                                                  colorSpace,
                                                  (kCGBitmapAlphaInfoMask&kCGImageAlphaPremultipliedFirst));
    assert(context);
    UIGraphicsPushContext(context);
    CGContextConcatCTM(context, CGAffineTransformMakeTranslation(0, size.height*scale));
    CGContextConcatCTM(context, CGAffineTransformMakeScale(1, -1));
    CGRect drawRect = CGRectMake(0,0,size.width*scale,size.height*scale);
    [self drawInContext:context
               withRect:drawRect
      verticalAlignment:RadSVGVerticalAlignmentCenter
    horizontalAlignment:RadSVGHorizontalAlignmentCenter
         colorOverrides:colorOverrides];
    CGImageRef theCGImage=CGBitmapContextCreateImage(context);
    UIImage *image = [[UIImage alloc] initWithCGImage:theCGImage
                                                scale:scale
                                          orientation:UIImageOrientationUp];
    CGImageRelease(theCGImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    return image;
}

- (NSData *) pngImageDataWithSize:(CGSize) size
                   colorOverrides:(NSDictionary *) colorOverrides
                  backgroundColor:(CGColorRef) backgroundColor
{
    UIImage *image = [self imageWithSize:size colorOverrides:colorOverrides scale:2];
    return UIImagePNGRepresentation(image);
}

#endif

@end

#pragma mark - static helpers for SVG parsing

static CGFloat parseAttributeNumber(const char *string) {
    float number;
    char *suffix = (char *) malloc(strlen(string)+1);
    sscanf(string, "%f%s", &number, suffix);
    if (!strcmp(suffix, "cm")) {
        number *= 100;
    }
    free(suffix);
    return number;
}

static CGFloat parsePathNumber(const char **cp) {
    CGFloat value = 0.0;
    CGFloat fraction = 0.0;
    int sign = 1;
    if ((**cp == ',') || (**cp == ' ') || (**cp == '\n')) {
        (*cp)++;
    }
    if (**cp == '-') {
        sign = -1;
        (*cp)++;
    }
    while(((**cp >= '0') && (**cp <= '9')) || (**cp == '.')) {
        if (**cp == '.') {
            fraction = 0.1;
        } else {
            if (fraction == 0.0) {
                value = value * 10 + (**cp - '0');
            } else {
                value += fraction * (**cp - '0');
                fraction = fraction * 0.1;
            }
        }
        (*cp)++;
    }
    value = value * sign;
    // NSLog(@"returning %f", value);
    return value;
}

static void parsePathText(CGMutablePathRef cgpath, CGAffineTransform *transform, NSString *pathText) {
    const char *pathString = [pathText cStringUsingEncoding:NSUTF8StringEncoding];
    const char *c = pathString;
    CGFloat lastx2 = 0;
    CGFloat lasty2 = 0;
    while (*c) {
        if ((*c == ' ') || (*c == '\n')) {
            c++;
        } else if ((*c == 'm') || (*c == 'M')) {
            // MOVE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            if (*c == 'm') {
                CGPoint current = CGPathGetCurrentPoint(cgpath);
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x = parsePathNumber(&c)+xc;
            CGFloat y = parsePathNumber(&c)+yc;
            CGPathMoveToPoint(cgpath, transform, x, y);
        } else if ((*c == 'l') || (*c == 'L')) {
            // LINE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            if (*c == 'l') {
                CGPoint current = CGPathGetCurrentPoint(cgpath);
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x = parsePathNumber(&c)+xc;
            CGFloat y = parsePathNumber(&c)+yc;
            CGPathAddLineToPoint(cgpath, transform, x, y);
        } else if ((*c == 'h') || (*c == 'H')) {
            // HORIZONTAL LINE
            CGPoint current = CGPathGetCurrentPoint(cgpath);
            CGFloat xc = 0.0;
            if (*c == 'h') {
                xc = current.x;
            }
            c++;
            CGFloat y = current.y;
            CGFloat x = parsePathNumber(&c)+xc;
            CGPathAddLineToPoint(cgpath, transform, x, y);
        } else if ((*c == 'v') || (*c == 'V')) {
            // VERTICAL LINE
            CGPoint current = CGPathGetCurrentPoint(cgpath);
            CGFloat yc = 0.0;
            if (*c == 'v') {
                yc = current.y;
            }
            c++;
            CGFloat y = parsePathNumber(&c)+yc;
            CGFloat x = current.x;
            CGPathAddLineToPoint(cgpath, transform, x, y);
        } else if ((*c == 'c') || (*c == 'C')) {
            // BEZIER CURVE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            if (*c == 'c') {
                CGPoint current = CGPathGetCurrentPoint(cgpath);
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x1 = parsePathNumber(&c)+xc;
            CGFloat y1 = parsePathNumber(&c)+yc;
            CGFloat x2 = parsePathNumber(&c)+xc;
            CGFloat y2 = parsePathNumber(&c)+yc;
            CGFloat x0 = parsePathNumber(&c)+xc;
            CGFloat y0 = parsePathNumber(&c)+yc;
            CGPathAddCurveToPoint(cgpath, transform, x1, y1, x2, y2, x0, y0);
            lastx2 = x2;
            lasty2 = y2;
        } else if ((*c == 's') || (*c == 'S')) {
            // SHORTHAND BEZIER CURVE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            CGPoint current = CGPathGetCurrentPoint(cgpath);
            if (*c == 's') {
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x2 = parsePathNumber(&c)+xc;
            CGFloat y2 = parsePathNumber(&c)+yc;
            CGFloat x0 = parsePathNumber(&c)+xc;
            CGFloat y0 = parsePathNumber(&c)+yc;
            CGFloat x1 = current.x + (current.x - lastx2);
            CGFloat y1 = current.y + (current.y - lasty2);
            CGPathAddCurveToPoint(cgpath, transform, x1, y1, x2, y2, x0, y0);
            lastx2 = x2;
            lasty2 = y2;
        } else if ((*c == 'z') || (*c == 'Z')) {
            // CLOSE PATH
            CGPathCloseSubpath(cgpath);
            c++;
        } else if ((*c == 'q') || (*c == 'Q')) {
            // Quadratic BEZIER CURVE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            if (*c == 'q') {
                CGPoint current = CGPathGetCurrentPoint(cgpath);
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x1 = parsePathNumber(&c)+xc;
            CGFloat y1 = parsePathNumber(&c)+yc;
            CGFloat x0 = parsePathNumber(&c)+xc;
            CGFloat y0 = parsePathNumber(&c)+yc;
            CGPathAddQuadCurveToPoint(cgpath, transform, x1, y1, x0, y0);
            lastx2 = x1;
            lasty2 = y1;
        } else if ((*c == 't') || (*c == 'T')) {
            // SHORTHAND QUADRATIC BEZIER CURVE
            CGFloat xc = 0.0;
            CGFloat yc = 0.0;
            CGPoint current = CGPathGetCurrentPoint(cgpath);
            if (*c == 't') {
                xc = current.x;
                yc = current.y;
            }
            c++;
            CGFloat x0 = parsePathNumber(&c)+xc;
            CGFloat y0 = parsePathNumber(&c)+yc;
            CGFloat x1 = current.x + (current.x - lastx2);
            CGFloat y1 = current.y + (current.y - lasty2);
            CGPathAddQuadCurveToPoint(cgpath, transform, x1, y1, x0, y0);
            lastx2 = x1;
            lasty2 = y1;
        } else {
            NSLog(@"stuck on unknown svg path command: %c", *c);
            c++;
            //assert(0);
        }
    }
}

static void parsePolyText(CGMutablePathRef cgpath, CGAffineTransform *transform, NSString *polygonText, BOOL closePath) {
    BOOL started = NO;
    id pairs = [polygonText componentsSeparatedByString:@" "];
    for (id pair in pairs) {
        NSArray *coordinates = [pair componentsSeparatedByString:@","];
        if ([coordinates count] == 2) {
            CGFloat x = [[coordinates objectAtIndex:0] floatValue];
            CGFloat y = [[coordinates objectAtIndex:1] floatValue];
            if (!started) {
                started = YES;
                CGPathMoveToPoint(cgpath, transform, x, y);
            } else {
                CGPathAddLineToPoint(cgpath, transform, x, y);
            }
        }
    }
    if (closePath) {
        CGPathCloseSubpath(cgpath);
    }
}

#pragma mark - SVG Reader, reads files and creates SVG objects

@implementation RadSVGReader

- (id) init {
    if ((self = [super init])) {
        svgStack = [[NSMutableArray alloc] init];
    }
    return self;
}


- (void) processNode:(xmlTextReaderPtr) reader {
    xmlChar *node_name = xmlTextReaderName(reader);
    if (node_name == NULL)
        node_name = xmlStrdup(BAD_CAST "--");
    xmlChar *node_value = xmlTextReaderValue(reader);
    // int node_depth = xmlTextReaderDepth(reader);
    int node_type = xmlTextReaderNodeType(reader);
    int node_isempty = xmlTextReaderIsEmptyElement(reader);
    int node_hasattributes = xmlTextReaderHasAttributes(reader);
    /*
     XML_READER_TYPE_NONE = 0,
     XML_READER_TYPE_ELEMENT = 1,
     XML_READER_TYPE_ATTRIBUTE = 2,
     XML_READER_TYPE_TEXT = 3,
     XML_READER_TYPE_CDATA = 4,
     XML_READER_TYPE_ENTITY_REFERENCE = 5,
     XML_READER_TYPE_ENTITY = 6,
     XML_READER_TYPE_PROCESSING_INSTRUCTION = 7,
     XML_READER_TYPE_COMMENT = 8,
     XML_READER_TYPE_DOCUMENT = 9,
     XML_READER_TYPE_DOCUMENT_TYPE = 10,
     XML_READER_TYPE_DOCUMENT_FRAGMENT = 11,
     XML_READER_TYPE_NOTATION = 12,
     XML_READER_TYPE_WHITESPACE = 13,
     XML_READER_TYPE_SIGNIFICANT_WHITESPACE = 14,
     XML_READER_TYPE_END_ELEMENT = 15,
     XML_READER_TYPE_END_ENTITY = 16,
     XML_READER_TYPE_XML_DECLARATION = 17
     */
    // switch through the possible node types
    if (node_type == XML_READER_TYPE_SIGNIFICANT_WHITESPACE) {
        goto finished;
    }
    else if (node_type == XML_READER_TYPE_COMMENT) {
        goto finished;
    }
    else if (node_type == XML_READER_TYPE_END_ELEMENT) {
        if (!strcmp((const char *) node_name, "g") ||
            !strcmp((const char *) node_name, "path") ||
            !strcmp((const char *) node_name, "polygon") ||
            !strcmp((const char *) node_name, "rect") ||
            !strcmp((const char *) node_name, "polyline") ||
            !strcmp((const char *) node_name, "line") ||
            !strcmp((const char *) node_name, "circle") ||
            !strcmp((const char *) node_name, "ellipse") ||
            !strcmp((const char *) node_name, "image")) {
            id lastObject = [svgStack lastObject];
            if ([lastObject isKindOfClass:[RadSVGDrawable class]]) {
                [((RadSVGDrawable *)lastObject) process];
            }
            [svgStack removeLastObject];
        }
        goto finished;
    }
    else if (node_type == XML_READER_TYPE_ELEMENT) {
        if (!strcmp((const char *) node_name, "svg")) {
            [svgStack addObject:[[RadSVGObject alloc] init]];
            //NSLog(@"creating SVGFile");
        }
        else if (!strcmp((const char *) node_name, "g")) {
            RadSVGGroup *group = [[RadSVGGroup alloc] init];
            id parent = [svgStack lastObject];
            if ([parent isKindOfClass:[RadSVGObject class]]) {
                [((RadSVGObject *) parent).children addObject:group];
            } else if ([parent isKindOfClass:[RadSVGGroup class]]) {
                [((RadSVGGroup *) parent).children addObject:group];
            }
            [svgStack addObject:group];
            //NSLog(@"creating SVGGroup");
        }
        else if (!strcmp((const char *) node_name, "path") ||
                 !strcmp((const char *) node_name, "polygon") ||
                 !strcmp((const char *) node_name, "rect") ||
                 !strcmp((const char *) node_name, "polyline") ||
                 !strcmp((const char *) node_name, "line") ||
                 !strcmp((const char *) node_name, "circle") ||
                 !strcmp((const char *) node_name, "ellipse") ||
                 !strcmp((const char *) node_name, "image")) {
            RadSVGDrawable *drawable = [[RadSVGDrawable alloc] init];
            [drawable.attributes setObject:[NSString stringWithCString:(const char *) node_name encoding:NSUTF8StringEncoding] forKey:@"type"];
            //NSLog(@"creating SVGDrawable element %@", [drawable.attributes objectForKey:@"type"]);
            id parent = [svgStack lastObject];
            if ([parent isKindOfClass:[RadSVGObject class]]) {
                [((RadSVGObject *) parent).children addObject:drawable];
            } else if ([parent isKindOfClass:[RadSVGGroup class]]) {
                [((RadSVGGroup *) parent).children addObject:drawable];
            }
            [svgStack addObject:drawable];
        }
        else if (!strcmp((const char *) node_name, "use") ||
                 !strcmp((const char *) node_name, "title") ||
                 !strcmp((const char *) node_name, "desc") ||
                 !strcmp((const char *) node_name, "mask") ||
                 !strcmp((const char *) node_name, "defs")) {
            // known and unused or unsupported
        } else {
            NSLog(@"skipping unknown SVG element: %s", node_name);
        }
        if (node_hasattributes) {
            int more = xmlTextReaderMoveToNextAttribute(reader);
            while (more) {
                int nodeType = xmlTextReaderNodeType(reader);
                const char *name = (const char *) xmlTextReaderName(reader);
                const char *value = (const char *) xmlTextReaderValue(reader);
                if (nodeType == XML_READER_TYPE_ATTRIBUTE) {
                    id topObject = [svgStack lastObject];
                    if ([topObject isKindOfClass:[RadSVGObject class]]) {
                        RadSVGObject *svgFile = (RadSVGObject *) topObject;
                        if (!strcmp(name, "width")) {
                            svgFile->_width = parseAttributeNumber(value);
                        } else if (!strcmp(name, "height")) {
                            svgFile->_height = parseAttributeNumber(value);
                        } else if (!strcmp(name, "viewBox")) {
                            NSString *viewBoxString = [NSString stringWithCString:value encoding:NSUTF8StringEncoding];
                            NSArray *parts = [viewBoxString componentsSeparatedByString:@" "];
                            CGRect viewBox;
                            viewBox.origin.x = [parts[0] floatValue];
                            viewBox.origin.y = [parts[1] floatValue];
                            viewBox.size.width = [parts[2] floatValue];
                            viewBox.size.height = [parts[3] floatValue];
                            svgFile.viewBox = viewBox;
                        }
                    } else if ([topObject isKindOfClass:[RadSVGDrawable class]]) {
                        [((RadSVGDrawable *) topObject).attributes
                         setObject:[NSString stringWithCString:value encoding:NSUTF8StringEncoding]
                         forKey:[NSString stringWithCString:name encoding:NSUTF8StringEncoding]];
                    } else if ([topObject isKindOfClass:[RadSVGGroup class]]) {
                        [((RadSVGGroup *) topObject).attributes
                         setObject:[NSString stringWithCString:value encoding:NSUTF8StringEncoding]
                         forKey:[NSString stringWithCString:name encoding:NSUTF8StringEncoding]];
                    }
                }
                xmlFree((xmlChar *) name);
                xmlFree((xmlChar *) value);
                more = xmlTextReaderMoveToNextAttribute(reader);
            }
        }
        if (node_isempty) {
            if (!strcmp((const char *) node_name, "g") ||
                !strcmp((const char *) node_name, "path") ||
                !strcmp((const char *) node_name, "polygon") ||
                !strcmp((const char *) node_name, "rect") ||
                !strcmp((const char *) node_name, "polyline") ||
                !strcmp((const char *) node_name, "line") ||
                !strcmp((const char *) node_name, "circle") ||
                !strcmp((const char *) node_name, "ellipse")) {
                id lastObject = [svgStack lastObject];
                if ([lastObject isKindOfClass:[RadSVGDrawable class]]) {
                    [((RadSVGDrawable *)lastObject) process];
                }
                [svgStack removeLastObject];
            }
        }
    }
finished:
    xmlFree(node_name);
    if (node_value) {
        xmlFree(node_value);
    }
}

- (id) readSVGFromFile:(NSString *) filename {
    xmlTextReaderPtr reader = xmlNewTextReaderFilename([filename UTF8String]);
    if (reader != NULL) {
        int ret = xmlTextReaderRead(reader);
        while (ret == 1) {
            [self processNode:reader];
            ret = xmlTextReaderRead(reader);
        }
        xmlFreeTextReader(reader);
        if (ret != 0) {
            NSLog(@"Failed to parse SVG");
        }
    } else {
        NSLog(@"Unable to parse SVG");
    }
    id result = [svgStack lastObject];
    [svgStack removeAllObjects];
    return result;
}

- (id) readSVGFromData:(NSData *) data {
    if (!data) {
        return nil;
    }
    xmlTextReaderPtr reader = xmlReaderForMemory([data bytes], (int) [data length], "", NULL, 0);
    if (reader != NULL) {
        int ret = xmlTextReaderRead(reader);
        while (ret == 1) {
            [self processNode:reader];
            ret = xmlTextReaderRead(reader);
        }
        xmlFreeTextReader(reader);
        if (ret != 0) {
            NSLog(@"Failed to parse SVG");
        }
    } else {
        NSLog(@"Unable to parse SVG");
    }
    id result = [svgStack lastObject];
    [svgStack removeAllObjects];
    return result;
}

- (id) readSVGFromString:(NSString *) string {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [self readSVGFromData:data];
}

@end

#if TARGET_OS_IPHONE

@implementation RadSVGView

- (instancetype) initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame]) {
        self.contentMode = UIViewContentModeRedraw;
        self.verticalAlignment = RadSVGVerticalAlignmentCenter;
        self.horizontalAlignment = RadSVGHorizontalAlignmentCenter;
        self.colorOverrides = @{};
    }
    return self;
}

- (void) drawRect:(CGRect)rect
{
    [self.svgObject drawInContext:UIGraphicsGetCurrentContext()
                         withRect:self.bounds
                verticalAlignment:self.verticalAlignment
              horizontalAlignment:self.horizontalAlignment
                   colorOverrides:self.colorOverrides];
}

- (void) setSvgObject:(RadSVGObject *)svgObject
{
    _svgObject = svgObject;
    [self setNeedsDisplay];
}

@end

#endif