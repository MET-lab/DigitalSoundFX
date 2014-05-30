//
//  AudioController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "AudioController.h"

/* Idea: can we just pass a callback method from the delegate directly, and not have to go through this intermediate static callback? */


/* Main render callback method */
static OSStatus audioInputRender(void *inRefCon, // Reference to the calling object
                                 AudioUnitRenderActionFlags *ioActionFlags,
                                 const AudioTimeStamp 		*inTimeStamp,
                                 UInt32 					inBusNumber,
                                 UInt32 					inNumberFrames,
                                 AudioBufferList 			*ioData)
{
    OSStatus status;
    
	/* Cast void to AudioController input object */
	AudioController *controller = (__bridge AudioController *)inRefCon;
    
    /* Copy samples from input bus into the ioData (buffer to output) */
    status = AudioUnitRender(controller->remoteIOUnit,
                             ioActionFlags,
                             inTimeStamp,
                             1, // Input bus
                             inNumberFrames,
                             ioData);
    if (status != noErr)
        printf("Error rendering from remote IO unit\n");
    
    /* iPhone mic/line input is mono, so only send the first buffer */
    [controller.delegate audioInputCallback:(Float32 *)ioData->mBuffers[0].mData
                                      length:inNumberFrames];
    
	return status;
}


/* Callback that connects AUConverter2 to the RemoteIO's output bus. Manually pull samples from AUConverter2 so we can pass them in parallel to the AudioControllerDelegate's callback for plotting */
static OSStatus audioOutputRender(void *inRefCon, // Reference to the calling object
                                  AudioUnitRenderActionFlags    *ioActionFlags,
                                  const AudioTimeStamp          *inTimeStamp,
                                  UInt32                        inBusNumber,
                                  UInt32                        inNumberFrames,
                                  AudioBufferList               *ioData)
{
    OSStatus status;
    
	/* Cast void to AudioController input object */
	AudioController *controller = (__bridge AudioController *)inRefCon;
    
    /* Copy samples from the converter 2 unit to ioData (buffer to output) */
    status = AudioUnitRender(controller->converterUnit2,
                             ioActionFlags,
                             inTimeStamp,
                             0, // I/O bus
                             inNumberFrames,
                             ioData);
    if (status != noErr)
        printf("Error rendering from RemoteIO unit\n");
    
    /* Pass the data going to the output to the delegate's callback so it can plot */
    [controller.delegate audioOutputCallback:(Float32 *)ioData->mBuffers[0].mData
                                      length:inNumberFrames];
    return status;
}

/* Interrupt handler to stop/start audio for incoming notifications/alarms/calls */
void interruptListener(void *inUserData, UInt32 inInterruptionState) {
    
    AudioController *audioController = (__bridge AudioController *)inUserData;
    
    if (inInterruptionState == kAudioSessionBeginInterruption)
        [audioController stopAUGraph];
    else if (inInterruptionState == kAudioSessionEndInterruption)
        [audioController startAUGraph];
}

@implementation AudioController

@synthesize delegate;
@synthesize hardwareSampleRate;
@synthesize inputEnabled;
@synthesize outputEnabled;
@synthesize isRunning;
@synthesize isInitialized;

- (id)init {
    
    self = [super init];
    
    if (self) {
        
        inputEnabled = false;
        outputEnabled = false;
        isInitialized = false;
        isRunning = false;
        
        [self setUpAUGraph];
    }
    
    return self;
}

