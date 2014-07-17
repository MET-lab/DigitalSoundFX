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
    [[self view] setBackgroundColor:[UIColor whiteColor]];
    
    /* ----------------------------------------------------- */
    /* == Setup for time and frequency domain scope views == */
    /* ----------------------------------------------------- */
    [tdScopeView setPlotResolution:456];
    [tdScopeView setHardXLim:-0.00001 max:kMaxDelayTime];
    [tdScopeView setVisibleXLim:-0.00001 max:1024/kAudioSampleRate];
    [tdScopeView setPlotUnitsPerXTick:0.005];
    [tdScopeView setMinPlotRange:CGPointMake(1024/kAudioSampleRate/2, 0.1)];
    [tdScopeView setMaxPlotRange:CGPointMake(kMaxDelayTime, 2.0)];
    [tdScopeView setXGridAutoScale:true];
    [tdScopeView setYGridAutoScale:true];
    [tdScopeView setXPinchZoomEnabled:false];
    [tdScopeView setYPinchZoomEnabled:false];
    [tdScopeView setXLabelPosition:kMETScopeViewXLabelsOutsideAbove];
    [tdScopeView setYLabelPosition:kMETScopeViewYLabelsOutsideLeft];
    
    /* Allocate subviews for wet (pre-processing) and dry (post-processing) waveforms */
    tdDryIdx = [tdScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    tdWetIdx = [tdScopeView addPlotWithColor:[UIColor  redColor] lineWidth:2.0];
    
    /* Allocate subviews for the clipping amplitude */
    tdClipIdxLow = [tdScopeView addPlotWithResolution:10 color:[UIColor greenColor] lineWidth:2.0];
    tdClipIdxHigh = [tdScopeView addPlotWithResolution:10 color:[UIColor greenColor] lineWidth:2.0];
    
    [fdScopeView setPlotResolution:fdScopeView.frame.size.width];
    [fdScopeView setUpFFTWithSize:kFFTSize];      // Set up FFT before setting FD mode
    [fdScopeView setDisplayMode:kMETScopeViewFrequencyDomainMode];
    [fdScopeView setHardXLim:0.0 max:10000];       // Set bounds after FD mode
    [fdScopeView setVisibleXLim:0.0 max:9300];
    [fdScopeView setPlotUnitsPerXTick:2000];
    [fdScopeView setXGridAutoScale:true];
    [fdScopeView setYGridAutoScale:true];
    [fdScopeView setXPinchZoomEnabled:false];
    [fdScopeView setYPinchZoomEnabled:false];
    [fdScopeView setXLabelPosition:kMETScopeViewXLabelsOutsideBelow];
    [fdScopeView setYLabelPosition:kMETScopeViewYLabelsOutsideLeft];
    [fdScopeView setAxisScale:kMETScopeViewAxesSemilogY];
    [fdScopeView setHardYLim:-80 max:0];
    [fdScopeView setPlotUnitsPerYTick:20];
    [fdScopeView setAxesOn:true];
    
    /* Get the FFT frequencies for the FD scope */
    plotFreqs = (float *)malloc(fdScopeView.frame.size.width * sizeof(float));
    [self linspace:fdScopeView.minPlotMin.x
               max:fdScopeView.maxPlotMax.x
       numElements:fdScopeView.frame.size.width
             array:plotFreqs];
    
    /* Allocate subviews for wet (pre-processing) and dry (post-processing) waveforms */
    fdDryIdx = [fdScopeView addPlotWithColor:[UIColor blueColor] lineWidth:2.0];
    fdWetIdx = [fdScopeView addPlotWithColor:[UIColor  redColor] lineWidth:2.0];
    
    /* Create a scope view for the delay signal. Don't add to main view yet */
    delayView = [[METScopeView alloc] initWithFrame:tdScopeView.frame];
    [delayView setBackgroundColor:[UIColor clearColor]];
    
    /* Allocate a subview for the delay signal */
    delayIdx = [delayView addPlotWithResolution:200 color:[UIColor colorWithRed:0.5 green:0 blue:0 alpha:1] lineWidth:1.0];
    
    /* ------------------------------------ */
    /* === External gesture recognizers === */
    /* ------------------------------------ */
    
    tdPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDPinch:)];
    [tdScopeView addGestureRecognizer:tdPinchRecognizer];
    fdPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleFDPinch:)];
    [fdScopeView addGestureRecognizer:fdPinchRecognizer];
    
    tdPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDPan:)];
    [tdPanRecognizer setMinimumNumberOfTouches:1];
    [tdPanRecognizer setMaximumNumberOfTouches:1];
    [tdScopeView addGestureRecognizer:tdPanRecognizer];
    fdPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleFDPan:)];
    [fdPanRecognizer setMinimumNumberOfTouches:1];
    [fdPanRecognizer setMaximumNumberOfTouches:1];
    [fdScopeView addGestureRecognizer:fdPanRecognizer];
    
    tdTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTDTap:)];
    [tdTapRecognizer setNumberOfTapsRequired:2];
    [tdScopeView addGestureRecognizer:tdTapRecognizer];
    
    /* ----------------- */
    /* == Audio Setup == */
    /* ----------------- */
    audioController = [[AudioController alloc] init];
    
    /* Distortion */
    [audioController setDistortionEnabled:false];
    
    /* Filters */
    [audioController setLpfEnabled:false];
    [audioController setHpfEnabled:false];
    [audioController rescaleFilters:fdScopeView.visiblePlotMin.x max:fdScopeView.visiblePlotMax.x];
    
    /* Modulation */
    [audioController setModulationEnabled:false];
    [audioController setModFrequency:440.0f];
    
    /* Delay */
    [audioController setDelayEnabled:false];
    
    /* Gains */
    [self updatePreGain:self];
    [self updatePostGain:self];
    
    /* ----------------------------- */
    /* == Setup for delay control == */
    /* ----------------------------- */
    
    /* Create a subview over the right-most 15th of the time domain scope view */
    CGRect delayRegionFrame;
    delayRegionFrame.size.width = tdScopeView.frame.size.width / 7.1;
    delayRegionFrame.size.height = tdScopeView.frame.size.height;
    delayRegionFrame.origin.x = 0;
    delayRegionFrame.origin.y = 0;
    delayRegionView = [[UIView alloc] initWithFrame:delayRegionFrame];
    [delayRegionView setBackgroundColor:[UIColor blackColor]];
    [delayRegionView setAlpha:0.05];
    [tdScopeView addSubview:delayRegionView];
    
    /* Add a tap gesture recognizer to enable delay */
    delayTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDelayTap:)];
    [delayTapRecognizer setNumberOfTapsRequired:1];
    [delayRegionView addGestureRecognizer:delayTapRecognizer];
    
    /* -------------------------------------------- */
    /* == Set up UIView to show delay parameters == */
    /* -------------------------------------------- */
    
    CGRect delayParameterFrame = CGRectMake(50, 50, 150, 100);
    delayParameterView = [[UIView alloc] initWithFrame:delayParameterFrame];
    [delayParameterView setBackgroundColor:[UIColor lightGrayColor]];
    [delayParameterView setAlpha:0.5];
    
    CGRect labelFrame = CGRectMake(10, 20, 65, 20);
    UILabel *timeParameter = [[UILabel alloc] initWithFrame:labelFrame];
    [timeParameter setText:@"  Time: "];
    [timeParameter setTextAlignment:NSTextAlignmentRight];
    [delayParameterView addSubview:timeParameter];
    
    CGRect valueFrame = labelFrame;
    valueFrame.origin.x += labelFrame.size.width + 20;
    delayTimeValue = [[UILabel alloc] initWithFrame:valueFrame];
    [delayTimeValue setText:[NSString stringWithFormat:@"%3.2f", 0.0]];
    [delayTimeValue setTextAlignment:NSTextAlignmentLeft];
    [delayParameterView addSubview:delayTimeValue];
    
    labelFrame.origin.y += labelFrame.size.height * 2;
    UILabel *amountParameter = [[UILabel alloc] initWithFrame:labelFrame];
    [amountParameter setText:@"Amount: "];
    [amountParameter setTextAlignment:NSTextAlignmentRight];
    [delayParameterView addSubview:amountParameter];
    
    valueFrame.origin.y += labelFrame.size.height * 2;
    delayAmountValue = [[UILabel alloc] initWithFrame:valueFrame];
    [delayAmountValue setText:[NSString stringWithFormat:@"%3.2f", 0.15/tdScopeView.visiblePlotMax.y]];
    [delayAmountValue setTextAlignment:NSTextAlignmentLeft];
    [delayParameterView addSubview:delayAmountValue];
    
    /* ------------------------------------------ */
    /* == Setup for clipping threshold control == */
    /* ------------------------------------------ */
    
    /* Create a subview over the right-most 15th of the time domain scope view */
    CGRect pinchRegionFrame;
    pinchRegionFrame.size.width = tdScopeView.frame.size.width / 7.1;
    pinchRegionFrame.size.height = tdScopeView.frame.size.height;
    pinchRegionFrame.origin.x = tdScopeView.frame.size.width - pinchRegionFrame.size.width;
    pinchRegionFrame.origin.y = 0;
    distPinchRegionView = [[PinchRegionView alloc] initWithFrame:pinchRegionFrame];
    [distPinchRegionView setBackgroundColor:[[UIColor greenColor] colorWithAlphaComponent:0.05]];
    [distPinchRegionView setLinesVisible:false];
    CGPoint pix = [tdScopeView plotScaleToPixel:CGPointMake(0.0, audioController->clippingAmplitude)];
    [distPinchRegionView setPixelHeightFromCenter:pix.y-distPinchRegionView.frame.size.height/2];
    [tdScopeView addSubview:distPinchRegionView];
    
    /* Add a tap gesture recognizer to enable clipping */
    distCutoffTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDistCutoffTap:)];
    [distCutoffTapRecognizer setNumberOfTapsRequired:1];
    [distPinchRegionView addGestureRecognizer:distCutoffTapRecognizer];
    
    /* Add a pinch recognizer and set the callback to update the clipping amplitude */
    distCutoffPinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handleDistCutoffPinch:)];
    [distPinchRegionView addGestureRecognizer:distCutoffPinchRecognizer];
    [distCutoffPinchRecognizer setEnabled:false];
    
    /* -------------------------------------------- */
    /* == Setup for modulation frequency control == */
    /* -------------------------------------------- */
    
    modIdx = [fdScopeView addPlotWithColor:[UIColor greenColor] lineWidth:2.0];
    
    CGRect modRegionFrame;
    modRegionFrame.size.width = fdScopeView.frame.size.width;
    modRegionFrame.size.height = fdScopeView.frame.size.height / 4;
    modRegionFrame.origin.x = fdScopeView.frame.size.width - modRegionFrame.size.width;
    modRegionFrame.origin.y = fdScopeView.frame.size.height - modRegionFrame.size.height;
    modFreqPanRegionView = [[UIView alloc] initWithFrame:modRegionFrame];
    [modFreqPanRegionView setBackgroundColor:[UIColor greenColor]];
    [modFreqPanRegionView setAlpha:0.05];
    [fdScopeView addSubview:modFreqPanRegionView];
    
    /* Add a tap gesture recognizer to enable modulation */
    modFreqTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleModFreqTap:)];
    [modFreqTapRecognizer setNumberOfTapsRequired:1];
    [modFreqPanRegionView addGestureRecognizer:modFreqTapRecognizer];
    
    /* Add a pan gesture recognizer for controlling the modulation frequency */
    modFreqPanRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleModFreqPan:)];
    [modFreqPanRegionView addGestureRecognizer:modFreqPanRecognizer];
    
    /* ------------------------------ */
    /* == Setup for filter control == */
    /* ------------------------------ */
    
    /* Create a subview over at the left side of the spectrum */
    CGRect hpfTapRegionFrame;
    hpfTapRegionFrame.size.width = fdScopeView.frame.size.width / 7.1;
    hpfTapRegionFrame.size.height = fdScopeView.frame.size.height - modRegionFrame.size.height;
    hpfTapRegionFrame.origin.x = 0;
    hpfTapRegionFrame.origin.y = 0;
    hpfTapRegionView = [[FilterTapRegionView alloc] initWithFrame:hpfTapRegionFrame];
    [hpfTapRegionView setBackgroundColor:[UIColor clearColor]];
    [hpfTapRegionView setFillColor:[UIColor blackColor]];
    [hpfTapRegionView setAlpha:0.05];
    [fdScopeView addSubview:hpfTapRegionView];
    
    /* Add a tap gesture recognizer to enable/disable the HPF */
    hpfTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleHPF:)];
    [hpfTapRecognizer setNumberOfTapsRequired:1];
    [hpfTapRegionView addGestureRecognizer:hpfTapRecognizer];
    
    /* Create a subview over at the right side of the spectrum */
    CGRect lpfTapRegionFrame;
    lpfTapRegionFrame.size.width = fdScopeView.frame.size.width / 7.1;
    lpfTapRegionFrame.size.height = fdScopeView.frame.size.height - modRegionFrame.size.height;
    lpfTapRegionFrame.origin.x = fdScopeView.frame.size.width - lpfTapRegionFrame.size.width;
    lpfTapRegionFrame.origin.y = 0;
    lpfTapRegionView = [[FilterTapRegionView alloc] initWithFrame:lpfTapRegionFrame];
    [lpfTapRegionView setBackgroundColor:[UIColor clearColor]];
    [lpfTapRegionView setFillColor:[UIColor blackColor]];
    [lpfTapRegionView setAlpha:0.05];
    [fdScopeView addSubview:lpfTapRegionView];
    
    /* Add a tap gesture recognizer to enable/disable the HPF */
    lpfTapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleLPF:)];
    [lpfTapRecognizer setNumberOfTapsRequired:1];
    [lpfTapRegionView addGestureRecognizer:lpfTapRecognizer];
    
    /* Make a "knee" shaped fill region for the filter cutoff views */
    int nPoints = 100;
    float fillRegionX[nPoints];
    CGPoint fillRegion[nPoints];
    
    [self linspace:0 max:hpfTapRegionFrame.size.width numElements:nPoints-1 array:fillRegionX];
    for (int i = 0; i < nPoints-1; i++) {
        fillRegion[i].x = fillRegionX[i];
        fillRegion[i].y = 500.0f / fillRegionX[i] - fillRegionX[i] * 5.0f / hpfTapRegionFrame.size.width;
    }
    fillRegion[nPoints-1].x = hpfTapRegionFrame.origin.x;
    fillRegion[nPoints-1].y = hpfTapRegionFrame.origin.y;
    [hpfTapRegionView setFillRegion:fillRegion numPoints:nPoints];
    
    /* Reverse direction of y coordinates for the LPF */
    CGPoint temp;
    for (int i = 0, j = nPoints; i < nPoints/2; i++, j--) {
        temp.y = fillRegion[i].y;
        fillRegion[i].y = fillRegion[j].y;
        fillRegion[j].y = temp.y;
    }
    fillRegion[nPoints-1].x = hpfTapRegionFrame.size.width;
    fillRegion[nPoints-1].y = 0.0f;
    [lpfTapRegionView setFillRegion:fillRegion numPoints:nPoints];
    
    
    
    /* Update the scope views on timers by querying AudioController's wet/dry signal buffers */
    [self setTDUpdateRate:kScopeUpdateRate];
    [self setFDUpdateRate:kScopeUpdateRate];
    
    delayOn = false;
}

