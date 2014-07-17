//
//  FilterTapRegionView.m
//  DigitalSoundFX_v2
//
//  Created by Jeff Gregorio on 7/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "FilterTapRegionView.h"

@implementation FilterTapRegionView

@synthesize fillColor;
@synthesize fillAlpha;

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        
        fillColor = [UIColor blackColor];
        fillAlpha = 1.0;
        
        CGPoint p[4];
        p[0] = CGPointMake(0, 0);
        p[1] = CGPointMake(self.frame.size.width, 0);
        p[2] = CGPointMake(self.frame.size.width, self.frame.size.height);
        p[3] = CGPointMake(0, self.frame.size.height);
        [self setFillRegion:p numPoints:4];
    }
    return self;
}

- (void)setFillRegion:(CGPoint *)pts numPoints:(int)n {
    
    if (points)
        free(points);
    
    nPoints = n;
    points = (CGPoint *)malloc(nPoints * sizeof(CGPoint));
    memcpy(points, pts, nPoints*sizeof(CGPoint));
    
    [self setNeedsDisplay];
}

- (void)setFillAlpha:(CGFloat)alpha {
    fillAlpha = alpha;
    [self setNeedsDisplay];
}

- (bool)pointInFillRegion:(CGPoint)point {
    
    bool retVal = true;
    
    return retVal;
}

- (void)drawRect:(CGRect)rect {
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    [path moveToPoint:points[0]];
    
    for (int i = 1; i < nPoints; i++)
        [path addLineToPoint:points[i]];
    
    [path closePath];
    path.lineWidth = 1.0;
    [[UIColor clearColor] setStroke];
    [fillColor setFill];
    
    [path fillWithBlendMode:kCGBlendModeNormal alpha:fillAlpha];
    [path stroke];
}


@end













