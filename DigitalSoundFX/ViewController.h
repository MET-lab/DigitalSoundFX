//
//  ViewController.h
//  DigitalSoundFX
//
//  Created by Jeff Gregorio on 5/11/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "AudioController.h"
#import "METScopeView.h"
#import "EnvelopeView.h"
#import "FunctionDrawView.h"

#define kFFTSize 1024

@interface ViewController : UIViewController <METScopeViewDelegate> {
    
    /* Time/Frequency domain scopes */
    IBOutlet METScopeView *kObjectTDScopeView;
    IBOutlet METScopeView *kObjectFDScopeView;
    
    /* Waveform subview indices */
    int tdDryIdx, tdWetIdx;
    int fdDryIdx, fdWetIdx;
    int tdClipIdxLow, tdClipIdxHigh;
    int fdFilterIdx;
    
    /* Plot x-axis values (time, frequencies) */
    float *plotTimes;
    float *plotFreqs;
    
    /* Audio */
    AudioController *audioController;
    
    /* Filter drawing */
    UITapGestureRecognizer *filterDrawTapRecognizer;
    EnvelopeView *filterDrawView;
    float *filterEnvelope;
    bool filterDrawEnabled;     // Draw mode active
    bool filterPlotEnabled;     // Plot filter on FD Scope
    
    /* Filter panning */
    UIView *filterPanRegionView;
    UIPanGestureRecognizer *filterPanRecognizer;
    CGPoint previousPanTouchLoc;
    
    /* Distortion cutoff control */
    UIView *distPinchRegionView;
    UIPinchGestureRecognizer *distCutoffPinchRecognizer;
    CGFloat previousPinchScale;
    
    /* Gain controls */
    IBOutlet UISlider *kObjectPreGainSlider;
    IBOutlet UISlider *kObjectPostGainSlider;
    
    /* Modulation frequency slider */
    IBOutlet UISlider *kObjectModFreqSlider;
    
    /* Delay time slider */
    IBOutlet UISlider *kObjectDelayTimeSlider;
    IBOutlet UISlider *kObjectDelayFeedbackSlider;
}



- (IBAction)toggleAudio:(id)sender;
- (IBAction)toggleFilter:(id)sender;

@end

