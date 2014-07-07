//
//  EnvelopeView.m
//  AcousticSynthesis
//
//  Created by Matthew Zimmerman on 7/5/12.
//  Copyright (c) 2012 Drexel University. All rights reserved.
//

#import "EnvelopeView.h"

@implementation EnvelopeView

@synthesize values, delegate, drawEnabled;


- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    //    if (self) {
    drawEnabled = YES;
    pointValues = (float*)calloc(self.frame.size.width, sizeof(float));
    fullValues = (float*)calloc(self.frame.size.width, sizeof(float));
    scaledValues = (float*)calloc(self.frame.size.width, sizeof(float));
    pointSet = (int*)calloc(self.frame.size.width, sizeof(int));
    counter = 0;
    //    }
    pointValues[0] = self.frame.size.height/2;
    pointSet[0] = 1;
    
    for (int i = 1;i<self.frame.size.width-1;i++) {
        pointValues[i] = self.frame.size.height/2.0;
        //        pointValues[i] = arc4random()%(int)self.frame.size.height/2+self.frame.size.height/2.0;
        pointSet[i] = 1;
    }
    pointValues[(int)self.frame.size.width-1] = self.frame.size.height/2;
    pointSet[(int)self.frame.size.width-1] = 1;
    [self interpolateFullFrame];
    [self setNeedsDisplay];
    return self;

}

-(id) initWithCoder:(NSCoder *)aDecoder {
    self = [super initWithCoder:aDecoder];
//    if (self) {
        drawEnabled = YES;
        pointValues = (float*)calloc(self.frame.size.width, sizeof(float));
        fullValues = (float*)calloc(self.frame.size.width, sizeof(float));
        scaledValues = (float*)calloc(self.frame.size.width, sizeof(float));
        pointSet = (int*)calloc(self.frame.size.width, sizeof(int));
        counter = 0;
//    }
    pointValues[0] = self.frame.size.height/2;
    pointSet[0] = 1;
    
    for (int i = 1;i<self.frame.size.width-1;i++) {
        pointValues[i] = self.frame.size.height/2.0;
        //        pointValues[i] = arc4random()%(int)self.frame.size.height/2+self.frame.size.height/2.0;
        pointSet[i] = 1;
    }
    pointValues[(int)self.frame.size.width-1] = self.frame.size.height/2;
    pointSet[(int)self.frame.size.width-1] = 1;
    [self interpolateFullFrame];
    [self setNeedsDisplay];
    return self;
}



-(void) resetDrawing {
    pointValues[0] = self.frame.size.height/2;
    pointSet[0] = 1;
    
    for (int i = 1;i<self.frame.size.width-1;i++) {
        pointValues[i] = self.frame.size.height/2;
        pointSet[i] = 1;
    }
    pointValues[(int)self.frame.size.width-1] = self.frame.size.height/2;
    pointSet[(int)self.frame.size.width-1] = 1;
    [self setNeedsDisplay];
}

-(void) touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    if (drawEnabled){
        UITouch *touch = [touches anyObject];
        CGPoint touchLocation = [touch locationInView:self];
        previousLocation = touchLocation;
    }
    
    if ([delegate respondsToSelector:@selector(drawingStarted)]) {
        [delegate drawingStarted];
    }
}

-(void) touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    
    if (drawEnabled) {
        UITouch *touch = [touches anyObject];
        CGPoint touchLocation = [touch locationInView:self];
        
        if (touchLocation.x >= 0 && touchLocation.x <= self.frame.size.width) {
            if (touchLocation.y >= self.frame.size.height) {
                pointValues[(int)touchLocation.x] = self.frame.size.height;
            } else if (touchLocation.y <= 0) {
                pointValues[(int)touchLocation.x] = 0;
            } else {
                pointValues[(int)touchLocation.x] = touchLocation.y;
            }
            pointSet[(int)touchLocation.x] = 1;
        }
        
        [self resetPointsBetween:previousLocation.x andEndIndex:touchLocation.x];
        
        [self setNeedsDisplay];
        previousLocation = touchLocation;
    }
}