- (void)setTDUpdateRate:(float)rate {
    
    if ([tdScopeClock isValid])
        [tdScopeClock invalidate];
        
    tdScopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                    target:self
                                                  selector:@selector(updateTDScope)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)setFDUpdateRate:(float)rate {
    
    if ([fdScopeClock isValid])
        [fdScopeClock invalidate];
    
    fdScopeClock = [NSTimer scheduledTimerWithTimeInterval:rate
                                                    target:self
                                                  selector:@selector(updateFDScope)
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)updateTDScope {
    
    int startIdx = fmax(tdScopeView.visiblePlotMin.x, 0.0) * kAudioSampleRate;
    int endIdx = tdScopeView.visiblePlotMax.x * kAudioSampleRate;
    int visibleBufferLength = endIdx - startIdx;
    
    /* Update the plots */
    if (!tdHold && ![tdScopeView isCurrentlyZooming]) {
        
        /* Get buffer of times for each sample */
        plotTimes = (float *)malloc(visibleBufferLength * sizeof(float));
        [self linspace:fmax(tdScopeView.visiblePlotMin.x, 0.0)
                   max:tdScopeView.visiblePlotMax.x
           numElements:visibleBufferLength
                 array:plotTimes];
        
        /* Allocate wet/dry signal buffers */
        float *dryYBuffer = (float *)malloc(visibleBufferLength * sizeof(float));
        float *wetYBuffer = (float *)malloc(visibleBufferLength * sizeof(float));
        
        /* Get current visible samples from the audio controller */
        [audioController getInputBuffer:dryYBuffer withLength:visibleBufferLength];
        [audioController getOutputBuffer:wetYBuffer withLength:visibleBufferLength];
        
        [tdScopeView setPlotDataAtIndex:tdDryIdx
                             withLength:visibleBufferLength
                                  xData:plotTimes
                                  yData:dryYBuffer];
        
        [tdScopeView setPlotDataAtIndex:tdWetIdx
                             withLength:visibleBufferLength
                                  xData:plotTimes
                                  yData:wetYBuffer];
        
        free(plotTimes);
        free(dryYBuffer);
        free(wetYBuffer);
    }
}

- (void)updateFDScope {

    if (!fdHold && ![fdScopeView isCurrentlyZooming]) {
        
        /* Get buffer of times for each sample */
        plotTimes = (float *)malloc(kAudioBufferSize * sizeof(float));
        [self linspace:0.0 max:(kAudioBufferSize * kAudioSampleRate) numElements:kAudioBufferSize array:plotTimes];
        
        /* Allocate wet/dry signal buffers */
        float *dryYBuffer = (float *)malloc(kAudioBufferSize * sizeof(float));
        float *wetYBuffer = (float *)malloc(kAudioBufferSize * sizeof(float));
        
        /* Get current visible samples from the audio controller */
        [audioController getInputBuffer:dryYBuffer withLength:kAudioBufferSize];
        [audioController getOutputBuffer:wetYBuffer withLength:kAudioBufferSize];
        
        [fdScopeView setPlotDataAtIndex:fdDryIdx
                             withLength:kAudioBufferSize
                                  xData:plotTimes
                                  yData:dryYBuffer];
        
        [fdScopeView setPlotDataAtIndex:fdWetIdx
                             withLength:kAudioBufferSize
                                  xData:plotTimes
                                  yData:wetYBuffer];
        free(plotTimes);
        free(dryYBuffer);
        free(wetYBuffer);
    }
}

- (void)plotModFreq {
    
    /* Get buffer of times for each sample */
    plotTimes = (float *)malloc(kAudioBufferSize * sizeof(float));
    [self linspace:0.0 max:(kAudioBufferSize * kAudioSampleRate) numElements:kAudioBufferSize array:plotTimes];
    
    float *modYBuffer = (float *)malloc(kAudioBufferSize * sizeof(float));
    [audioController getModulationBuffer:modYBuffer withLength:kAudioBufferSize];
    
    [fdScopeView setPlotDataAtIndex:modIdx
                         withLength:kAudioBufferSize
                              xData:plotTimes
                              yData:modYBuffer];
    free(plotTimes);
    free(modYBuffer);
}

- (void)handleTDPinch:(UIPinchGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save the initial pinch scale */
        tdPreviousPinchScale = sender.scale;
        
        /* Stop time domain plot and throttle spectrum plot */
        if (!delayOn)
            tdHold = true;
        
        float rate = 1000 * [fdScopeClock timeInterval];
        [self setFDUpdateRate:rate];
        
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Restart time domain plot and revert spectrum update rate to the default */
        if (!delayOn)
            tdHold = false;
        
        [self setFDUpdateRate:kScopeUpdateRate];
        
        /* Update the clipping threshold plot */
        if (audioController.distortionEnabled)
            [self plotClippingThreshold];
    }
    
    else {
    
        /* Scale the time axis upper bound */
        CGFloat scaleChange;
        scaleChange = sender.scale - tdPreviousPinchScale;
        
        if (!delayOn) {
            [tdScopeView setVisibleXLim:tdScopeView.visiblePlotMin.x
                                    max:(tdScopeView.visiblePlotMax.x - scaleChange*tdScopeView.visiblePlotMax.x)];
        }
        else {
            
            /* Get the current feedback value as a function of the plot bounds */
            float feedback = fminf(kDelayFeedbackScalar / delayView.visiblePlotMax.y, kDelayMaxFeedback);
            
            /* Set the label text */
            [delayAmountValue setText:[NSString stringWithFormat:@"%3.2f", feedback]];
            
            if (feedback < kDelayMaxFeedback || scaleChange < 0) {
                [delayView setVisibleYLim:(delayView.visiblePlotMin.y - scaleChange*delayView.visiblePlotMin.y) max:(delayView.visiblePlotMax.y - scaleChange*delayView.visiblePlotMax.y)];
            }
        }
    
        tdPreviousPinchScale = sender.scale;
    }
}