- (void)setUpAUGraph {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    OSStatus status;
    
    /* ------------------------ */
    /* == Create the AUGraph == */
    /* ------------------------ */
    
    status = NewAUGraph(&graph);
    if (status != noErr) {
        [self printErrorMessage:@"NewAUGraph failed" withStatus:status];
    }
    
    /* ----------------------- */
    /* == Add RemoteIO Node == */
    /* ----------------------- */
    
    AudioComponentDescription IOUnitDescription;    // Description
    IOUnitDescription.componentType          = kAudioUnitType_Output;
    IOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    IOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    IOUnitDescription.componentFlags         = 0;
    IOUnitDescription.componentFlagsMask     = 0;
    
    AUNode IONode;
    status = AUGraphAddNode(graph, &IOUnitDescription, &IONode);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[RemoteIO] failed" withStatus:status];
    }
    
    /* ---------------------- */
    /* == Add NBandEQ Node == */
    /* ---------------------- */
    
    AudioComponentDescription equalizerUnitDescription;     // Description
    equalizerUnitDescription.componentType          = kAudioUnitType_Effect;
    equalizerUnitDescription.componentSubType       = kAudioUnitSubType_NBandEQ;
    equalizerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    equalizerUnitDescription.componentFlags         = 0;
    equalizerUnitDescription.componentFlagsMask     = 0;

    AUNode EQNode;
    status = AUGraphAddNode(graph, &equalizerUnitDescription, &EQNode);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[NBandEQ] failed" withStatus:status];
    }
    
    /* -------------------------------- */
    /* == Add Format Converter Nodes == */
    /* -------------------------------- */
    
    AudioComponentDescription converterDescription;         // Description
    converterDescription.componentType         = kAudioUnitType_FormatConverter;
    converterDescription.componentSubType      = kAudioUnitSubType_AUConverter;
    converterDescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    converterDescription.componentFlags        = 0;
    converterDescription.componentFlagsMask    = 0;
    
    AUNode CNode1;
    status = AUGraphAddNode(graph, &converterDescription, &CNode1);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[AUConverter] failed" withStatus:status];
    }
    AUNode CNode2;
    status = AUGraphAddNode(graph, &converterDescription, &CNode2);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphAddNode[AUConverter] failed" withStatus:status];
    }
    
    /* ---------------------------------------------------------------------------------- */
    /* == Connections: remoteIO => AUConverter1 => nBandEQ => AUConverter2 => remoteIO == */
    /* ---------------------------------------------------------------------------------- */
    
//    status = AUGraphConnectNodeInput(graph, IONode, 1, CNode1, 0);  // remoteIO (input) => converter 1
//    if (status != noErr) {
//        [self printErrorMessage:@"AUGraphConnectNodeInput[input => AUConverter1] failed" withStatus:status];
//    }
    
    status = AUGraphConnectNodeInput(graph, CNode1, 0, EQNode, 0);  // converter 1 => NBandEQ
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphConnectNodeInput[AUConverter1 => NBandEQ] failed" withStatus:status];
    }
    
    status = AUGraphConnectNodeInput(graph, EQNode, 0, CNode2, 0);  // NBandEQ => converter 2
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphConnectNodeInput[NBandEQ => AUConverter2] failed" withStatus:status];
    }
    
//    status = AUGraphConnectNodeInput(graph, CNode2, 0, IONode, 0);  // converter 2 => remoteIO (output)
//    if (status != noErr) {
//        [self printErrorMessage:@"AUGraphConnectNodeInput[AUConverter2 => output] failed" withStatus:status];
//    }

    /* ------------------------------------------------------------ */
    /* ==== Set up: remoteIO (input) -> remoteIO (output) ========= */
    /* ------------------------------------------------------------ */

//    /* Connect the remoteIO unit's output to its input */
//    status = AUGraphConnectNodeInput(graph, IONode, 1, IONode, 0);
//    if (status != noErr) {
//        [self printErrorMessage:@"AUGraphConnectNodeInput failed" withStatus:status];
//    }
    
    /* ------------------------------------------------------------- */
    /* ==== Set up: render callback instead of connections ========= */
    /* ------------------------------------------------------------- */
    
