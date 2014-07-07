//
//  FunctionDrawView.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 6/2/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "FunctionDrawView.h"

@implementation FunctionDrawView

@synthesize drawEnabled;
@synthesize nValues;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
        /* Flags and other defaults */
        drawEnabled = true;
        nValues = self.frame.size.width;
        
        /* Initialize the drawing buffer */
        pixelValues = (CGPoint *)malloc(nValues * sizeof(CGPoint));
        for (int i = 0; i < nValues; i++)
            pixelValues[i] = CGPointMake(i, self.frame.size.height/2);
    }
    return self;
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    
    /* If drawing began, save the first touch location */
    if (drawEnabled) {
        UITouch *touch = [touches anyObject];
        previousTouchLoc = [touch locationInView:self];
    }
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    if (drawEnabled) {
        
        UITouch *touch = [touches anyObject];
        CGPoint loc = [touch locationInView:self];
        
        if (loc.x >= 0 && loc.x <= nValues && loc.y >= 0 && loc.y <= self.frame.size.height) {
            
            pixelValues[(int)loc.x] = loc;
        
            printf("\nloc.x = %f\nloc.y = %f\n", loc.x, loc.y);
            [self setNeedsDisplay];
        }
    }
}

- (void)drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, 1.0);
    for (int i = 0; i < nValues-1; i++) {
        CGContextMoveToPoint(context, pixelValues[i].x, pixelValues[i].y);
        CGContextAddLineToPoint(context, pixelValues[i+1].x, pixelValues[i+1].y);
        CGContextStrokePath(context);
    }
}

@end
