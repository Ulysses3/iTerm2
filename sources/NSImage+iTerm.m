//
//  NSImage+iTerm.m
//  iTerm
//
//  Created by George Nachman on 7/20/14.
//
//

#import "NSColor+iTerm.h"
#import "NSImage+iTerm.h"

@implementation NSImage (iTerm)

- (NSImage *)it_imageFillingSize:(NSSize)size {
    const CGFloat imageAspectRatio = self.size.width / self.size.height;
    const CGFloat containerAspectRatio = size.width / size.height;
    NSRect sourceRect;
    if (imageAspectRatio < containerAspectRatio) {
        // image is taller than container.
        sourceRect.origin.x = 0;
        sourceRect.size.width = self.size.width;
        sourceRect.size.height = self.size.width / containerAspectRatio;
        sourceRect.origin.y = (self.size.height - sourceRect.size.height) / 2.0;
    } else {
        // container is taller than image
        sourceRect.origin.y = 0;
        sourceRect.size.height = self.size.height;
        sourceRect.size.width = containerAspectRatio * self.size.height;
        sourceRect.origin.x = (self.size.width - sourceRect.size.width) / 2.0;
    }
    return [NSImage imageOfSize:size drawBlock:^{
        [self drawInRect:NSMakeRect(0, 0, size.width, size.height)
                fromRect:sourceRect
               operation:NSCompositingOperationCopy
                fraction:1];
    }];
}

+ (NSImage *)imageOfSize:(NSSize)size color:(NSColor *)color {
    return [self imageOfSize:size drawBlock:^{
        [color set];
        NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    }];
}

+ (instancetype)imageOfSize:(NSSize)size drawBlock:(void (^)(void))block {
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image it_drawWithBlock:block];
    return image;
}

- (void)it_drawWithBlock:(void (^)(void))block {
    if (self.size.width == 0 || self.size.height == 0) {
        return;
    }
    [self lockFocus];
    block();
    [self unlockFocus];
}

+ (NSData *)dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:(NSData *)input {
    NSMutableData *output = [NSMutableData dataWithLength:input.length * 4];
    unsigned char *ob = (unsigned char *)output.mutableBytes;
    unsigned char *ib = (unsigned char *)input.bytes;
    for (int i = 0; i < input.length; i++) {
        const int j = i * 4;
        ob[j + 0] = ib[i];
        ob[j + 1] = ib[i];
        ob[j + 2] = ib[i];
        ob[j + 3] = 255;
    }
    return output;
}

+ (instancetype)imageWithRawData:(NSData *)data
                            size:(NSSize)size
                   bitsPerSample:(NSInteger)bitsPerSample
                 samplesPerPixel:(NSInteger)samplesPerPixel
                        hasAlpha:(BOOL)hasAlpha
                  colorSpaceName:(NSString *)colorSpaceName {
    if (samplesPerPixel == 1) {
        return [self imageWithRawData:[self dataWithFourBytesPerPixelFromDataWithOneBytePerPixel:data]
                                 size:size
                        bitsPerSample:8
                      samplesPerPixel:4
                             hasAlpha:YES
                       colorSpaceName:colorSpaceName];
    }
    
    assert(data.length == size.width * size.height * bitsPerSample * samplesPerPixel / 8);
    NSBitmapImageRep *bitmapImageRep =
        [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil  // allocate the pixel buffer for us
                                                pixelsWide:size.width
                                                pixelsHigh:size.height
                                             bitsPerSample:bitsPerSample
                                           samplesPerPixel:samplesPerPixel
                                                  hasAlpha:hasAlpha
                                                  isPlanar:NO
                                            colorSpaceName:colorSpaceName
                                               bytesPerRow:bitsPerSample * samplesPerPixel * size.width / 8
                                              bitsPerPixel:bitsPerSample * samplesPerPixel];  // 0 means OS infers it

    memmove([bitmapImageRep bitmapData], data.bytes, data.length);

    NSImage *theImage = [[NSImage alloc] initWithSize:size];
    [theImage addRepresentation:bitmapImageRep];

    return theImage;
}

+ (NSString *)extensionForUniformType:(NSString *)type {
    NSDictionary *map = @{ (NSString *)kUTTypeBMP: @"bmp",
                           (NSString *)kUTTypeGIF: @"gif",
                           (NSString *)kUTTypeJPEG2000: @"jp2",
                           (NSString *)kUTTypeJPEG: @"jpeg",
                           (NSString *)kUTTypePNG: @"png",
                           (NSString *)kUTTypeTIFF: @"tiff",
                           (NSString *)kUTTypeICO: @"ico" };
    return map[type];
}

+ (instancetype)it_imageNamed:(NSImageName)name forClass:(Class)theClass {
    return [[NSBundle bundleForClass:theClass] imageForResource:name];
}

- (NSImage *)blurredImageWithRadius:(int)radius {
    // Initially, this used a CIFilter but this doesn't work on some machines for mysterious reasons.
    // Instead, this algorithm implements a really simple box blur. It's quite fast--about 5ms on
    // a macbook pro with radius 5 for a 48x48 image.

    NSImage *image = self;
    NSSize size = self.size;
    NSRect frame = NSMakeRect(0, 0, size.width, size.height);
    for (int i = 0; i < radius; i++) {
        [image lockFocus];
        [self drawInRect:frame
                fromRect:frame
               operation:NSCompositingOperationSourceOver
                fraction:1];
        [image unlockFocus];
        image = [self onePixelBoxBlurOfImage:image alpha:1.0/9.0];
    }
    return image;
}

