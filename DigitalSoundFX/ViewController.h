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

@interface ViewController : UIViewController <AudioControllerDelegate> {
    
    AudioController *audioController;
    
    IBOutlet METScopeView *kObjectTDScopeView;
    IBOutlet METScopeView *kObjectFDScopeView;
    
    UIView *distPinchRegionView;
    UIPinchGestureRecognizer *distCutoffPinchRecognizer;
    float previousPinchScale;
    float clippingAmplitude;
    
    IBOutlet UISlider *kObjectMasterVolSlider;
}



- (IBAction)toggleAudio:(id)sender;


@end