//    /* Set an input callback rather than making any audio unit connections.  */
//    AudioUnitElement outputBus = 0;
//    AURenderCallbackStruct inputCallbackStruct;
//    inputCallbackStruct.inputProc = audioInputRender;
//    inputCallbackStruct.inputProcRefCon = (__bridge void*) self;
//    
//    status = AudioUnitSetProperty(remoteIOUnit,
//                                  kAudioUnitProperty_SetRenderCallback,
//                                  kAudioUnitScope_Global,
//                                  outputBus,
//                                  &inputCallbackStruct,
//                                  sizeof(inputCallbackStruct));
//    if (status != noErr) {
//        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
//    }
    
    /* ---------------------- */
    /* == Open the AUGraph == */
    /* ---------------------- */
    
    status = AUGraphOpen(graph);    // Instantiates audio units, but doesn't initialize
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphOpen failed" withStatus:status];
    }
    
    /* ----------------------------------------------------- */
    /* == Get AudioUnit instances from the opened AUGraph == */
    /* ----------------------------------------------------- */
    status = AUGraphNodeInfo(graph, IONode, NULL, &remoteIOUnit);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[RemoteIO] failed" withStatus:status];
    }
    
    status = AUGraphNodeInfo(graph, EQNode, NULL, &equalizerUnit);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[NBandEQ] failed" withStatus:status];
    }
    
    status = AUGraphNodeInfo(graph, CNode1, NULL, &converterUnit1);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[AUConverter1] failed" withStatus:status];
    }
    status = AUGraphNodeInfo(graph, CNode2, NULL, &converterUnit2);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphNodeInfo[AUConverter2] failed" withStatus:status];
    }
    
    /* ------------------- */
    /* == Set Callbacks == */
    /* ------------------- */
    AURenderCallbackStruct callback;
    callback.inputProcRefCon = (__bridge void *)self;
    
    /* Set a callback to pull data from RemoteIO's input bus and pass it to AUConverter 1 */
    callback.inputProc = audioInputRender;
    status = AudioUnitSetProperty(converterUnit1,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0, // I/O Bus
                                  &callback,
                                  sizeof(callback));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
    }

    /* Set a callback to pull data from AUConverter2 and send it in parallel to the RemoteIO's output bus and the AudioControllerDelegate's callback method audioOutputCallback:length: for plotting */
    callback.inputProc = audioOutputRender;
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  0, // Output Bus
                                  &callback,
                                  sizeof(callback));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
    }
    
    /* ------------------------------------ */
    /* == Set Stream Formats, Parameters == */
    /* ------------------------------------ */
    [self setOutputEnabled:true];       // Enable output on the remoteIO unit
    [self setInputEnabled:true];        // Enable input on the remoteIO unit
    [self setIOStreamFormat];           // Set up stream format on input/output of the remoteIO
    
    [self setUpEQUnit];             // Set frequency bands, bypass settings, gains; get stream format
    [self setConverterFormats];     // Set up the format conversion for the nBandEQ
    
    /* ------------------------ */
    /* == Initialize and Run == */
    /* ------------------------ */
    [self initializeGraph];     // Initialize the AUGraph (allocates resources)
    [self startAUGraph];        // Start the AUGraph
    
    CAShow(graph);
}

/* Set the stream format on the remoteIO audio unit */
- (void)setIOStreamFormat {
    
    OSStatus status;
    
    /* Set up the stream format for the I/O unit */
    memset(&IOStreamFormat, 0, sizeof(IOStreamFormat));
    IOStreamFormat.mSampleRate = kAudioSampleRate;
    IOStreamFormat.mFormatID = kAudioFormatLinearPCM;
    IOStreamFormat.mFormatFlags = kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved;
    IOStreamFormat.mBytesPerPacket = kAudioBytesPerPacket;
    IOStreamFormat.mFramesPerPacket = kAudioFramesPerPacket;
    IOStreamFormat.mBytesPerFrame = kAudioBytesPerPacket / kAudioFramesPerPacket;
    IOStreamFormat.mChannelsPerFrame = kAudioChannelsPerFrame;
    IOStreamFormat.mBitsPerChannel = 8 * kAudioBytesPerPacket;
    
    /* Set the stream format for the input bus */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Input] failed" withStatus:status];
    }
    
    /* Set the stream format for the output bus */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  1,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_StreamFormat - Output] failed" withStatus:status];
    }
}