- (NSImage *)onePixelBoxBlurOfImage:(NSImage *)image alpha:(CGFloat)alpha {
    NSSize size = image.size;
    NSImage *destination = [[NSImage alloc] initWithSize:image.size];
    [destination lockFocus];
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            [image drawInRect:NSMakeRect(dx,
                                         dy,
                                         size.width,
                                         size.height)
                     fromRect:NSMakeRect(0, 0, size.width, size.height)
                    operation:NSCompositingOperationSourceOver
                     fraction:alpha];
        }
    }
    [destination unlockFocus];
    return destination;
}

+ (CGContextRef)newBitmapContextOfSize:(NSSize)size storage:(NSMutableData *)data {
  NSInteger bytesPerRow = size.width * 4;
  NSUInteger storageNeeded = bytesPerRow * size.height;
  [data setLength:storageNeeded];

  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGContextRef context = CGBitmapContextCreate((void *)data.bytes,
                                               size.width,
                                               size.height,
                                               8,
                                               bytesPerRow,
                                               colorSpace,
                                               (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
  CGColorSpaceRelease(colorSpace);
  if (!context) {
    return NULL;
  }


  return context;
}

- (CGContextRef)newBitmapContextWithStorage:(NSMutableData *)data {
    NSSize size = self.size;
    return [NSImage newBitmapContextOfSize:size storage:data];
}

- (NSImage *)imageWithColor:(NSColor *)color {
    NSSize size = self.size;
    NSRect rect = NSZeroRect;
    rect.size = size;

    // Create a bitmap context.
    NSMutableData *data = [NSMutableData data];
    CGContextRef context = [self newBitmapContextWithStorage:data];

    // Draw myself into that context.
    CGContextDrawImage(context, rect, [self CGImageForProposedRect:NULL context:nil hints:nil]);

    // Now draw over it with |color|.
    CGContextSetFillColorWithColor(context, [color CGColor]);
    CGContextSetBlendMode(context, kCGBlendModeSourceAtop);
    CGContextFillRect(context, rect);

    // Extract the resulting image into the graphics context.
    CGImageRef image = CGBitmapContextCreateImage(context);

    // Convert to NSImage
    NSImage *coloredImage = [[NSImage alloc] initWithCGImage:image size:size];

    // Release memory.
    CGContextRelease(context);
    CGImageRelease(image);

    return coloredImage;
}

- (void)saveAsPNGTo:(NSString *)filename {
    [[self dataForFileOfType:NSPNGFileType] writeToFile:filename atomically:NO];
}

// TODO: Should this use -bitmapImageRep?
- (NSData *)dataForFileOfType:(NSBitmapImageFileType)fileType {
    CGImageRef cgImage = [self CGImageForProposedRect:NULL
                                              context:nil
                                                hints:nil];
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithCGImage:cgImage];
    [imageRep setSize:self.size];
    return [imageRep representationUsingType:fileType properties:@{}];
}

- (NSData *)rawPixelsInRGBColorSpace {
    NSMutableData *storage = [NSMutableData data];
    CGContextRef context = [self newBitmapContextWithStorage:storage];
    CGContextDrawImage(context, NSMakeRect(0, 0, self.size.width, self.size.height),
                       [self CGImageForProposedRect:NULL context:nil hints:nil]);
    CGContextRelease(context);
    return storage;
}

- (NSBitmapImageRep *)bitmapImageRep {
    int width = [self size].width;
    int height = [self size].height;

    if (width < 1 || height < 1) {
        return nil;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                    pixelsWide:width
                                                                    pixelsHigh:height
                                                                 bitsPerSample:8
                                                               samplesPerPixel:4
                                                                      hasAlpha:YES
                                                                      isPlanar:NO
                                                                colorSpaceName:NSDeviceRGBColorSpace
                                                                   bytesPerRow:width * 4
                                                                  bitsPerPixel:32];

    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep: rep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:ctx];
    [self drawAtPoint:NSZeroPoint
             fromRect:NSZeroRect
            operation:NSCompositingOperationCopy
             fraction:1.0];
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    return rep;
}

- (NSImageRep *)bestRepresentationForScale:(CGFloat)desiredScale {
    NSImageRep *best = nil;
    double bestScale = 0;
    CGFloat width = self.size.width;
    if (width <= 0) {
        return nil;
    }
    for (NSImageRep *rep in self.representations) {
        const double scale = best.pixelsWide / width;
        if (!best || fabs(desiredScale - scale) < fabs(desiredScale - bestScale)) {
            best = rep;
            bestScale = scale;
        }
    }
    return best;
}

- (NSImage *)it_imageWithTintColor:(NSColor *)tintColor {
    if (!tintColor) {
        return self;
    }
    NSSize size = self.size;
    NSImage *image = [self copy];
    image.template = NO;
    [image it_drawWithBlock:^{
        [tintColor set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
                                 NSCompositingOperationSourceAtop);
    }];
    return image;

}

- (NSImage *)it_flippedImage {
    const NSSize size = self.size;
    NSAffineTransform *transform = [NSAffineTransform transform];
    [transform scaleXBy:1 yBy:-1];
    NSAffineTransform *center = [NSAffineTransform transform];
    [center translateXBy:size.width / 2. yBy:size.height / 2.];
    [transform appendTransform:center];
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [transform concat];
    NSRect rect = NSMakeRect(0, 0, size.width, size.height);
    NSPoint corner = NSMakePoint(-size.width / 2., -size.height / 2.);
    [self drawAtPoint:corner fromRect:rect operation:NSCompositingOperationCopy fraction:1.0];
    [image unlockFocus];
    return image;
}

- (NSImage *)it_imageOfSize:(NSSize)newSize {
    if (!self.isValid) {
        return nil;
    }

    return [NSImage imageOfSize:newSize drawBlock:^{
        [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
        [self drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height)
                fromRect:NSMakeRect(0, 0, self.size.width, self.size.height)
               operation:NSCompositingOperationCopy
                fraction:1];
    }];
}

@end
