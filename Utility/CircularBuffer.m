//
//  CircularBuffer.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 6/24/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "CircularBuffer.h"

@implementation CircularBuffer

@synthesize nTaps;

/* Allocate the buffer with a specified length */
- (id)initWithLength:(int)length {
    
    self = [super init];
    if (self) {
    
        if (buffer)
            free(buffer);
        
        bufferLength = length;
        buffer = (Float32 *)calloc(bufferLength, sizeof(Float32));
        writeIdx = 0;
        nTaps = 0;
    }
    
    return self;
}

/* Add a new delay tap */
- (void)addDelayTapForSampleDelay:(int)nSamples {
    
    if (nTaps == kMaxNumDelayTaps) {
        NSLog(@"Warning: Maximum %d delay taps allowed", kMaxNumDelayTaps);
        return;
    }
    
    if (writeIdx - nSamples > 0)
        delayTaps[nTaps] = writeIdx - nSamples;
    else
        delayTaps[nTaps] = bufferLength + (writeIdx - nSamples);
    
    nTaps++;
}

/* Set/get the sample delay for a specified tap */
- (void)setSampleDelayForTap:(int)tapIdx sampleDelay:(int)nSamples {
    
    if (tapIdx < 0 && tapIdx >= kMaxNumDelayTaps) {
        NSLog(@"Warning: Invalid tap index %d (nTaps = %d)", tapIdx, nTaps);
        return;
    }
    
    if (writeIdx - nSamples > 0)
        delayTaps[tapIdx] = writeIdx - nSamples;
    else
        delayTaps[tapIdx] = bufferLength + (writeIdx - nSamples);
}

- (int)getSampleDelayForTap:(int)tapIdx {
    
    if (tapIdx < 0 && tapIdx >= kMaxNumDelayTaps) {
        NSLog(@"Warning: Invalid tap index %d (nTaps = %d)", tapIdx, nTaps);
        return -1;
    }
    
    if (delayTaps[tapIdx] > writeIdx)
        return bufferLength - delayTaps[tapIdx] + writeIdx;
    else
        return writeIdx - delayTaps[tapIdx];
}

/* Write data to the circular buffer */
- (void)writeDataWithLength:(int)length inData:(Float32 *)data {
    
    for (int i = 0; i < length; i++) {
        
        buffer[writeIdx] = data[i];
        
        writeIdx++;
        if (writeIdx >= bufferLength)
            writeIdx = 0;
    }
}

/* Read data starting from the write pointer without changing read/write pointers */
- (void)readDataFromWritePointerWithLength:(int)length outData:(Float32 *)data {
    
    int writeIdxCopy = writeIdx;
    
    for (int i = 0; i < length; i++) {
        
        data[i] = buffer[writeIdxCopy];
        
        writeIdxCopy++;
        if (writeIdxCopy >= bufferLength)
            writeIdxCopy = 0;
    }
}

/* Read data starting from the delay tap index*/
- (void)readFromDelayTap:(int)tapIdx withLength:(int)length outData:(Float32 *)data {
    
    if (tapIdx < 0 && tapIdx >= kMaxNumDelayTaps) {
        NSLog(@"Warning: Invalid tap index %d (nTaps = %d)", tapIdx, nTaps);
        return;
    }
    
    for (int i = 0; i < length; i++) {
        
        data[i] = buffer[delayTaps[tapIdx]];
        
        delayTaps[tapIdx]++;
        if (delayTaps[tapIdx] >= bufferLength)
            delayTaps[tapIdx] = 0;
    }
}

@end















