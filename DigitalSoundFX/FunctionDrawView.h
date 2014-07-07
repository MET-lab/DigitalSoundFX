//
//  FunctionDrawView.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 6/2/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FunctionDrawView : UIView {
    
    CGPoint *pixelValues;
    CGPoint previousTouchLoc;
}

@property bool drawEnabled;
@property (readonly) int nValues;

@end