- (void)handleFDPinch:(UIPinchGestureRecognizer *)sender {
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save the initial pinch scale */
        fdPreviousPinchScale = sender.scale;
        
        /* Stop the spectrum plot updates */
        fdHold = true;
        return;
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Restart the spectrum plot updates */
        fdHold = false;
    }
    
    else {
        
        /* Scale the frequency axis upper bound */
        CGFloat scaleChange;
        scaleChange = sender.scale - fdPreviousPinchScale;
        
        [fdScopeView setVisibleXLim:fdScopeView.visiblePlotMin.x
                                max:(fdScopeView.visiblePlotMax.x - scaleChange*fdScopeView.visiblePlotMax.x)];
        
        /* Set the LPF and HPF to roll off at the updated plot bounds */
        [audioController rescaleFilters:fdScopeView.visiblePlotMin.x max:fdScopeView.visiblePlotMax.x];
        
        fdPreviousPinchScale = sender.scale;
    }
}

- (void)handleTDPan:(UIPanGestureRecognizer *)sender {
    
    /* Location of current touch */
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save initial touch location */
        tdPreviousPanLoc = touchLoc;
        
        /* Stop the time-domain plot updates */
        if (!delayOn)
            tdHold = true;
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded && !delayOn) {
        
        /* Restart time-domain plot updates */
        tdHold = false;
        
        /* Update the clipping threshold plot */
        [self plotClippingThreshold];
    }
    
    else {
        
        /* Get the relative change in location; convert to plot units (time) */
        CGPoint locChange;
        locChange.x = tdPreviousPanLoc.x - touchLoc.x;
        locChange.y = tdPreviousPanLoc.y - touchLoc.y;
        
        /* Shift the plot bounds in time */
        if (!delayOn) {
            locChange.x *= tdScopeView.unitsPerPixel.x;
            [tdScopeView setVisibleXLim:(tdScopeView.visiblePlotMin.x + locChange.x)
                                    max:(tdScopeView.visiblePlotMax.x + locChange.x)];
        }
        else {
            locChange.x *= delayView.unitsPerPixel.x;
            [delayView setVisibleXLim:(delayView.visiblePlotMin.x + locChange.x)
                                  max:(delayView.visiblePlotMax.x + locChange.x)];
            
            /* Get the delay time as the difference between the bounds of the delay scope and the TD Scope */
            float delayTime = tdScopeView.visiblePlotMin.x - delayView.visiblePlotMin.x;
            
            /* Set the label text */
            [delayTimeValue setText:[NSString stringWithFormat:@"%3.2f", delayTime]];
        }
        
        tdPreviousPanLoc = touchLoc;
    }
}

