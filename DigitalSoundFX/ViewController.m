//
//  ViewController.m
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "ViewController.h"

@implementation ViewController

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    /* ----------------------------------------------------- */
    /* == Setup for time and frequency domain scope views == */
    /* ----------------------------------------------------- */
    [kObjectTDScopeView setPlotResolution:512];
    [kObjectTDScopeView setHardXLim:-0.00001 max:1024/kAudioSampleRate];
    [kObjectTDScopeView setPlotUnitsPerXTick:0.005];
    [kObjectTDScopeView setXGridAutoScale:true];
    [kObjectTDScopeView setYGridAutoScale:true];
    [kObjectTDScopeView setXPinchZoomEnabled:false];
    [kObjectTDScopeView setYPinchZoomEnabled:false];
    
    /* Allocate subviews for wet (pre-processing) and dry (post-processing) waveforms */
    tdDryIdx = [kObjectTDScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    tdWetIdx = [kObjectTDScopeView addPlotWithColor:[UIColor  redColor] lineWidth:2.0];
    
    /* Allocate subviews for the clipping amplitude */
    tdClipIdxLow = [kObjectTDScopeView addPlotWithResolution:10 color:[UIColor greenColor] lineWidth:2.0];
    tdClipIdxHigh = [kObjectTDScopeView addPlotWithResolution:10 color:[UIColor greenColor] lineWidth:2.0];
    
    [kObjectFDScopeView setPlotResolution:512];
    [kObjectFDScopeView setUpFFTWithSize:kFFTSize];      // Set up FFT before setting FD mode
    [kObjectFDScopeView setDisplayMode:kMETScopeViewFrequencyDomainMode];
    [kObjectFDScopeView setHardXLim:0.0 max:20000];       // Set bounds after FD mode
    [kObjectFDScopeView setVisibleXLim:0.0 max:9300];
    [kObjectFDScopeView setPlotUnitsPerXTick:2000];
    [kObjectFDScopeView setXGridAutoScale:true];
    [kObjectFDScopeView setYGridAutoScale:true];
    [kObjectFDScopeView setXPinchZoomEnabled:false];
    [kObjectFDScopeView setYPinchZoomEnabled:false];
    [kObjectFDScopeView setDelegate:self];
    
    /* Allocate subviews for wet (pre-processing) and dry (post-processing) waveforms */
    fdDryIdx = [kObjectFDScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    fdWetIdx = [kObjectFDScopeView addPlotWithColor:[UIColor  redColor] lineWidth:2.0];

    /* ----------------- */
    /* == Audio Setup == */
    /* ----------------- */
    audioController = [[AudioController alloc] init];
    
    /* Filter */
    [audioController setLpfEnabled:false];
    [audioController setFilterbankEnabled:true];
    
    /* Modulation */
    [audioController setModulationEnabled:false];
    [audioController setModFrequency:kObjectModFreqSlider.value];
    
    /* Delay */
    [audioController setDelayEnabled:false];
    [audioController->circularBuffer setSampleDelayForTap:0 sampleDelay:kObjectDelayTimeSlider.value*kAudioSampleRate];
    audioController->tapGains[0] = kObjectDelayFeedbackSlider.value;
    
    /* ---------------------------- */
    /* == Filter drawing/panning == */
    /* ---------------------------- */
    
    /* Get the FFT frequencies from the FD scope */
    plotFreqs = (float *)malloc(kObjectFDScopeView.frame.size.width * sizeof(float));
    [self linspace:kObjectFDScopeView.minPlotMin.x
               max:kObjectFDScopeView.maxPlotMax.x
       numElements:kObjectFDScopeView.frame.size.width
             array:plotFreqs];
    
    /* Allocate a subview */
    fdFilterIdx = [kObjectFDScopeView addPlotWithColor:[UIColor greenColor] lineWidth:2.0];
    
    /* Set up the tap gesture recognizer to overlay an EnvelopeView for drawing */
    filterDrawTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleFilterDraw:)];
    [filterDrawTapRecognizer setNumberOfTouchesRequired:1];
    [filterDrawTapRecognizer setNumberOfTapsRequired:2];
    [kObjectFDScopeView addGestureRecognizer:filterDrawTapRecognizer];
    
    filterDrawEnabled = false;
    filterPlotEnabled = false;
    filterDrawView = [[EnvelopeView alloc] initWithFrame:kObjectFDScopeView.frame];
    [filterDrawView setBackgroundColor:[UIColor grayColor]];
    [filterDrawView setAlpha:0.0];
    [self.view addSubview:filterDrawView];
    
    filterEnvelope = (float *)calloc(kObjectFDScopeView.frame.size.width, sizeof(float));
    