/* Set the band frequencies and bypass settings for the NBandEQ unit; retrieve a description of its required stream format so we can set the converter formats later */
- (void)setUpEQUnit {
    
    OSStatus status;
    
    UInt32 maxNBands;
    UInt32 propSize = sizeof(maxNBands);
    status = AudioUnitGetProperty(equalizerUnit,
                                  kAUNBandEQProperty_MaxNumberOfBands,
                                  kAudioUnitScope_Global,
                                  0,
                                  &maxNBands,
                                  &propSize);
    printf("maxNBands = %d\n", (unsigned int)maxNBands);
    
    /* Set up the frequency bands */
//    NSArray *frequencies = @[@32, @250, @500, @1000, @2000, @16000];
    NSArray *frequencies = @[@500, @1000];

    /* Set the number of bands */
    UInt32 nBands = [frequencies count];
    status = AudioUnitSetProperty(equalizerUnit,
                                  kAUNBandEQProperty_NumberOfBands,
                                  kAudioUnitScope_Global,
                                  0,
                                  &nBands,
                                  sizeof(nBands));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[NBandEQ_MaxNumberOfBands] failed" withStatus:status];
    }

    /* Set properties for each band */
    for (int i = 0; i < nBands; i++) {
        
        /* Set the filter type to bandpass */
        status = AudioUnitSetParameter(equalizerUnit,
                                       kAUNBandEQParam_FilterType + i,
                                       kAudioUnitScope_Global,
                                       0,
                                       (AudioUnitParameterValue)kAUNBandEQFilterType_BandPass,
                                       0);
        if (status != noErr) {
            [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_FilterType + %d] failed", i] withStatus:status];
        }
        
        /* Set the center frequenices */
        status = AudioUnitSetParameter(equalizerUnit,
                                       kAUNBandEQParam_Frequency + i,
                                       kAudioUnitScope_Global,
                                       0,
                                       (AudioUnitParameterValue)[frequencies[i] floatValue],
                                       0);
        if (status != noErr) {
            [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_Frequency + %d] failed", i] withStatus:status];
        }
        
//        /* Set bandwidths */
//        status = AudioUnitSetParameter(equalizerUnit,
//                                       kAUNBandEQParam_Bandwidth + i,
//                                       kAudioUnitScope_Global,
//                                       0,
//                                       0.5,   // Half an octave
//                                       0);
//        if (status != noErr) {
//            [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_Bandwidth + %d] failed", i] withStatus:status];
//        }
        
//        /* Set the gains */
//        status = AudioUnitSetParameter(equalizerUnit,
//                                       kAUNBandEQParam_Gain + i,
//                                       kAudioUnitScope_Global,
//                                       0,
//                                       (AudioUnitParameterValue)-96.0,
//                                       0);
//        if (status != noErr) {
//            [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_Gain + %d] failed", i] withStatus:status];
//        }
        
        /* Set the bypass modes */
        status = AudioUnitSetParameter(equalizerUnit,
                                       kAUNBandEQParam_BypassBand + i,
                                       kAudioUnitScope_Global,
                                       0,
                                       1,   // Bypass off
                                       0);
        if (status != noErr) {
            [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_Frequency + %d] failed", i] withStatus:status];
        }
    }
    
    /* Also store a description of the EQ unit's required stream format */
    UInt32 size;    // Don't actually need this, but can't pass NULL pointer
    status = AudioUnitGetProperty(equalizerUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &EQStreamFormat,
                                  &size);
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitGetProperty[nBandEQ streamFormat] failed" withStatus:status];
    }
}