- (void)handleFDPan:(UIPanGestureRecognizer *)sender {
    
    /* Location of current touch */
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save initial touch location */
        fdPreviousPanLoc = touchLoc;
        
        /* Throttle time and spectrum plot updates */
        float rate = 500 * (tdScopeView.visiblePlotMax.x - tdScopeView.visiblePlotMin.x) * [tdScopeClock timeInterval] + 30 * [tdScopeClock timeInterval];
        [self setTDUpdateRate:rate];
        [self setFDUpdateRate:rate/2];
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
        /* Return time and spectrum plot updates to default rate */
        [self setTDUpdateRate:kScopeUpdateRate];
        [self setFDUpdateRate:kScopeUpdateRate];
    }
    
    else {
        
        /* Get the relative change in location; convert to plot units (frequency) */
        CGPoint locChange;
        locChange.x = fdPreviousPanLoc.x - touchLoc.x;
        locChange.y = fdPreviousPanLoc.y - touchLoc.y;
        locChange.x *= fdScopeView.unitsPerPixel.x;
        
        /* Shift the plot bounds in frequency */
        [fdScopeView setVisibleXLim:(fdScopeView.visiblePlotMin.x + locChange.x)
                                max:(fdScopeView.visiblePlotMax.x + locChange.x)];
        
        /* Set the LPF and HPF to roll off at the updated plot bounds */
        [audioController rescaleFilters:fmax(fdScopeView.visiblePlotMin.x, 20.0) max:fdScopeView.visiblePlotMax.x];

        fdPreviousPanLoc = touchLoc;
    }
}