//    /* Filter panning: */
//    /* Create a subview over the bottom-most 5th of the frequency domain scope view */
//    CGRect panRegionFrame;
//    panRegionFrame.size.width = kObjectTDScopeView.frame.size.width;
//    panRegionFrame.size.height = kObjectTDScopeView.frame.size.height / 5;
//    panRegionFrame.origin.x = 0;
//    panRegionFrame.origin.y = kObjectTDScopeView.frame.size.height - panRegionFrame.size.height;
//    filterPanRegionView = [[UIView alloc] initWithFrame:panRegionFrame];
//    [filterPanRegionView setBackgroundColor:[UIColor clearColor]];
//    [kObjectFDScopeView addSubview:filterPanRegionView];
//    filterPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFilterPan:)];
//    [filterPanRecognizer setMinimumNumberOfTouches:1];
//    [filterPanRecognizer setMaximumNumberOfTouches:1];
//    [filterPanRegionView addGestureRecognizer:filterPanRecognizer];
    
    [self updatePreGain:self];
    [self updatePostGain:self];
    
    /* ------------------------------------------ */
    /* == Setup for clipping threshold control == */
    /* ------------------------------------------ */
    /* Create a subview over the right-most 15th of the time domain scope view */
    CGRect pinchRegionFrame;
    pinchRegionFrame.size.width = kObjectTDScopeView.frame.size.width / 12;
    pinchRegionFrame.size.height = kObjectTDScopeView.frame.size.height;
    pinchRegionFrame.origin.x = kObjectTDScopeView.frame.size.width - pinchRegionFrame.size.width;
    pinchRegionFrame.origin.y = 0;
    distPinchRegionView = [[UIView alloc] initWithFrame:pinchRegionFrame];
    [distPinchRegionView setBackgroundColor:[UIColor clearColor]];
    [kObjectTDScopeView addSubview:distPinchRegionView];
    
    /* Add a pinch recognizer and set the callback to update the clipping amplitude */
    distCutoffPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(changeDistCutoff:)];
    [distPinchRegionView addGestureRecognizer:distCutoffPinchRecognizer];
    
    /* Update the scope views on a timer by querying AudioController's wet/dry signal buffers */
    [NSTimer scheduledTimerWithTimeInterval:0.002 target:self selector:@selector(updateWaveforms) userInfo:nil repeats:YES];
}

- (void)updateWaveforms {
    
    /* Get buffer of times for each sample */
    plotTimes = (float *)malloc(audioController->bufferSizeFrames * sizeof(float));
    [self linspace:0.0 max:audioController->bufferSizeFrames/kAudioSampleRate numElements:audioController->bufferSizeFrames array:plotTimes];
    
    /* Allocate wet/dry signal buffers */
    float *dryYBuffer = (float *)malloc(audioController->bufferSizeFrames * sizeof(float));
    float *wetYBuffer = (float *)malloc(audioController->bufferSizeFrames * sizeof(float));
    
    /* Get current buffer values from the audio controller */
    [audioController getInputBuffer:dryYBuffer];
    [audioController getOutputBuffer:wetYBuffer];
    
    /* Update the plots */
    [kObjectTDScopeView setPlotDataAtIndex:tdDryIdx
                              withLength:audioController->bufferSizeFrames
                                   xData:plotTimes
                                   yData:dryYBuffer];
    
    [kObjectTDScopeView setPlotDataAtIndex:tdWetIdx
                              withLength:audioController->bufferSizeFrames
                                   xData:plotTimes
                                   yData:wetYBuffer];
    
    [kObjectFDScopeView setPlotDataAtIndex:fdDryIdx
                                withLength:audioController->bufferSizeFrames
                                     xData:plotTimes
                                     yData:dryYBuffer];
    
    [kObjectFDScopeView setPlotDataAtIndex:fdWetIdx
                                withLength:audioController->bufferSizeFrames
                                     xData:plotTimes
                                     yData:wetYBuffer];
    free(plotTimes);
    free(dryYBuffer);
    free(wetYBuffer);
}

