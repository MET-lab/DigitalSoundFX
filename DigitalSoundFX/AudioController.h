//
//  AudioController.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

/* Idea: have audio controller only update internal buffers as members instead of setting an external object to AudioControllerDelegate to register callbacks. Any object wishing to access information about the audio can set a timed selector that queries the AudioController's data and updates views. The distortion cutoff pinch can be set by a UI callback. Any interaction (data updates or queries) with AudioController in this configuration should be mutex protected by an accessible mutex property since data is updated and queried often in an audio thread. 
 
    This may require the ViewController to register a METScopeViewDelegate method that gets called by drawRect: so data from the AudioController is queried in the main (drawing) thread. */

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define kAudioSampleRate        44100.0
#define kAudioBytesPerPacket    4
#define kAudioFramesPerPacket   1
#define kAudioChannelsPerFrame  1

#pragma mark -
#pragma mark AudioControllerDelegate
/* Conform to AudioControllerDelegate to set input/output callbacks */
@protocol AudioControllerDelegate <NSObject>

@required
- (void)audioInputCallback:(float *)buffer length:(int)length;
- (void)audioOutputCallback:(float *)buffer length:(int)length;

@end

#pragma mark -
#pragma mark AudioController
@interface AudioController : NSObject {
    
@public 
    AUGraph graph;
    AudioUnit remoteIOUnit;
    AudioUnit equalizerUnit;
    AudioUnit converterUnit1;
    AudioUnit converterUnit2;
    
@private
    AudioStreamBasicDescription IOStreamFormat;
    AudioStreamBasicDescription EQStreamFormat;
    Float32 hardwareSampleRate;
}

@property id <AudioControllerDelegate> delegate;
@property Float32 hardwareSampleRate;

@property (readonly) bool inputEnabled;
@property (readonly) bool outputEnabled;
@property (readonly) bool isRunning;
@property (readonly) bool isInitialized;

- (void)setUpAUGraph;

/* Start/stop audio */
- (void)startAUGraph;
- (void)stopAUGraph;

/* Enable/disable audio input */
- (void)setInputEnabled:(bool)enabled;
- (void)setOutputEnabled:(bool)enabled;

/* Update a band of the nBandEQ audio unit */
- (void)updateBand:(int)n gain:(float)gain;

@end
