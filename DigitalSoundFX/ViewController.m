//
//  ViewController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    /* ----------------------------------------------------- */
    /* == Setup for time and frequency domain scope views == */
    /* ----------------------------------------------------- */
    [kObjectTDScopeView setPlotResolution:256];
    [kObjectTDScopeView setHardXLim:-0.00001 max:1024/kAudioSampleRate];
    [kObjectTDScopeView setPlotUnitsPerXTick:0.005];
    [kObjectTDScopeView setAutoScaleGrid:true];
    [kObjectTDScopeView setAutoScaleXGrid:true];
    [kObjectTDScopeView setAutoScaleYGrid:true];
    
    [kObjectFDScopeView setPlotResolution:512];
    [kObjectFDScopeView setUpFFTWithSize:512];      // Set up FFT before setting FD mode
    [kObjectFDScopeView setDisplayMode:kMETScopeViewFrequencyDomainMode];
    [kObjectFDScopeView setHardXLim:0 max:9300];    // Set bounds after FD mode
    [kObjectFDScopeView setPlotUnitsPerXTick:2000];
    [kObjectFDScopeView setAutoScaleGrid:true];
    [kObjectFDScopeView setAutoScaleXGrid:true];
    [kObjectFDScopeView setAutoScaleYGrid:true];

    /* ----------------- */
    /* == Audio Setup == */
    /* ----------------- */
    audioController = [[AudioController alloc] init];
    [audioController setDelegate:self];
    
    /* ------------------------------------------ */
    /* == Setup for clipping threshold control == */
    /* ------------------------------------------ */
    clippingAmplitude = 1.0;
    
    /* Create a subview over the right-most 15th of the time domain scope view */
    CGRect pinchRegionFrame;
    pinchRegionFrame.size.width = kObjectTDScopeView.frame.size.width / 15;
    pinchRegionFrame.size.height = kObjectTDScopeView.frame.size.height;
    pinchRegionFrame.origin.x = kObjectTDScopeView.frame.size.width - pinchRegionFrame.size.width;
    pinchRegionFrame.origin.y = 0;
    distPinchRegionView = [[UIView alloc] initWithFrame:pinchRegionFrame];
    [distPinchRegionView setBackgroundColor:[UIColor clearColor]];
    [kObjectTDScopeView addSubview:distPinchRegionView];
    
    /* Add a pinch recognizer and set the callback to update the clipping amplitude */
    distCutoffPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(changeDistCutoff:)];
    [distPinchRegionView addGestureRecognizer:distCutoffPinchRecognizer];
}

- (void)changeDistCutoff:(UIPinchGestureRecognizer *)sender {

    /* Reset the previous scale if the gesture began */
    if(sender.state == UIGestureRecognizerStateBegan) {
        
        previousPinchScale = 1.0;
    }
    
    /* Otherwise, increment or decrement by a constant depending on the direction of the pinch */
    else {
        
        clippingAmplitude += (sender.scale > previousPinchScale ? 0.02 : -0.02);
        previousPinchScale = sender.scale;
    }
    
    /* Bound the clipping amplitude */
    if(clippingAmplitude >  1.0) clippingAmplitude =  1.0;
    if(clippingAmplitude < 0.05) clippingAmplitude = 0.05;
    
    /* Draw the clipping amplitude */
    float xx[] = {0.0, 0.1};
    float yy[] = {clippingAmplitude, clippingAmplitude};
    [kObjectTDScopeView setDataAtIndex:2
                            withLength:2
                                 xData:xx
                                 yData:yy
                                 color:[UIColor greenColor]
                             lineWidth:1.0];
    yy[0] = -clippingAmplitude;
    yy[1] = -clippingAmplitude;
    [kObjectTDScopeView setDataAtIndex:3
                            withLength:2
                                 xData:xx
                                 yData:yy
                                 color:[UIColor greenColor]
                             lineWidth:1.0];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)toggleAudio:(id)sender {
    
    if ([audioController isRunning]) {
        [audioController stopAUGraph];
    }
    else {
        [audioController startAUGraph];
    }
}

#pragma mark -
#pragma mark Audio Callbacks
- (void)audioInputCallback:(float *)buffer length:(int)length {
    
    /* Send to the scopes */
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),  ^{
        
        /* Allocate buffer of times for each sample */
        float *inputXBuffer = (float *)malloc(length * sizeof(float));
        [self linspace:0.0 max:length/kAudioSampleRate numElements:length array:inputXBuffer];
        
        /* Allocate an input buffer */
        float *inputYBuffer = (float *)malloc(length * sizeof(float));
        inputYBuffer = memcpy(inputYBuffer, buffer, length * sizeof(float));
        
        [kObjectTDScopeView setDataAtIndex:0
                                withLength:length
                                     xData:inputXBuffer
                                     yData:inputYBuffer
                                     color:[UIColor blueColor]
                                 lineWidth:2.0];
        
        [kObjectFDScopeView setDataAtIndex:0
                                withLength:length
                                     xData:inputXBuffer
                                     yData:inputYBuffer
                                     color:[UIColor blueColor]
                                 lineWidth:2.0];
        free(inputXBuffer);
        free(inputYBuffer);
    });
    

    /* Hard clipping */
    float *inSamples = (float *)malloc(length * sizeof(float));
    inSamples = memcpy(inSamples, buffer, length * sizeof(float));
    for (int i = 0; i < length; i++) {
        
        if (inSamples[i] > clippingAmplitude)
            inSamples[i] = clippingAmplitude;
        
        else if (inSamples[i] < -clippingAmplitude)
            inSamples[i] = -clippingAmplitude;
    }
    
    buffer = memcpy(buffer, inSamples, length * sizeof(float));
    free(inSamples);
}
- (void)audioOutputCallback:(float *)buffer length:(int)length {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0),  ^{
        
        /* Allocate buffer of times for each sample */
        float *inputXBuffer = (float *)malloc(length * sizeof(float));
        [self linspace:0.0 max:length/kAudioSampleRate numElements:length array:inputXBuffer];
        
        /* Allocate an input buffer */
        float *inputYBuffer = (float *)malloc(length * sizeof(float));
        inputYBuffer = memcpy(inputYBuffer, buffer, length * sizeof(float));
    
        [kObjectTDScopeView setDataAtIndex:1
                                withLength:length
                                     xData:inputXBuffer
                                     yData:inputYBuffer
                                     color:[UIColor redColor]
                                 lineWidth:1.0];

        [kObjectFDScopeView setDataAtIndex:1
                                withLength:length
                                     xData:inputXBuffer
                                     yData:inputYBuffer
                                     color:[UIColor redColor]
                                 lineWidth:2.0];
        free(inputXBuffer);
        free(inputYBuffer);
    });
}

#pragma mark -
#pragma mark Utility
/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal-minVal)/(size-1);
    array[0] = minVal;
    int i;
    for (i = 1;i<size-1;i++) {
        array[i] = array[i-1]+step;
    }
    array[size-1] = maxVal;
}


@end