- (void)handleTDTap:(UITapGestureRecognizer *)sender {
    
    if ([audioController isRunning]) {
        [audioController stopAUGraph];
        [inputEnableSwitch setOn:false animated:true];
    }
    else {
        [audioController startAUGraph];
        [inputEnableSwitch setOn:true animated:true];
    }
}

- (void)handleDelayTap:(UITapGestureRecognizer *)sender {
    
    /* Note: delayOn is a flag indicating that everything is paused and we're modifying delay parameters. audioController.delayEnabled is the flag that indicates delay is being applied to the audio */
    if (delayOn) {
        
        delayOn = tdHold = fdHold = false;
        [tdScopeView setAlpha:1.0];
        
        /* Get the delay time as the difference between the bounds of the delay scope and the TD Scope */
        float delayTime = tdScopeView.visiblePlotMin.x - delayView.visiblePlotMin.x;
        [audioController->circularBuffer setSampleDelayForTap:0 sampleDelay:delayTime*kAudioSampleRate];
        
        /* Get the current feedback value as a function of the plot bounds */
        float feedback = fminf(kDelayFeedbackScalar / delayView.visiblePlotMax.y, kDelayMaxFeedback);
        
        audioController->tapGains[0] = feedback;
        
        /* Enable */
        if (delayTime > 0.0f) {
            [audioController setDelayEnabled:true];
            [delayRegionView setAlpha:0.15];
        }
        else {
            [audioController setDelayEnabled:true];
            [delayRegionView setAlpha:0.05];
        }
        
        /* Remove the TD gesture recognizers from the delay scope and put them on the TD Scope */
        [delayView removeGestureRecognizer:delayTapRecognizer];
        [delayView removeGestureRecognizer:tdPinchRecognizer];
        [delayView removeGestureRecognizer:tdPanRecognizer];
        [delayRegionView addGestureRecognizer:delayTapRecognizer];
        [tdScopeView addGestureRecognizer:tdPinchRecognizer];
        [tdScopeView addGestureRecognizer:tdPanRecognizer];
        
        /* Remove the delay scope from the main view */
        [delayView performSelectorOnMainThread:@selector(removeFromSuperview) withObject:nil waitUntilDone:false];
        
        /* Put the distortion pinch region back on the time-domain plot */
        [tdScopeView addSubview:distPinchRegionView];
        
        /* Remove the delay parameter view */
        [delayParameterView removeFromSuperview];
    }
    
    else {
        
        delayOn = tdHold = fdHold = true;
        [tdScopeView setAlpha:0.5];
        
        /* Copy settings from current time domain scope */
        [delayView setPlotResolution:tdScopeView.plotResolution];
        [delayView setHardXLim:-tdScopeView.maxPlotMax.x max:tdScopeView.maxPlotMax.x];
        [delayView setHardYLim:-10.0 max:10.0];
        [delayView setVisibleXLim:tdScopeView.visiblePlotMin.x max:tdScopeView.visiblePlotMax.x];
        [delayView setVisibleYLim:tdScopeView.visiblePlotMin.y max:tdScopeView.visiblePlotMax.y];
        [delayView setMinPlotRange:CGPointMake(tdScopeView.minPlotRange.x, 0.1)];
        [delayView setMaxPlotRange:CGPointMake(tdScopeView.maxPlotRange.x, 20.0)];
        [delayView setXPinchZoomEnabled:false];
        [delayView setYPinchZoomEnabled:false];
        [delayView setAxesOn:false];
        [delayView setGridOn:false];
        [delayView setLabelsOn:false];
        
        /* Copy the TD Scope's current output buffer for the delay plot */
        float *delayXBuffer = (float *)malloc(tdScopeView.plotResolution * sizeof(float));
        float *delayYBuffer = (float *)malloc(tdScopeView.plotResolution * sizeof(float));
        [tdScopeView getPlotDataAtIndex:tdWetIdx withLength:tdScopeView.plotResolution xData:delayXBuffer yData:delayYBuffer];
        
        /* Plot */
        [delayView setPlotDataAtIndex:delayIdx
                           withLength:tdScopeView.plotResolution
                                xData:delayXBuffer
                                yData:delayYBuffer];
        free(delayXBuffer);
        free(delayYBuffer);
        
        /* If the TD Scope is in fill mode, set it for the delay scope */
        [delayView setFillMode:[tdScopeView getFillModeAtIndex:tdWetIdx] atIndex:delayIdx];
        
        /* Add the delay scope to the main view */
        [[self view] addSubview:delayView];
        
        /* Remove the TD gesture recognizers from the TD Scope and put them on the delay scope */
        [delayRegionView removeGestureRecognizer:delayTapRecognizer];
        [tdScopeView removeGestureRecognizer:tdPinchRecognizer];
        [tdScopeView removeGestureRecognizer:tdPanRecognizer];
        [delayView addGestureRecognizer:delayTapRecognizer];
        [delayView addGestureRecognizer:tdPinchRecognizer];
        [delayView addGestureRecognizer:tdPanRecognizer];
        
        tdPreviousPinchScale = 1.0f;
        tdPreviousPanLoc = [sender locationInView:sender.view];
        
        /* Add the delay parameter view */
        [delayView addSubview:delayParameterView];
        
        /* Make sure the distortion pinch region is on top so we can still use it */
        [delayView addSubview:distPinchRegionView];
        
        /* Get the delay time as the difference between the bounds of the delay scope and the TD Scope */
        float delayTime = tdScopeView.visiblePlotMin.x - delayView.visiblePlotMin.x;
        
        /* Set the label text */
        [delayTimeValue setText:[NSString stringWithFormat:@"%3.2f", delayTime]];
        
        /* Get the current feedback value as a function of the plot bounds */
        float feedback = fminf(kDelayFeedbackScalar / delayView.visiblePlotMax.y, kDelayMaxFeedback);
        
        /* Set the label text */
        [delayAmountValue setText:[NSString stringWithFormat:@"%3.2f", feedback]];
    }
    
    CGRect flashFrame = delayRegionView.frame;
    flashFrame.origin.x += tdScopeView.frame.origin.x;
    flashFrame.origin.y += tdScopeView.frame.origin.y;
    [self flashInFrame:flashFrame];
}