-(void) resetPointsBetween:(int)startIndex andEndIndex:(int)endIndex {
    int temp;
    if (endIndex<startIndex) {
        temp = startIndex;
        startIndex = endIndex;
        endIndex = temp;
    }
    for (int i = startIndex+1;i<endIndex;i++) {
        if (pointSet[i] == 1) {
            pointSet[i] = 0;
            pointValues[i] = 0;
        }
    }
}

-(void) touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    if (drawEnabled) {
        UITouch *touch = [touches anyObject];
        CGPoint touchLocation = [touch locationInView:self];
        previousLocation = touchLocation;
    }
    
    if ([delegate respondsToSelector:@selector(drawingEnded)]) {
        [delegate drawingEnded];
    }
}

-(CGPoint) getPreviousSetPointFromIndex:(int)index {
    
    CGPoint point = CGPointMake(index, pointValues[index]);
    BOOL done = NO;
    int i = index;
    while (!done) {
        if (i<=0) {
            point = CGPointMake(0, pointValues[0]);
            done = YES;
        } else {
            if (pointSet[i]==1) {
                point = CGPointMake(i, pointValues[i]);
                done = YES;
            }
        }
        i--;
    }
    return point;
}

-(CGPoint) getNextSetPointFromIndex:(int)index {
    CGPoint point = CGPointMake(index, pointValues[index]);
    BOOL done = NO;
    int i = index;
    while (!done) {
        if (i>=self.frame.size.width) {
            point = CGPointMake(self.frame.size.width-1, pointValues[(int)self.frame.size.width-1]);
            done = YES;
        } else {
            if (pointSet[i]==1) {
                point = CGPointMake(i, pointValues[i]);
                done = YES;
            }
        }
        i++;
    }
    return point;
}

-(void) drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, 1.0);
    CGPoint prevPoint = CGPointMake(0, self.frame.size.height);
    for (int i = 0;i<=self.frame.size.width;i++) {
        if (pointSet[i] == 1) {
            CGContextMoveToPoint(context,prevPoint.x,prevPoint.y);
            CGContextAddLineToPoint(context,i,pointValues[i]);
            prevPoint = CGPointMake(i, pointValues[i]);
            CGContextStrokePath(context);
        }
    }
    CGContextMoveToPoint(context,prevPoint.x,prevPoint.y);
    CGContextAddLineToPoint(context,self.frame.size.width ,self.frame.size.height);
    CGContextStrokePath(context);
    
    //    if (counter%1==0) {
    [self interpolateFullFrame];
    //    }
    counter++;
    if ([delegate respondsToSelector:@selector(drawViewChanged)]) {
        [delegate drawViewChanged];
    }
}

-(float) interpolateIndex:(int)index {
    CGPoint last = [self getPreviousSetPointFromIndex:index];
    CGPoint next = [self getNextSetPointFromIndex:index];
    float result = self.frame.size.height;
    if (next.x-last.x != 0) {
        result = (((index-last.x)*(next.y-last.y))/(next.x-last.x))+last.y;
    }
    return result;
}

-(void) clearDrawing {
    pointSet[0] = 1;
    pointValues[0] = self.frame.size.height;
    for (int i = 1;i<self.frame.size.width-1;i++) {
        pointSet[i] = 0;
        pointValues[i] = self.frame.size.height;
    }
    pointSet[(int)self.frame.size.width-1] = 1;
    pointValues[(int)self.frame.size.width-1] = self.frame.size.height;
    [self setNeedsDisplay];
    counter = 0;
}

-(void) interpolateFullFrame {
    float value;
    for (int i = 0;i<self.frame.size.width;i++) {
        if (pointSet[i]==1) {
            fullValues[i] = pointValues[i];
        } else {
            value = [self interpolateIndex:i];
            fullValues[i] = value;
        }
        scaledValues[i] = (self.frame.size.height-fullValues[i])/(self.frame.size.height);
    }
}

-(float*) getWaveform {
    return scaledValues;
}

-(void) setWaveform:(float*)newValues arraySize:(int)size {
    
    for (int i = 0;i<size;i++) {
        pointValues[i] = newValues[i];
        pointSet[i] = 1;
    }
    [self setNeedsDisplay];
}

-(void) setScaledValues:(float*)newValues arraySize:(int)size {
    
    for (int i = 0;i<size;i++) {
        scaledValues[i] = newValues[i];
    }
    [self setNeedsDisplay];
}
@end
