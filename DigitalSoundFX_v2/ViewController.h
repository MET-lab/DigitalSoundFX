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
#import "FilterTapRegionView.h"
#import "PinchRegionView.h"

#define kFFTSize 1024
#define kScopeUpdateRate 0.003

#define kDelayFeedbackScalar 0.15
#define kDelayMaxFeedback 0.8

@interface ViewController : UIViewController {
    
    /* Audio */
    AudioController *audioController;
    CGFloat previousPostGain;
    
    /* Time/Frequency domain scopes */
    IBOutlet METScopeView *tdScopeView;
    IBOutlet METScopeView *fdScopeView;
    bool tdHold, fdHold;
    NSTimer *tdScopeClock;
    NSTimer *fdScopeClock;
    
    /* Delay scope */
    METScopeView *delayView;
    bool delayOn;
    
    /* Waveform subview indices */
    int tdDryIdx, tdWetIdx, delayIdx;
    int fdDryIdx, fdWetIdx, modIdx;
    int tdClipIdxLow, tdClipIdxHigh;
    
    /* Plot x-axis values (time, frequencies) */
    float *plotTimes;
    float *plotFreqs;
    
    /* Delay control */
    UIView *delayRegionView;
    UITapGestureRecognizer *delayTapRecognizer;
    UIView *delayParameterView;
    UILabel *delayTimeValue;
    UILabel *delayAmountValue;
    
    /* Distortion cutoff control */
    PinchRegionView *distPinchRegionView;
    UITapGestureRecognizer *distCutoffTapRecognizer;
    UIPinchGestureRecognizer *distCutoffPinchRecognizer;
    CGFloat previousPinchScale;
    
    /* Modulation frequency control */
    UIView *modFreqPanRegionView;
    UITapGestureRecognizer *modFreqTapRecognizer;
    UIPanGestureRecognizer *modFreqPanRecognizer;
    CGPoint modFreqPreviousPanLoc;
    
    /* Filter control */
    FilterTapRegionView *hpfTapRegionView;
    FilterTapRegionView *lpfTapRegionView;
    UITapGestureRecognizer *hpfTapRecognizer;
    UITapGestureRecognizer *lpfTapRecognizer;
    
    /* Pinch zoom controls */
    UIPinchGestureRecognizer *tdPinchRecognizer;
    CGFloat tdPreviousPinchScale;
    UIPinchGestureRecognizer *fdPinchRecognizer;
    CGFloat fdPreviousPinchScale;
    
    /* Panning controls */
    UIPanGestureRecognizer *tdPanRecognizer;
    CGPoint tdPreviousPanLoc;
    UIPanGestureRecognizer *fdPanRecognizer;
    CGPoint fdPreviousPanLoc;
    
    /* Tap recognizer for delay control */
    UITapGestureRecognizer *tdTapRecognizer;
    
    /* Gain controls */
    IBOutlet UISlider *preGainSlider;
    IBOutlet UISlider *postGainSlider;
    
    /* Switches */
    IBOutlet UISwitch *inputEnableSwitch;
    IBOutlet UISwitch *outputEnableSwitch;
}

@end