- (void)handleDistCutoffTap:(UITapGestureRecognizer *)sender {
    
    if (audioController.distortionEnabled) {
        [audioController setDistortionEnabled:false];
        [tdScopeView setVisibilityAtIndex:tdClipIdxLow visible:false];
        [tdScopeView setVisibilityAtIndex:tdClipIdxHigh visible:false];
        [distCutoffPinchRecognizer setEnabled:false];
        [distPinchRegionView setBackgroundColor:[[UIColor greenColor] colorWithAlphaComponent:0.05]];
        [distPinchRegionView setLinesVisible:false];
    }
    
    else {
        [audioController setDistortionEnabled:true];
        [self plotClippingThreshold];
        [tdScopeView setVisibilityAtIndex:tdClipIdxLow visible:true];
        [tdScopeView setVisibilityAtIndex:tdClipIdxHigh visible:true];
        [distCutoffPinchRecognizer setEnabled:true];
        [distPinchRegionView setBackgroundColor:[[UIColor greenColor] colorWithAlphaComponent:0.15]];
        [distPinchRegionView setLinesVisible:true];
    }
    
    CGRect flashFrame = distPinchRegionView.frame;
    flashFrame.origin.x += tdScopeView.frame.origin.x;
    flashFrame.origin.y += tdScopeView.frame.origin.y;
    [self flashInFrame:flashFrame];
}