/* The NBandEQ unit has a different stream format than remoteIO unit, so set the AUConverter units to convert to and from the NBandEQ's stream format */
- (void)setConverterFormats {
    
    OSStatus status;
    
    /* Set the input format for converter 1 */
    status = AudioUnitSetProperty(converterUnit1,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[conv. 1 input stream format] failed" withStatus:status];
    }
    /* Set the output format for converter 1 */
    status = AudioUnitSetProperty(converterUnit1,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &EQStreamFormat,
                                  sizeof(EQStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[conv. 1 output stream format] failed" withStatus:status];
    }
    
    /* Set the input format for converter 2 */
    status = AudioUnitSetProperty(converterUnit2,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  0,
                                  &EQStreamFormat,
                                  sizeof(EQStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[conv. 2 input stream format] failed" withStatus:status];
    }
    /* Set the output format for converter 2 */
    status = AudioUnitSetProperty(converterUnit2,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  0,
                                  &IOStreamFormat,
                                  sizeof(IOStreamFormat));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[conv. 2 output stream format] failed" withStatus:status];
    }
}

/* Initialize the AUGraph (allocates resources) */
- (void)initializeGraph {
    
    OSStatus status = AUGraphInitialize(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphInitialize failed" withStatus:status];
    }
    else
        isInitialized = true;
}

/* Uninitialize the AUGraph in case we need to set properties that require an uninitialized graph */
- (void)uninitializeGraph {
    
    OSStatus status = AUGraphUninitialize(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphUninitialize failed" withStatus:status];
    }
    else
        isInitialized = false;
}

#pragma mark -
#pragma mark Interface Methods
/* Run audio */
- (void)startAUGraph {
    
    OSStatus status = AUGraphStart(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStart failed" withStatus:status];
    }
    else
        isRunning = true;
}

/* Stop audio */
- (void)stopAUGraph {
    
    OSStatus status = AUGraphStop(graph);
    if (status != noErr) {
        [self printErrorMessage:@"AUGraphStop failed" withStatus:status];
    }
    else
        isRunning = false;
}

/* Enable/disable audio input */
- (void)setInputEnabled:(bool)enabled {
    
    OSStatus status;
    UInt32 enableInput = (UInt32)enabled;
    AudioUnitElement inputBus = 1;
    bool wasInitialized = false;
    bool wasRunning = false;
    
    /* Stop if running */
    if (isRunning) {
        [self stopAUGraph];
        wasRunning = true;
    }
    /* Uninitialize if initialized */
    if (isInitialized) {
        [self uninitializeGraph];
        wasInitialized = true;
    }
    
    /* Set up the remoteIO unit to enable/disable input */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  inputBus,
                                  &enableInput,
                                  sizeof(enableInput));
    if (status != noErr) {
        [self printErrorMessage:@"Enable/disable input failed" withStatus:status];
    }
    else
        inputEnabled = enabled;
    
    /* Reinitialize if needed */
    if (wasInitialized)
        [self initializeGraph];
    
    /* Restart if needed */
    if (wasRunning)
        [self startAUGraph];
}

/* Enable/disable audio output */
- (void)setOutputEnabled:(bool)enabled {
    
    OSStatus status;
    UInt32 enableOutput = (UInt32)enabled;
    AudioUnitElement outputBus = 0;
    bool wasInitialized = false;
    bool wasRunning = false;
    
    /* Stop if running */
    if (isRunning) {
        [self stopAUGraph];
        wasRunning = true;
    }
    /* Uninitialize if initialized */
    if (isInitialized) {
        [self uninitializeGraph];
        wasInitialized = true;
    }
    
    /* Set up the remoteIO unit to enable/disable output */
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  outputBus,
                                  &enableOutput,
                                  sizeof(enableOutput));
    if (status != noErr) {
        [self printErrorMessage:@"Enable/disable output failed" withStatus:status];
    }
    else outputEnabled = enabled;
    
    /* Reinitialize if needed */
    if (wasInitialized)
        [self initializeGraph];
    
    /* Restart if needed */
    if (wasRunning)
        [self startAUGraph];
}

/* Update a band of the nBandEQ audio unit */
- (void)updateBand:(int)n gain:(float)gain {
    
    OSStatus status;
    status = AudioUnitSetParameter(equalizerUnit,
                                   kAUNBandEQParam_Gain + n,
                                   kAudioUnitScope_Global,
                                   0,
                                   gain,
                                   0);
    if (status != noErr) {
        [self printErrorMessage:[NSString stringWithFormat:@"AudioUnitSetParameter[kAUNBandEQParam_Gain + %d] failed", n] withStatus:status];
    }
}

#pragma mark Utility Methods
- (void)printErrorMessage:(NSString *)errorString withStatus:(OSStatus)result {
    
    char errorDetail[20];
    
    /* Check if the error is a 4-character code */
    *(UInt32 *)(errorDetail + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorDetail[1]) && isprint(errorDetail[2]) && isprint(errorDetail[3]) && isprint(errorDetail[4])) {
        
        errorDetail[0] = errorDetail[5] = '\'';
        errorDetail[6] = '\0';
    }
    else /* Format is an integer */
        sprintf(errorDetail, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", [errorString cStringUsingEncoding:NSASCIIStringEncoding], errorDetail);
}

@end



















