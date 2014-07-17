//
//  PinchRegionView.h
//  DigitalSoundFX_v2
//
//  Created by Jeff Gregorio on 7/16/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface PinchRegionView : UIView

@property (readonly) CGFloat pixelHeightFromCenter;
@property (readonly) bool linesVisible;
@property CGFloat lineWidth;
@property UIColor *lineColor;

- (void)setPixelHeightFromCenter:(CGFloat)pix;
- (void)setLinesVisible:(bool)vis;

@end
