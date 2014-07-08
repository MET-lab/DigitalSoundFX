//
//  AudioController.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <pthread.h>

#import "NVDSP.h"
#import "NVBandpassFilter.h"
#import "NVHighPassFilter.h"
#import "NVLowpassFilter.h"

#import "CircularBuffer.h"

#define kAudioSampleRate        44100.0
#define kAudioBytesPerPacket    4
#define kAudioFramesPerPacket   1
#define kAudioChannelsPerFrame  2

// Potentially unsafe assumption. Is there a way to force this buffer size or is it hardware-dependent?
#define kAudioBufferSize 1024

#define kMaxDelayTime 2.0

#pragma mark -
#pragma mark AudioController
@interface AudioController : NSObject {
    
@public
    
    /* Ring Mod */
    float modFreq;
    float modTheta;
    float modThetaInc;
    
    /* Filters */
    NVLowpassFilter *lpf;
    NVHighpassFilter *hpf;

    AUGraph graph;
    AudioUnit remoteIOUnit;
    AudioUnit equalizerUnit;
    AudioUnit converterUnit1;
    AudioUnit converterUnit2;
    
    UInt32 bufferSizeFrames;
    
    Float32 clippingAmplitude;
    Float32 preGain;
    Float32 postGain;
    
    AudioStreamBasicDescription IOStreamFormat;
    Float32 hardwareSampleRate;
    
    Float32 *inputBuffer;               // Pre-processing
    pthread_mutex_t inputBufferMutex;
    Float32 *outputBuffer;              // Post-processing
    pthread_mutex_t outputBufferMutex;
    
    Float32 *modulationBuffer;
    pthread_mutex_t modulationBufferMutex;
    
    CircularBuffer *circularBuffer;
    pthread_mutex_t circularBufferMutex;
    Float32 tapGains[kMaxNumDelayTaps];
}

@property Float32 hardwareSampleRate;

@property (readonly) int bufferLength;

@property (readonly) bool inputEnabled;
@property (readonly) bool outputEnabled;
@property (readonly) bool isRunning;
@property (readonly) bool isInitialized;

@property bool distortionEnabled;
@property bool hpfEnabled;
@property bool lpfEnabled;
@property bool modulationEnabled;
@property bool delayEnabled;

/* Start/stop audio */
- (void)startAUGraph;
- (void)stopAUGraph;

/* Enable/disable audio input */
- (void)setInputEnabled: (bool)enabled;
- (void)setOutputEnabled:(bool)enabled;

/* Append to and read most recent data from the internal buffers */
- (void)appendInputBuffer:(Float32 *)inBuffer withLength:(int)length;
- (void)appendOutputBuffer:(Float32 *)inBuffer withLength:(int)length;
- (void)getInputBuffer:(Float32 *)outBuffer withLength:(int)length;
- (void)getOutputBuffer:(Float32 *)outBuffer withLength:(int)length;
- (void)getModulationBuffer:(Float32 *)outBuffer withLength:(int)length;

/* Setters */
- (void)rescaleFilters:(float)minFreq max:(float)maxFreq;
- (void)setModFrequency:(float)freq;

@end
