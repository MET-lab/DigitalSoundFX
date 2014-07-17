//
//  PinchRegionView.m
//  DigitalSoundFX_v2
//
//  Created by Jeff Gregorio on 7/16/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "PinchRegionView.h"

@implementation PinchRegionView

@synthesize pixelHeightFromCenter;
@synthesize linesVisible;
@synthesize lineWidth;
@synthesize lineColor;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        lineWidth = 8.0;
        lineColor = [UIColor greenColor];
    }
    return self;
}

- (void)setPixelHeightFromCenter:(CGFloat)pix {
    
    pixelHeightFromCenter = pix;
    [self setNeedsDisplay];
}

- (void)setLinesVisible:(bool)vis {
    
    linesVisible = vis;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    
    if (!linesVisible)
        return;
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, lineWidth);
    CGContextSetStrokeColorWithColor(context, lineColor.CGColor);
    
    /* Bottom cutoff handle */
    CGFloat height= (self.frame.size.height/2 - pixelHeightFromCenter);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, 0, height);
    CGContextAddLineToPoint(context, self.frame.size.width-1, height);
    CGContextStrokePath(context);
    
    /* Top cutoff handle */
    height = (self.frame.size.height/2 + pixelHeightFromCenter);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, 0, height);
    CGContextAddLineToPoint(context, self.frame.size.width-1, height);
    CGContextStrokePath(context);
    
}
@end
