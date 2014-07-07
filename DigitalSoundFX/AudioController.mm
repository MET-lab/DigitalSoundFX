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
    [controller updateInputBuffer:procBuffer];
    
    /* ------------------------------ */
    /* == Modulation / Waveshaping == */
    /* ------------------------------ */
    for (int i = 0; i < inNumberFrames; i++) {
        
        /* Ring mod */
        if (controller.modulationEnabled)
            procBuffer[i] *= sin(controller->modTheta);
        
        controller->modTheta += controller->modThetaInc;
        if (controller->modTheta > 2*M_PI)
            controller->modTheta -= 2*M_PI;
        
        /* Clipping */
        if (procBuffer[i] > controller->clippingAmplitude)
            procBuffer[i] = controller->clippingAmplitude;
        
        else if (procBuffer[i] < -controller->clippingAmplitude)
            procBuffer[i] = -controller->clippingAmplitude;
    }
    
    /* --------------------- */
    /* == Low Pass Filter == */
    /* --------------------- */
    if (controller.lpfEnabled) {
        [controller->LPF filterContiguousData:procBuffer numFrames:inNumberFrames channel:0];
    }
    
    /* ---------------- */
    /* == Filterbank == */
    /* ---------------- */
    if (controller.filterbankEnabled) {
        
        /* Allocate a buffer for the summed output of the filterbank */
        Float32 *outSamples = (Float32 *)calloc(inNumberFrames, sizeof(Float32));

        /* Allocate a buffer for the outputs of individual filter bands */
        Float32 *filterChannelOut = (Float32 *)calloc(inNumberFrames, sizeof(Float32));
    
        /* Pass the processing buffer through each filter band and recombine the outputs */
        for (int i = 0; i < controller->nFilterBands; i++) {
            
            /* Copy the processing buffer into the filter channel buffer and filter it */
            memcpy(filterChannelOut, procBuffer, inNumberFrames * sizeof(Float32));
            [controller->filters[i] filterContiguousData:filterChannelOut numFrames:inNumberFrames channel:0];
            
            /* Apply the band gain */
            for (int j = 0; j < inNumberFrames; j++)
                outSamples[j] += controller->filterGains[i] * filterChannelOut[j] / (Float32)controller->nFilterBands;
        }
        
        /* Overwrite the processing buffer with the filtered samples and free the unneeded buffers */
        memcpy(procBuffer, outSamples, inNumberFrames * sizeof(Float32));
        free(filterChannelOut);
        free(outSamples);
    }
    
    /* ----------- */
    /* == Delay == */
    /* ----------- */
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
    
    /* Copy the processing buffer to the circular buffer */
    [controller->circularBuffer writeDataWithLength:inNumberFrames inData:procBuffer];
    
    /* Update the stored output buffer (for plotting) */
    [controller updateOutputBuffer:procBuffer];
    
    /* Apply post-gain */
    for (int i = 0; i < inNumberFrames; i++)
        procBuffer[i] *= controller->postGain;
    
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
@synthesize inputEnabled;
@synthesize outputEnabled;
@synthesize isRunning;
@synthesize isInitialized;
@synthesize filterbankEnabled;
@synthesize lpfEnabled;
@synthesize delayEnabled;

- (id)init {
    
    self = [super init];
    
    if (self) {
        
        /* Set flags */
        inputEnabled = false;
        outputEnabled = false;
        isInitialized = false;
        isRunning = false;
        filterbankEnabled = false;
        lpfEnabled = true;
        delayEnabled = true;
        
        /* Defaults */
        preGain = 1.0;
        postGain = 1.0;
        clippingAmplitude = 1.0;
        
        [self setUpDefaultFilterBank];
        [self setUpLPF];
        [self setUpRingModulator];
        [self setUpDelay];
        [self setUpAUGraph];
    }
    
    return self;
}

