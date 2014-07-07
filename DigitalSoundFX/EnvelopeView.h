//
//  EnvelopeView.h
//  AcousticSynthesis
//
//  Created by Matthew Zimmerman on 7/5/12.
//  Copyright (c) 2012 Drexel University. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol EnvelopeDelegate <NSObject>

@optional

-(void) drawViewChanged;

-(void) drawingStarted;

-(void) drawingEnded;

@end

@interface EnvelopeView : UIView {
    
    float *pointValues;
    int *pointSet;
    float *fullValues;
    float *scaledValues;
    CGPoint previousLocation;
    int counter;
    id <EnvelopeDelegate> delegate;
    BOOL drawEnabled;
}

@property float *values;
@property id <EnvelopeDelegate> delegate;
@property BOOL drawEnabled;

-(void) resetPointsBetween:(int)startIndex andEndIndex:(int)endIndex;

-(void) clearDrawing;

-(CGPoint) getPreviousSetPointFromIndex:(int)index;

-(CGPoint) getNextSetPointFromIndex:(int)index;

-(float) interpolateIndex:(int)index;

-(void) interpolateFullFrame;

-(float*) getWaveform;

-(void) resetDrawing;

-(void) setWaveform:(float*)newValues arraySize:(int)size;

-(void) setScaledValues:(float*)newValues arraySize:(int)size;

@end