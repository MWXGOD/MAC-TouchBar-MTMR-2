#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Foundation/Foundation.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: make-round-logo input.png output.png\n");
            return 2;
        }

        NSURL *inputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)inputURL, NULL);
        CGImageRef input = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
        if (!input) {
            fprintf(stderr, "unable to read input image\n");
            if (source) CFRelease(source);
            return 1;
        }

        size_t side = MIN(CGImageGetWidth(input), CGImageGetHeight(input));
        size_t offsetX = (CGImageGetWidth(input) - side) / 2;
        size_t offsetY = (CGImageGetHeight(input) - side) / 2;
        CGImageRef square = CGImageCreateWithImageInRect(input, CGRectMake(offsetX, offsetY, side, side));
        size_t outputSide = side;
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, outputSide, outputSide, 8, outputSide * 4,
                                                       colorSpace, kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(colorSpace);
        if (!context || !square) {
            fprintf(stderr, "unable to create output image\n");
            if (context) CGContextRelease(context);
            if (square) CGImageRelease(square);
            CGImageRelease(input);
            CFRelease(source);
            return 1;
        }

        CGContextClearRect(context, CGRectMake(0, 0, outputSide, outputSide));
        CGContextAddEllipseInRect(context, CGRectMake(0, 0, outputSide, outputSide));
        CGContextClip(context);
        CGContextDrawImage(context, CGRectMake(0, 0, outputSide, outputSide), square);

        CGImageRef output = CGBitmapContextCreateImage(context);
        NSURL *outputURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]];
        CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)outputURL,
                                                                               CFSTR("public.png"), 1, NULL);
        BOOL success = NO;
        if (destination) {
            CGImageDestinationAddImage(destination, output, NULL);
            success = CGImageDestinationFinalize(destination);
        }

        if (destination) CFRelease(destination);
        CGImageRelease(output);
        CGContextRelease(context);
        CGImageRelease(square);
        CGImageRelease(input);
        CFRelease(source);
        return success ? 0 : 1;
    }
}