- (void)handleDistCutoffPinch:(UIPinchGestureRecognizer *)sender {

    /* Reset the previous scale if the gesture began */
    if(sender.state == UIGestureRecognizerStateBegan)
        previousPinchScale = 1.0;
    
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
    [self plotClippingThreshold];
    
    /* Convert the clipping amplitude to pixels for the pinch region view */
    CGPoint pix = [tdScopeView plotScaleToPixel:CGPointMake(0.0, audioController->clippingAmplitude)];
    pix.y -= distPinchRegionView.frame.size.height/2.0;
    [distPinchRegionView setPixelHeightFromCenter:pix.y];
}

- (void)handleModFreqTap:(UITapGestureRecognizer *)sender {
    
    if (audioController.modulationEnabled) {
        [audioController setModulationEnabled:false];
        [fdScopeView setVisibilityAtIndex:modIdx visible:false];
        [modFreqPanRecognizer setEnabled:false];
        [modFreqPanRegionView setAlpha:0.05];
    }
    
    else {
        [audioController setModulationEnabled:true];
        [fdScopeView setVisibilityAtIndex:modIdx visible:true];
        [modFreqPanRecognizer setEnabled:true];
        [modFreqPanRegionView setAlpha:0.15];
        
        /* If the modulation frequency is beyond the plot bounds, put it in the center */
        if (audioController->modFreq < fdScopeView.visiblePlotMin.x ||
            audioController->modFreq > fdScopeView.visiblePlotMax.x)
            [audioController setModFrequency:(fdScopeView.visiblePlotMax.x - fdScopeView.visiblePlotMin.x)];
        
        [self plotModFreq];
    }
    
    CGRect flashFrame = modFreqPanRegionView.frame;
    flashFrame.origin.x += fdScopeView.frame.origin.x;
    flashFrame.origin.y += fdScopeView.frame.origin.y;
    [self flashInFrame:flashFrame];
}

