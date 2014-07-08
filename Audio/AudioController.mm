//
//  AudioController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "AudioController.h"

/* Main render callback method */
static OSStatus processingCallback(void *inRefCon, // Reference to the calling object
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
    
    /* Set the current buffer length */
    controller->bufferSizeFrames = inNumberFrames;
    
    /* Allocate a buffer for processing samples and copy the ioData into it */
    Float32 *procBuffer = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
    memcpy(procBuffer, (Float32 *)ioData->mBuffers[0].mData, sizeof(Float32) * inNumberFrames);
    
    /* Apply pre-gain */
    for (int i = 0; i < inNumberFrames; i++)
        procBuffer[i] *= controller->preGain;
    
    /* Set the pre-processing buffer with pre-gain applied */
    [controller appendInputBuffer:procBuffer withLength:inNumberFrames];
    
    /* ---------------- */
    /* == Modulation == */
    /* ---------------- */
    pthread_mutex_lock(&controller->modulationBufferMutex);
    for (int i = 0; i < inNumberFrames; i++) {
        
        controller->modulationBuffer[i] = sin(controller->modTheta);
        
        controller->modTheta += controller->modThetaInc;
        if (controller->modTheta > 2*M_PI)
            controller->modTheta -= 2*M_PI;
    }
    pthread_mutex_unlock(&controller->modulationBufferMutex);
    
    if (controller.modulationEnabled) {

        for (int i = 0; i < inNumberFrames; i++)
            procBuffer[i] *= controller->modulationBuffer[i];
    }
    
    /* ---------------- */
    /* == Distortion == */
    /* ---------------- */
    if (controller.distortionEnabled) {
        
        for (int i = 0; i < inNumberFrames; i++) {
            
            if (procBuffer[i] > controller->clippingAmplitude)
                procBuffer[i] = controller->clippingAmplitude;
            
            else if (procBuffer[i] < -controller->clippingAmplitude)
                procBuffer[i] = -controller->clippingAmplitude;
        }
    }
    
    /* ------------- */
    /* == Filters == */
    /* ------------- */
    
    if (controller.hpfEnabled)
        [controller->hpf filterContiguousData:procBuffer numFrames:inNumberFrames channel:0];
    
    if (controller.lpfEnabled)
        [controller->lpf filterContiguousData:procBuffer numFrames:inNumberFrames channel:0];
    
    /* ----------- */
    /* == Delay == */
    /* ----------- */
    
    /* Copy the processing buffer to the circular buffer */
    [controller->circularBuffer writeDataWithLength:inNumberFrames inData:procBuffer];
    
    if (controller.delayEnabled) {
        
        /* Allocate a buffer for the summed output of the filterbank */
        Float32 *outSamples = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
        memcpy(outSamples, procBuffer, inNumberFrames * sizeof(Float32));
        
        /* Allocate a buffer for the outputs of individual filter bands */
        Float32 *delayTapOut = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
        
        for (int i = 0; i < controller->circularBuffer.nTaps; i++) {
            
            /* Copy samples from the i^th delay tap */
            [controller->circularBuffer readFromDelayTap:i withLength:inNumberFrames outData:delayTapOut];
            
            /* Apply the tap gain */
            for (int j = 0; j < inNumberFrames; j++)
                outSamples[j] += controller->tapGains[i] * delayTapOut[j] / controller->circularBuffer.nTaps;
        }
        
        /* Overwrite the processing buffer with the delayed samples and free the unneeded buffers */
        memcpy(procBuffer, outSamples, inNumberFrames * sizeof(Float32));
        free(delayTapOut);
        free(outSamples);
    }
    
    /* Update the stored output buffer (for plotting) */
    [controller appendOutputBuffer:procBuffer withLength:inNumberFrames];
    
    /* Apply post-gain or mute */
    if (controller.outputEnabled) {
        for (int i = 0; i < inNumberFrames; i++)
            procBuffer[i] *= controller->postGain;
    }
    else {
        for (int i = 0; i < inNumberFrames; i++)
            procBuffer[i] *= 0;
    }
    
    /* Copy the processing buffer into the left and right output channels */
    memcpy((Float32 *)ioData->mBuffers[0].mData, procBuffer, inNumberFrames * sizeof(Float32));
    memcpy((Float32 *)ioData->mBuffers[1].mData, procBuffer, inNumberFrames * sizeof(Float32));
    
    free(procBuffer);
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

@synthesize hardwareSampleRate;

@synthesize bufferLength;

@synthesize inputEnabled;
@synthesize outputEnabled;
@synthesize isRunning;
@synthesize isInitialized;

@synthesize distortionEnabled;
@synthesize hpfEnabled;
@synthesize lpfEnabled;
@synthesize modulationEnabled;
@synthesize delayEnabled;

- (id)init {
    
    self = [super init];
    
    if (self) {
        
        /* Set flags */
        inputEnabled = false;
        outputEnabled = false;
        isInitialized = false;
        isRunning = false;
        distortionEnabled = false;
        hpfEnabled = false;
        lpfEnabled = false;
        modulationEnabled = false;
        delayEnabled = false;
        
        /* Defaults */
        preGain = 1.0;
        postGain = 1.0;
        clippingAmplitude = 1.0;
        
        bufferLength = kMaxDelayTime * kAudioSampleRate;
        
        [self allocateBuffersWithLength:bufferLength];
        [self setUpFilters];
        [self setUpRingModulator];
        [self setUpDelay];
        [self setUpAUGraph];
    }
    
    return self;
}

- (void)dealloc {
    
    if (inputBuffer)
        free(inputBuffer);
    if (outputBuffer)
        free(outputBuffer);
    
    pthread_mutex_destroy(&inputBufferMutex);
    pthread_mutex_destroy(&outputBufferMutex);
}

- (void)allocateBuffersWithLength:(int)length {
    
    if (inputBuffer)
        free(inputBuffer);
    
    inputBuffer  = (Float32 *)calloc(length, sizeof(Float32));
    pthread_mutex_init(&inputBufferMutex, NULL);
    
    if (outputBuffer)
        free(outputBuffer);
    
    outputBuffer = (Float32 *)calloc(length, sizeof(Float32));
    pthread_mutex_init(&outputBufferMutex, NULL);
}

- (void)setUpFilters {
    
    hpf = [[NVHighpassFilter alloc] initWithSamplingRate:kAudioSampleRate];
    hpf.Q = 2.0;
    hpf.cornerFrequency = 20;
    
    lpf = [[NVLowpassFilter alloc] initWithSamplingRate:kAudioSampleRate];
    lpf.Q = 2.0;
    lpf.cornerFrequency = 20000;
}

- (void)setUpRingModulator {
    
    modFreq = 440;
    modTheta = 0;
    
    if (!modulationBuffer)
        modulationBuffer = (Float32 *)malloc(kAudioBufferSize * sizeof(Float32));
    
    pthread_mutex_init(&modulationBufferMutex, NULL);
}

- (void)setUpDelay {
    
    circularBuffer = [[CircularBuffer alloc] initWithLength:(int)(kAudioSampleRate * kMaxDelayTime)];
    [circularBuffer addDelayTapForSampleDelay:(int)(kAudioSampleRate * 1.0)];
    tapGains[0] = 0.8;
    tapGains[1] = 0.5;
    tapGains[2] = 0.5;
    tapGains[3] = 0.5;
    tapGains[4] = 0.5;
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
    
    /* ------------------------------------------------------------- */
    /* ==== Set up: render callback instead of connections ========= */
    /* ------------------------------------------------------------- */
    
    /* Set an input callback rather than making any audio unit connections.  */
    AudioUnitElement outputBus = 0;
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc = processingCallback;
    inputCallbackStruct.inputProcRefCon = (__bridge void*) self;
    
    status = AudioUnitSetProperty(remoteIOUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Input,
                                  outputBus,
                                  &inputCallbackStruct,
                                  sizeof(inputCallbackStruct));
    if (status != noErr) {
        [self printErrorMessage:@"AudioUnitSetProperty[kAudioUnitProperty_SetRenderCallback] failed" withStatus:status];
    }
    
    /* ------------------------------------ */
    /* == Set Stream Formats, Parameters == */
    /* ------------------------------------ */
    
    [self setOutputEnabled:true];       // Enable output on the remoteIO unit
    [self setInputEnabled:true];        // Enable input on the remoteIO unit
    [self setIOStreamFormat];           // Set up stream format on input/output of the remoteIO
    
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
    
    outputEnabled = enabled;
    
//    OSStatus status;
//    UInt32 enableOutput = (UInt32)enabled;
//    AudioUnitElement outputBus = 0;
//    bool wasInitialized = false;
//    bool wasRunning = false;
//    
//    /* Stop if running */
//    if (isRunning) {
//        [self stopAUGraph];
//        wasRunning = true;
//    }
//    /* Uninitialize if initialized */
//    if (isInitialized) {
//        [self uninitializeGraph];
//        wasInitialized = true;
//    }
//    
//    /* Set up the remoteIO unit to enable/disable output */
//    status = AudioUnitSetProperty(remoteIOUnit,
//                                  kAudioOutputUnitProperty_EnableIO,
//                                  kAudioUnitScope_Output,
//                                  outputBus,
//                                  &enableOutput,
//                                  sizeof(enableOutput));
//    if (status != noErr) {
//        [self printErrorMessage:@"Enable/disable output failed" withStatus:status];
//    }
//    else outputEnabled = enabled;
//    
//    /* Reinitialize if needed */
//    if (wasInitialized)
//        [self initializeGraph];
//    
//    /* Restart if needed */
//    if (wasRunning)
//        [self startAUGraph];
}

/* Internal pre/post processing buffer setters/getters */
- (void)appendInputBuffer:(Float32 *)inBuffer withLength:(int)length {
    
    pthread_mutex_lock(&inputBufferMutex);
    
    /* Shift old values back */
    for (int i = 0; i < bufferLength - length; i++)
        inputBuffer[i] = inputBuffer[i + length];
    
    /* Append new values to the front */
    for (int i = 0; i < length; i++)
        inputBuffer[bufferLength - (length-i)] = inBuffer[i];
    
    pthread_mutex_unlock(&inputBufferMutex);
}
- (void)appendOutputBuffer:(Float32 *)inBuffer withLength:(int)length {
    
    pthread_mutex_lock(&outputBufferMutex);
    
    /* Shift old values back */
    for (int i = 0; i < bufferLength - length; i++)
        outputBuffer[i] = outputBuffer[i + length];
    
    /* Append new values to the front */
    for (int i = 0; i < length; i++)
        outputBuffer[bufferLength - (length-i)] = inBuffer[i];
    
    pthread_mutex_unlock(&outputBufferMutex);
}
- (void)getInputBuffer:(Float32 *)outBuffer withLength:(int)length {
    
    pthread_mutex_lock(&inputBufferMutex);
    for (int i = 0; i < length; i++)
        outBuffer[i] = inputBuffer[bufferLength - (length-i)];
    pthread_mutex_unlock(&inputBufferMutex);
}
- (void)getOutputBuffer:(Float32 *)outBuffer withLength:(int)length {
    
    pthread_mutex_lock(&outputBufferMutex);
    for (int i = 0; i < length; i++)
        outBuffer[i] = outputBuffer[bufferLength - (length-i)];
    pthread_mutex_unlock(&outputBufferMutex);
}

- (void)getModulationBuffer:(Float32 *)outBuffer withLength:(int)length {
    
    if (length > bufferSizeFrames)
        length = bufferSizeFrames;
    
    pthread_mutex_lock(&modulationBufferMutex);
    for (int i = 0; i < length; i++)
        outBuffer[i] = modulationBuffer[i];
    pthread_mutex_unlock(&modulationBufferMutex);
}

- (void)rescaleFilters:(float)minFreq max:(float)maxFreq {
    
    hpf.cornerFrequency = minFreq;
    lpf.cornerFrequency = maxFreq;
}

- (void)setModFrequency:(float)freq {
    
    modFreq = freq;
    modThetaInc = 2.0 * M_PI * modFreq / kAudioSampleRate;
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



















