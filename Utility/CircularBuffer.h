//
//  CircularBuffer.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 6/24/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

/*
    Note: Always read from the delay taps before writing the current audio buffer to the circular buffer. If we write the current audio buffer, then read from a delay tap that is less than the length of one audio buffer from the write pointer, then we'll be reading from non-contiguous audio buffers
 */

#import <Foundation/Foundation.h>

#define kMaxNumDelayTaps 5

@interface CircularBuffer : NSObject {
    
    Float32 *buffer;
    int bufferLength;
    int writeIdx;
    int delayTaps[kMaxNumDelayTaps];
}

@property (readonly) int nTaps;

/* Allocate the buffer with a specified length */
- (id)initWithLength:(int)length;

/* Add a new delay tap */
- (void)addDelayTapForSampleDelay:(int)nSamples;

/* Set/get the sample delay for a specified tap */
- (void)setSampleDelayForTap:(int)tapIdx sampleDelay:(int)nSamples;
-  (int)getSampleDelayForTap:(int)tapIdx;

/* Write data to the circular buffer */
- (void)writeDataWithLength:(int)length inData:(Float32 *)data;

/* Read data starting from the delay tap index*/
- (void)readFromDelayTap:(int)tapIdx withLength:(int)length outData:(Float32 *)data;

@end
