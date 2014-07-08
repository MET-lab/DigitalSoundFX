//
//  FilterTapRegionView.h
//  DigitalSoundFX_v2
//
//  Created by Jeff Gregorio on 7/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FilterTapRegionView : UIView {
    
    int nPoints;
    CGPoint *points;
}

@property UIColor *fillColor;
@property (readonly) CGFloat fillAlpha;

- (void)setFillRegion:(CGPoint *)points numPoints:(int)n;
- (void)setFillAlpha:(CGFloat)alpha;
- (bool)pointInFillRegion:(CGPoint)point;

@end