- (void)handleModFreqPan:(UIPanGestureRecognizer *)sender {
    
    /* Location of current touch */
    CGPoint touchLoc = [sender locationInView:sender.view];
    
    if (sender.state == UIGestureRecognizerStateBegan) {
        
        /* Save initial touch location */
        modFreqPreviousPanLoc = touchLoc;
    }
    
    else if (sender.state == UIGestureRecognizerStateEnded) {
        
    }
    
    else {
        
        CGPoint locChange;
        locChange.x = modFreqPreviousPanLoc.x - touchLoc.x;
        locChange.y = modFreqPreviousPanLoc.y - touchLoc.y;
        
        locChange.x *= fdScopeView.unitsPerPixel.x;
        locChange.y *= fdScopeView.unitsPerPixel.y;
        
        float newModFreq = audioController->modFreq - locChange.x;
        
        if (newModFreq > fdScopeView.visiblePlotMin.x && newModFreq < fdScopeView.visiblePlotMax.x) {
            
            [audioController setModFrequency:newModFreq];
            
            [self plotModFreq];
        }
        
        modFreqPreviousPanLoc = touchLoc;
    }
}

- (void)plotClippingThreshold {
    
    float xx[] = {tdScopeView.visiblePlotMin.x, tdScopeView.visiblePlotMax.x * 1.2};
    float yy[] = {audioController->clippingAmplitude, audioController->clippingAmplitude};
    
    /* Plot */
    [tdScopeView setPlotDataAtIndex:tdClipIdxHigh
                         withLength:2
                              xData:xx
                              yData:yy];
    
    /* Negative mirror */
    yy[0] = -audioController->clippingAmplitude;
    yy[1] = -audioController->clippingAmplitude;
    
    /* Plot */
    [tdScopeView setPlotDataAtIndex:tdClipIdxLow
                         withLength:2
                              xData:xx
                              yData:yy];
}

- (void)toggleHPF:(UITapGestureRecognizer *)sender {
    
    CGPoint touchLoc = [sender locationInView:hpfTapRegionView];
    
    float endAlpha;
    
    if (![hpfTapRegionView pointInFillRegion:touchLoc])
        return;
    
    if ([audioController hpfEnabled]) {
        [audioController setHpfEnabled:false];
        endAlpha = 0.05;
    }
    else {
        [audioController setHpfEnabled:true];
        endAlpha = 0.15;
    }
    
    [hpfTapRegionView setAlpha:0.5f];
    [UIView animateWithDuration:0.5f
                     animations:^{
                         [hpfTapRegionView setAlpha:endAlpha];
                     }
                     completion:^(BOOL finished) {
                         [hpfTapRegionView setAlpha:endAlpha];
                     }
     ];
}

- (void)toggleLPF:(UITapGestureRecognizer *)sender {
    
    CGPoint touchLoc = [sender locationInView:lpfTapRegionView];
    
    float endAlpha;
    
    if (![lpfTapRegionView pointInFillRegion:touchLoc])
        return;
    
    if ([audioController lpfEnabled]) {
        [audioController setLpfEnabled:false];
        endAlpha = 0.05;
    }
    else {
        [audioController setLpfEnabled:true];
        endAlpha = 0.15;
    }
    
    [lpfTapRegionView setAlpha:0.5f];
    [UIView animateWithDuration:0.5f
                     animations:^{
                         [lpfTapRegionView setAlpha:endAlpha];
                     }
                     completion:^(BOOL finished) {
                         [lpfTapRegionView setAlpha:endAlpha];
                     }
     ];
}

- (IBAction)toggleInput:(id)sender {
    
    if ([audioController isRunning]) {
        [audioController stopAUGraph];
    }
    else {
        [audioController startAUGraph];
    }
}

- (IBAction)toggleOutput:(id)sender {
    
    if (audioController.outputEnabled) {
        [audioController setOutputEnabled:false];
        previousPostGain = audioController->postGain;
        audioController->postGain = postGainSlider.value = 0.0;
        [postGainSlider setEnabled:false];
        [postGainSlider setAlpha:0.5];
    }
    else {
        [audioController setOutputEnabled:true];
        audioController->postGain = postGainSlider.value = previousPostGain;
        [postGainSlider setEnabled:true];
        [postGainSlider setAlpha:1.0];
    }
}

- (IBAction)updatePreGain:(id)sender {
    audioController->preGain = preGainSlider.value;
}

- (IBAction)updatePostGain:(id)sender {
    audioController->postGain = postGainSlider.value;
    printf("gain = %f\n", audioController->postGain);
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

/* Flash animation in the given rectangle */
- (void)flashInFrame:(CGRect)flashFrame {
    
    UIView *flashView = [[UIView alloc] initWithFrame:flashFrame];
    [flashView setBackgroundColor:[UIColor blackColor]];
    [flashView setAlpha:0.5f];
    [[self view] addSubview:flashView];
    [UIView animateWithDuration:0.5f
                     animations:^{
                         [flashView setAlpha:0.0f];
                     }
                     completion:^(BOOL finished) {
                         [flashView removeFromSuperview];
                     }
     ];
}

@end















