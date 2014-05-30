//
//  METScopeView.h
//  METScopeViewTest
//
//  Created by Jeff Gregorio on 5/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Accelerate/Accelerate.h>

#define METScopeView_Default_PlotResolution 512
#define METScopeview_Default_MaxRefreshRate 0.02
/* Time-domain mode defaults */
#define METScopeView_Default_XMin_TD (-0.0001)
#define METScopeView_Default_XMax_TD 0.045      // For length 2048 buffer at 44.1kHz
#define METScopeView_Default_YMin_TD (-1.25)
#define METScopeView_Default_YMax_TD 1.25
#define METScopeView_Default_XTick_TD 0.01
#define METScopeView_Default_YTick_TD 0.5
#define METScopeView_Default_xLabelFormatString_TD @"%5.3f"
#define METScopeView_Default_yLabelFormatString_TD @"%3.2f"
/* Frequency-domain mode defaults */
#define METScopeView_Default_SamplingRate 44100 // For x-axis scaling
#define METScopeView_Default_XMin_FD (-20)
#define METScopeView_Default_XMax_FD 20000.0    // For sampling rate 44.1kHz
#define METScopeView_Default_YMin_FD (-0.03)
#define METScopeView_Default_YMax_FD 1.0
#define METScopeView_Default_XTick_FD 4000
#define METScopeView_Default_YTick_FD 0.25
#define METScopeView_Default_xLabelFormatString_FD @"%5.0f"
#define METScopeView_Default_yLabelFormatString_FD @"%3.2f"
/* Auto grid scaling defaults */
#define METScopeView_AutoGrid_MaxXTicksInFrame 6.0
#define METScopeView_AutoGrid_MinXTicksInFrame 4.0
#define METScopeView_AutoGrid_MaxYTicksInFrame 5.0
#define METScopeView_AutoGrid_MinYTicksInFrame 3.0

@interface METScopeView : UIView <UIGestureRecognizerDelegate> {
    
    /* Whether we're sampling a time-domain waveform or doing an FFT */
    enum DisplayMode {
        kMETScopeViewTimeDomainMode,
        kMETScopeViewFrequencyDomainMode,
    };
    
    enum DisplayMode displayMode;
    
    int plotResolution;             /* Number of frames sampled
                                       from incoming waveforms */
    
    time_t maxRefreshRate;          /* Interval at which the view 
                                       checks the update flag */
    NSTimer *updateClock;           // Timer handling plot updates
    bool doUpdate;                  // Flag to schedule updates
    
    NSMutableArray *plotData;       // Array of waveforms to plot
    NSMutableArray *plotColors;     // Colors per waveform
    NSMutableArray *lineWidths;     // Line widths per waveform
    
    NSDictionary *labelAttributes;  // Label text properties
    NSString *xLabelFormatString;
    NSString *yLabelFormatString;
    
    CGPoint visiblePlotMin;     // Visible bounds in plot units
    CGPoint visiblePlotMax;
    CGPoint minPlotMin;         // Hard limits constraining pinch zoom
    CGPoint maxPlotMax;
    
    CGPoint tickUnits;          // Grid/tick spacing in plot units
    CGPoint tickPixels;         // Grid/tick spacing in pixels
    
    CGPoint origin;             // Plot origin location in pixels
    CGPoint unitsPerPixel;      // Plot units per pixel
    
    float gridDashLengths[2];   // Length of grid line dashes
    
    /* Pinch zoom */
    UIPinchGestureRecognizer *pinchRecognizer;
    CGPoint previousPinchTouches[2];
    int previousNumPinchTouches;
    bool pinchZoomEnabled;
    
    /* Waveform tracking */
    int trackingBufferLength;
    int *trackingBuffer;        // Array of indices where waveform ~ tracking amplitude
    int trackingErrorLength;
    int trackingErrorIdx;
    float *trackingError;       // Array of tracking errors to watch for local minima
    
    /* Spectrum mode FFT parameters */
    int fftSize;                // Length of FFT, 2*nBins
    int windowSize;             // Length of Hann window
    float *inRealBuffer;        // Input buffer
    float *outRealBuffer;       // Output buffer
    float *window;              // Hann window
    float scale;                // Normalization constant
    FFTSetup fftSetup;          // vDSP FFT struct
    COMPLEX_SPLIT splitBuffer;  // Buffer holding real and complex parts
    
}

/* Note: setting properties directly doesn't schedule an update. If the view isn't being updated regularly by a callback passing new plot data, then use [METScopeView setNeedsDisplay] or the toggle methods */
@property int plotResolution;
@property bool axesOn;
@property bool gridOn;
@property bool autoScaleGrid;
@property bool autoScaleXGrid;
@property bool autoScaleYGrid;
@property bool xLabelsOn;
@property bool yLabelsOn;
@property bool pinchZoomEnabled;
@property bool pinchZoomXEnabled;
@property bool pinchZoomYEnabled;
@property bool trackingOn;
@property float trackingLevel;
@property int samplingRate;     /* Set for proper x-axis scaling in
                                   frequency domain mode (default 44.1kHz) */

@property NSString *xLabelFormatString;
@property NSString *yLabelFormatString;

@property (readonly) enum DisplayMode displayMode;
@property (readonly) CGPoint visiblePlotMin;
@property (readonly) CGPoint visiblePlotMax;
@property (readonly) CGPoint minPlotMin;
@property (readonly) CGPoint maxPlotMax;
@property (readonly) CGPoint tickUnits;

/* Set the number of points sampled from incoming waveforms and allocate a array of indices */
- (void)setPlotResolution:(int)res;

/* Initialize a vDSP FFT object */
- (void)setUpFFTWithSize:(int)size;

/* Set the display mode to time/frequency domain and automatically rescale to default limits */
- (void)setDisplayMode:(enum DisplayMode)mode;

/* Set the interval at which the view checks the update flag */
- (void)setMaxRefreshRate:(time_t)rate;

/* Hard axislimits constraining pinch zoom; schedule update */
- (void)setHardXLim:(float)xMin max:(float)xMax;
- (void)setHardYLim:(float)yMin max:(float)yMax;

/* Set the visible ranges of the axes in plot units; schedule update */
- (void)setVisibleXLim:(float)xMin max:(float)xMax;
- (void)setVisibleYLim:(float)yMin max:(float)yMax;

/* Set ticks and grid scale by specifying the input magnitude per tick/grid block; schedule update */
- (void)setPlotUnitsPerXTick:(float)xTick;
- (void)setPlotUnitsPerYTick:(float)yTick;
- (void)setPlotUnitsPerTick:(float)xTick vertical:(float)yTick;

/* Toggle axes, grid, labels; schedule update */
- (void)toggleAxes;
- (void)toggleGrid;
- (void)toggleLabels;
- (void)toggleXLabels;
- (void)toggleYLabels;

/* Toggle pinch zoom and auto grid */
- (void)togglePinchZoom;
- (void)togglePinchZoom:(char)axis;     // Specify C char 'x' or 'y'
- (void)toggleAutoGrid;
- (void)toggleAutoGrid:(char)axis;      // Specify C char 'x' or 'y'

/* Append new plot data to the array; schedule update */
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy;
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color;
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color lineWidth:(float)width;

/* Set/update plot data at a specified index in the array; schedule update */
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy;
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color;
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color lineWidth:(float)width;

/* Set/update plot color and line width for a waveform at some index */
- (void)setPlotColor:(UIColor *)color atIndex:(int)index;
- (void)setLineWidth:(float)width atIndex:(int)index;

@end