- (IBAction)updatePreGain:(id)sender {
    audioController->preGain = kObjectPreGainSlider.value;
}

- (IBAction)updatePostGain:(id)sender {
    audioController->postGain = kObjectPostGainSlider.value;
    printf("gain = %f\n", audioController->postGain);
}

- (IBAction)updateModFreq:(id)sender {
    [audioController setModFrequency:kObjectModFreqSlider.value];
    printf("mod freq = %f\n", audioController->modFreq);
}

- (IBAction)updateDelayTime:(id)sender {
    [audioController->circularBuffer setSampleDelayForTap:0 sampleDelay:kAudioSampleRate*kObjectDelayTimeSlider.value];
    printf("delay time = %f\n", [audioController->circularBuffer getSampleDelayForTap:0] / kAudioSampleRate);
}

- (IBAction)updateFeedback:(id)sender {
    audioController->tapGains[0] = kObjectDelayFeedbackSlider.value;
}

- (void)handleFilterDraw:(UITapGestureRecognizer *)sender {

    /* If we're activating filter draw mode, make the envelope view translucent, tell it to start drawing, and add the double-tap gesture recognizer to the envelope view so we can exit with another double-tap */
    if (!filterDrawEnabled) {
        filterDrawEnabled = true;
        [filterDrawView setAlpha:0.5];
        [filterDrawView addGestureRecognizer:filterDrawTapRecognizer];
        [filterDrawView setScaledValues:filterEnvelope arraySize:filterDrawView.frame.size.width];
    }
    
    /* If we're exiting filter draw mode, make the envelope view transparent, get the drawn waveform, sample it to get multi-band EQ gains, and plot it */
    else {
        filterDrawEnabled = false;
        [filterDrawView setAlpha:0.0];
        filterEnvelope = [filterDrawView getWaveform];
        [kObjectFDScopeView addGestureRecognizer:filterDrawTapRecognizer];
        
        if ([audioController filterbankEnabled]) {
            [self sampleDrawnFilter];
            [self plotFilterEnvelope];
        }
    }
}

- (void)handleFilterPan:(UIPanGestureRecognizer *)sender {
    
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    /* Save the initial touch location */
    if (sender.state == UIGestureRecognizerStateBegan) {
        previousPanTouchLoc = touchLoc;
        return;
    }
    
    /* Shift the cutoff of the LPF */
    if ([audioController lpfEnabled]) {
        
        CGPoint shift;
        shift.x = touchLoc.x - previousPanTouchLoc.x;
        shift.x *= kObjectFDScopeView.unitsPerPixel.x;
        
        float oldFc = [audioController->LPF cornerFrequency];
        float newFc = oldFc + shift.x;
        
        if (newFc < 20.0) newFc = 20.0;
        if (newFc > 16000.0) newFc = 16000.0;
        
        [audioController->LPF setCornerFrequency:newFc];
    }
    
    /* Shift the filter envelope */
    if ([audioController filterbankEnabled]) {
        
        int shiftLength;
        
        /* Shift right */
        if (touchLoc.x > previousPanTouchLoc.x) {
        
            shiftLength = round(touchLoc.x - previousPanTouchLoc.x);
            
            for (int n = 0; n < shiftLength; n++) {
                for (int i = filterDrawView.frame.size.width-1; i >= 0; i--)
                    filterEnvelope[i+1] = filterEnvelope[i];
            }
        }

        /* Shift left */
        else {
            shiftLength = round(previousPanTouchLoc.x - touchLoc.x);
            
            for (int n = 0; n < shiftLength; n++) {
                for (int i = 1; i <= filterDrawView.frame.size.width; i++)
                    filterEnvelope[i-1] = filterEnvelope[i];
            }
        }
        
        [self sampleDrawnFilter];   // Re-sample the filter envelope for filterbank gains
        [self plotFilterEnvelope];  // Re-draw the shifted filter
    }
    
    previousPanTouchLoc = touchLoc;
}

