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

#define kMaxNumFilterBands      24
#define kAudioSampleRate        44100.0
#define kAudioBytesPerPacket    4
#define kAudioFramesPerPacket   1
#define kAudioChannelsPerFrame  2

#define kMaxDelayTime 2.0

#pragma mark -
#pragma mark AudioController
@interface AudioController : NSObject {
    
@public
    
    /* Ring Mod */
    float modFreq;
    float modTheta;
    float modThetaInc;
    
    NVLowpassFilter *LPF;
    
    /* Filterbank */
    int nFilterBands;
    NVDSP *filters[kMaxNumFilterBands];
    float *filterCFs;
    float *filterQs;
    float *filterGains;

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
    
    CircularBuffer *circularBuffer;
    pthread_mutex_t circularBufferMutex;
    Float32 tapGains[kMaxNumDelayTaps];
}

@property Float32 hardwareSampleRate;

@property (readonly) bool inputEnabled;
@property (readonly) bool outputEnabled;
@property (readonly) bool isRunning;
@property (readonly) bool isInitialized;
@property bool lpfEnabled;
@property bool filterbankEnabled;
@property bool modulationEnabled;
@property bool delayEnabled;

- (void)setUpAUGraph;

/* Start/stop audio */
- (void)startAUGraph;
- (void)stopAUGraph;

/* Enable/disable audio input */
- (void)setInputEnabled: (bool)enabled;
- (void)setOutputEnabled:(bool)enabled;

/* Internal pre/post processing buffer setters/getters */
- (void)updateInputBuffer: (Float32 *)inBuffer;
- (void)updateOutputBuffer:(Float32 *)inBuffer;
- (void)getInputBuffer: (Float32 *)outBuffer;
- (void)getOutputBuffer:(Float32 *)outBuffer;

/* Filterbank setters */
- (void)setFilterCFs:   (float)freqs nBands:(int)n;
- (void)setFilterQs:    (float)qs    nBands:(int)n;
- (void)setFilterGains: (float)gains nBands:(int)n;
- (void)setFilterGain:  (float)gain  forBandNum:(int)n;
- (void)rescaleFilters:(float)minFreq max:(float)maxFreq;

- (void)setModFrequency:(float)freq;

@end