- (void)dealloc {
    
    if (filterCFs)
        free(filterCFs);
    if (filterQs)
        free(filterQs);
    if (filterGains)
        free(filterGains);
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

- (void)setUpRingModulator {
    
    modFreq = 440;
    modTheta = 0;
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

- (void)setModFrequency:(float)freq {
    
    modFreq = freq;
    modThetaInc = 2.0 * M_PI * modFreq / kAudioSampleRate;
}

- (void)setUpLPF {
    
    LPF = [[NVLowpassFilter alloc] initWithSamplingRate:44100];
    LPF.cornerFrequency = 10000.0f;
    LPF.Q = 2.0f;
}

/* */
- (void)setUpDefaultFilterBank {
    
    nFilterBands = kMaxNumFilterBands;
    
    filterCFs   = (float *)calloc(nFilterBands, sizeof(float));
    filterQs    = (float *)calloc(nFilterBands, sizeof(float));
    filterGains = (float *)calloc(nFilterBands, sizeof(float));
    
//    float minFreq = 20.0;
//    float maxFreq = 16000.0;
//    float bandSpacing = (maxFreq - minFreq) / nFilterBands-1;
    
    filterCFs[0] = 20.0f;
    for (int i = 1; i < nFilterBands; i++) {
        filterCFs[i] = 100.0 * pow(2, ((float)i / 3.0f));
        printf("filterCFs[%d] = %f\n", i, filterCFs[i]);
    }
    
    NVHighpassFilter *hpf = [[NVHighpassFilter alloc] initWithSamplingRate:44100.0f];
    hpf.cornerFrequency = filterCFs[0];
    hpf.Q = filterQs[0] = filterCFs[0] / (24.7 * (4.37 * filterCFs[0] + 1));
    filters[0] = hpf;

    for (int i = 1; i < nFilterBands-1; i++) {
        
        /* Compute Q for an ERB filterbank */
//        filterQs[i] = filterCFs[i] / (24.7 * (4.37 * filterCFs[i] + 1));
        filterQs[i] = 2.0;
        filterGains[i] = 1.0f;
        
        NVBandpassFilter *bpf = (NVBandpassFilter *)filters[i];
        
        bpf = [[NVBandpassFilter alloc] initWithSamplingRate:44100.0f];
        bpf.Q = filterQs[i];
        bpf.centerFrequency = filterCFs[i];
        filters[i] = bpf;
    }
    
    NVLowpassFilter *lpf = [[NVLowpassFilter alloc] initWithSamplingRate:44100.0f];
    lpf.cornerFrequency = filterCFs[nFilterBands-1];
    lpf.Q = filterQs[nFilterBands-1] = filterCFs[nFilterBands-1] / (24.7 * (4.37 * filterCFs[nFilterBands-1] + 1));
    filters[nFilterBands-1] = lpf;
}

- (void)rescaleFilters:(float)minFreq max:(float)maxFreq {
    
    float bandSpacing = (maxFreq - minFreq) / nFilterBands-1;
    
    filterCFs[0] = fmax(minFreq, 20.0);
    
    for (int i = 1; i < nFilterBands-1; i++) {
        filterCFs[i] = filterCFs[i-1] + bandSpacing;
        filterQs[i] = filterCFs[i] / bandSpacing;
        filterQs[i] *= 2.0f;
        
        NVBandpassFilter *bpf = (NVBandpassFilter *)filters[i];
        bpf.centerFrequency = filterCFs[i];
        bpf.Q = filterQs[i];
    }
    
    filterCFs[nFilterBands-1] = maxFreq;
    NVLowpassFilter *lpf = (NVLowpassFilter *)filters[nFilterBands-1];
    lpf.cornerFrequency = filterCFs[nFilterBands-1];
    lpf.Q = filterQs[nFilterBands-1];
    
    for (int i = 0; i < nFilterBands; i++)
        printf("filterCFs[%d] = %f\n", i, filterCFs[i]);
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

/* Internal pre/post processing buffer setters/getters */
- (void)updateInputBuffer:(Float32 *)inBuffer {
    
    pthread_mutex_lock(&inputBufferMutex);
    free(inputBuffer);
    inputBuffer = (Float32 *)malloc(bufferSizeFrames * sizeof(Float32));
    memcpy(inputBuffer, inBuffer, bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&inputBufferMutex);
}
- (void)updateOutputBuffer:(Float32 *)inBuffer {
    
    pthread_mutex_lock(&outputBufferMutex);
    free(outputBuffer);
    outputBuffer = (Float32 *)malloc(bufferSizeFrames * sizeof(Float32));
    memcpy(outputBuffer, inBuffer, bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&outputBufferMutex);
}
- (void)getInputBuffer:(Float32 *)outBuffer {
    
    pthread_mutex_lock(&inputBufferMutex);
    memcpy(outBuffer, inputBuffer, bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&inputBufferMutex);
}
- (void)getOutputBuffer:(Float32 *)outBuffer {
    
    pthread_mutex_lock(&outputBufferMutex);
    memcpy(outBuffer, outputBuffer, bufferSizeFrames * sizeof(Float32));
    pthread_mutex_unlock(&outputBufferMutex);
}

/* Filterbank setters */
- (void)setFilterCFs:(float)freqs nBands:(int)n {
    for (int i = 0; i < n; i++)
        filterCFs[i] = freqs;
}
- (void)setFilterQs:(float)qs nBands:(int)n {
    for (int i = 0; i < n; i++)
        filterQs[i] = qs;
}
- (void)setFilterGains:(float)gains nBands:(int)n {
    for (int i = 0; i < n; i++)
        filterGains[i] = gains;
}
- (void)setFilterGain:(float)gain forBandNum:(int)n {
    filterGains[n] = gain;
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



