- (void)sampleDrawnFilter {
    
    CGPoint pixelVal;
    
    for (int i = 0; i < audioController->nFilterBands; i++) {
        
        pixelVal = [kObjectFDScopeView plotScaleToPixel:audioController->filterCFs[i] y:0.0];
        
        pixelVal.y = 0.4 + filterEnvelope[(int)round(pixelVal.x)];
        pixelVal.y = 2 * pixelVal.y - 1;    // Convert scale to inerval [-1 1]
        pixelVal.y = pixelVal.y * 40;       // Convert to interval [-20 20]
        
        audioController->filterGains[i] = powf(10, (pixelVal.y / 20));
    }
}

- (void)plotFilterEnvelope {
    
    [kObjectFDScopeView setCoordinatesInFDModeAtIndex:fdFilterIdx
                                           withLength:filterDrawView.frame.size.width
                                                xData:plotFreqs
                                                yData:filterEnvelope];
}

- (void)changeDistCutoff:(UIPinchGestureRecognizer *)sender {

    /* Reset the previous scale if the gesture began */
    if(sender.state == UIGestureRecognizerStateBegan) {
        
        previousPinchScale = 1.0;
    }
    
    /* Otherwise, increment or decrement by a constant depending on the direction of the pinch */
    else {
        
        float scaleChange = (sender.scale - previousPinchScale) / previousPinchScale;
        audioController->clippingAmplitude *= (1 + scaleChange);
        previousPinchScale = sender.scale;
    }
    
    /* Bound the clipping amplitude */
    if(audioController->clippingAmplitude >  1.0) audioController->clippingAmplitude =  1.0;
    if(audioController->clippingAmplitude < 0.05) audioController->clippingAmplitude = 0.05;
    
    /* Draw the clipping amplitude */
    float xx[] = {0.0, 0.1};
    float yy[] = {audioController->clippingAmplitude, audioController->clippingAmplitude};
    
    /* Plot */
    [kObjectTDScopeView setPlotDataAtIndex:tdClipIdxHigh
                                withLength:2
                                     xData:xx
                                     yData:yy];
    
    /* Negative mirror */
    yy[0] = -audioController->clippingAmplitude;
    yy[1] = -audioController->clippingAmplitude;
    
    /* Plot */
    [kObjectTDScopeView setPlotDataAtIndex:tdClipIdxLow
                                withLength:2
                                     xData:xx
                                     yData:yy];
}

/* METScopeViewDelegate method. Update the filter center frequencies for the new FD plot bounds */
- (void)finishedPinchZoom {
    
    printf("Rescaling filters ------------\n");
    [audioController rescaleFilters:kObjectFDScopeView.visiblePlotMin.x
                                max:kObjectFDScopeView.visiblePlotMax.x];
}

- (IBAction)toggleAudio:(id)sender {
    
    if ([audioController isRunning]) {
        [audioController stopAUGraph];
    }
    else {
        [audioController startAUGraph];
    }
}

- (IBAction)toggleFilter:(id)sender {
    
    if ([audioController lpfEnabled]) {
        [audioController setLpfEnabled:false];
        [audioController setFilterbankEnabled:true];
        [kObjectFDScopeView setVisibilityAtIndex:fdFilterIdx visible:true];
    }
    else {
        [audioController setLpfEnabled:true];
        [audioController setFilterbankEnabled:false];
        [kObjectFDScopeView setVisibilityAtIndex:fdFilterIdx visible:false];
    }
}

- (IBAction)toggleModulation:(id)sender {
    
    if ([audioController modulationEnabled])
        [audioController setModulationEnabled:false];
    
    else
        [audioController setModulationEnabled:true];
}

- (IBAction)toggleDelay:(id)sender {
    
    if ([audioController delayEnabled])
        [audioController setDelayEnabled:false];
    
    else
        [audioController setDelayEnabled:true];
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















