//
//  METScopeView.m
//  METScopeViewTest
//
//  Created by Jeff Gregorio on 5/7/14.
//  Copyright (c) 2014 Jeff Gregorio. All rights reserved.
//

#import "METScopeView.h"

@implementation METScopeView

@synthesize axesOn;
@synthesize gridOn;
@synthesize autoScaleGrid;
@synthesize autoScaleXGrid;
@synthesize autoScaleYGrid;
@synthesize xLabelsOn;
@synthesize yLabelsOn;
@synthesize pinchZoomEnabled;
@synthesize pinchZoomXEnabled;
@synthesize pinchZoomYEnabled;
@synthesize trackingOn;
@synthesize trackingLevel;
@synthesize samplingRate;

@synthesize xLabelFormatString;
@synthesize yLabelFormatString;

@synthesize plotResolution;
@synthesize displayMode;
@synthesize visiblePlotMin;
@synthesize visiblePlotMax;
@synthesize minPlotMin;
@synthesize maxPlotMax;
@synthesize tickUnits;

- (id)initWithFrame:(CGRect)frame {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    self = [super initWithFrame:frame];
    
    if (self) {
        [self setDefaults];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    
    NSLog(@"%s", __PRETTY_FUNCTION__);
    
    self = [super initWithCoder:aDecoder];
    
    if (self) {
        [self setDefaults];
    }
    return self;
}

- (void)dealloc {
    
    if (trackingBuffer != NULL)
        free(trackingBuffer);
    if (trackingError != NULL)
        free(trackingError);
    if (inRealBuffer != NULL)
        free(inRealBuffer);
    if (outRealBuffer != NULL)
        free(outRealBuffer);
    if (window != NULL)
        free(window);
}

- (void)setDefaults {
    
    [self setBackgroundColor:[UIColor whiteColor]];
    
    /* Plot data, colors, linewidths, label attributes */
    plotData = [[NSMutableArray alloc] init];
    plotColors = [[NSMutableArray alloc] init];
    lineWidths = [[NSMutableArray alloc] init];
    labelAttributes = @{NSFontAttributeName:[UIFont fontWithName:@"Arial" size:10],
                        NSParagraphStyleAttributeName:[NSMutableParagraphStyle defaultParagraphStyle],
                        NSForegroundColorAttributeName:[UIColor grayColor]};
    xLabelFormatString = METScopeView_Default_xLabelFormatString_TD;
    yLabelFormatString = METScopeView_Default_yLabelFormatString_TD;
    
    /* Flags */
    gridOn = true;
    autoScaleGrid = false;
    autoScaleXGrid = false;
    autoScaleYGrid = false;
    axesOn = true;
    xLabelsOn = true;
    yLabelsOn = true;
    trackingOn = false;
    pinchZoomEnabled = true;
    pinchZoomXEnabled = true;
    pinchZoomYEnabled = true;
    
    /* Default mode */
    displayMode = kMETScopeViewTimeDomainMode;
    /* Frequency-domain mode needs sampling rate for x-axis scaling */
    samplingRate = METScopeView_Default_SamplingRate;
    
    /* Plot bounds, resolution, conversion factors */
    [self setPlotResolution:METScopeView_Default_PlotResolution];
    minPlotMin = CGPointMake(METScopeView_Default_XMin_TD, METScopeView_Default_YMin_TD);
    maxPlotMax = CGPointMake(METScopeView_Default_XMax_TD, METScopeView_Default_YMax_TD);
    tickUnits  = CGPointMake(METScopeView_Default_XTick_TD, METScopeView_Default_YTick_TD);
    [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
    [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
    gridDashLengths[0] = self.bounds.size.width  / 100;
    gridDashLengths[1] = self.bounds.size.height / 100;
    
    /* Detect pinch gesture for zooming/panning */
    pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(handlePinch:)];
    [self addGestureRecognizer:pinchRecognizer];
    
    /* Set up tracking settings and buffers */
    trackingLevel = 0.5;
    trackingBufferLength = 32;
    trackingBuffer = (int *)calloc(trackingBufferLength, sizeof(int));
    for (int i = 0; i < trackingBufferLength; i++)
        trackingBuffer[i] = 0;
    
    trackingErrorLength = 2;
    trackingErrorIdx = 0;
    trackingError = (float *)calloc(trackingErrorLength, sizeof(int));
    for (int i = 0; i < trackingErrorLength; i++)
        trackingError[i] = INFINITY;
    
    doUpdate = true;        // Schedule initial update
    maxRefreshRate = METScopeview_Default_MaxRefreshRate;  // Update interval
    
    updateClock = [[NSTimer alloc] init];
    [self setMaxRefreshRate:maxRefreshRate];
}

/* Check for updates at specified max refresh rate */
- (void)updateIfScheduled {
    if (doUpdate) {
        [self setNeedsDisplay];
        doUpdate = false;
    }
}

#pragma mark -
#pragma mark Interface Methods
/* Allocate input buffers of the specified length */
//- (void)setInputBufferLength:(int)length {
//    
//    inputBufferLength = length;
//    
//    /* setDataAtIndex: uses the input buffers in the main thread */
////    dispatch_sync(dispatch_get_main_queue(), ^{
//        if (xBuffer != NULL)
//            free(xBuffer);
//        
//        if (yBuffer != NULL)
//            free(yBuffer);
//        
//        /* Input buffers */
//        xBuffer = (float *)calloc(inputBufferLength, sizeof(float));
//        yBuffer = (float *)calloc(inputBufferLength, sizeof(float));
////    });
//}

/* Initialize a vDSP fft struct, buffers, windows, etc. */
- (void)setUpFFTWithSize:(int)size {
    
    fftSize = size;
    
    scale = 1.0f / (float)(fftSize/2);     // Normalization constant
    
    /* Buffers */
    inRealBuffer = (float *)malloc(fftSize * sizeof(float));
    outRealBuffer = (float *)malloc(fftSize * sizeof(float));
    splitBuffer.realp = (float *)malloc(fftSize/2 * sizeof(float));
    splitBuffer.imagp = (float *)malloc(fftSize/2 * sizeof(float));
    
    /* Hann Window */
    windowSize = size;
    window = (float *)calloc(windowSize, sizeof(float));
    vDSP_hann_window(window, windowSize, vDSP_HANN_NORM);
    
    /* Allocate the FFT struct */
    fftSetup = vDSP_create_fftsetup(log2f(fftSize), FFT_RADIX2);
}

/* Set the display mode to time/frequency domain and automatically rescale to default limits */
- (void)setDisplayMode:(enum DisplayMode)mode {
    
    if (mode == kMETScopeViewTimeDomainMode) {
        printf("Time domain mode\n");
        minPlotMin = CGPointMake(METScopeView_Default_XMin_TD, METScopeView_Default_YMin_TD);
        maxPlotMax = CGPointMake(METScopeView_Default_XMax_TD, METScopeView_Default_YMax_TD);
        tickUnits  = CGPointMake(METScopeView_Default_XTick_TD, METScopeView_Default_YTick_TD);
        xLabelFormatString = METScopeView_Default_xLabelFormatString_TD;
        yLabelFormatString = METScopeView_Default_yLabelFormatString_TD;
        [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
        [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
        displayMode = mode;
    }
    
    else if (mode == kMETScopeViewFrequencyDomainMode) {
        printf("Frequency domain mode\n");
        minPlotMin = CGPointMake(METScopeView_Default_XMin_FD, METScopeView_Default_YMin_FD);
        maxPlotMax = CGPointMake(METScopeView_Default_XMax_FD, METScopeView_Default_YMax_FD);
        tickUnits  = CGPointMake(METScopeView_Default_XTick_FD, METScopeView_Default_YTick_FD);
        xLabelFormatString = METScopeView_Default_xLabelFormatString_FD;
        yLabelFormatString = METScopeView_Default_yLabelFormatString_FD;
        [self setVisibleXLim:minPlotMin.x max:maxPlotMax.x];
        [self setVisibleYLim:minPlotMin.y max:maxPlotMax.y];
        displayMode = mode;
        trackingOn = false;
    }
}

/* Set the interval at which the view checks the update flag */
- (void)setMaxRefreshRate:(time_t)rate {
    
    [updateClock invalidate];       // Stop the old timer
    
    /* Reset with new interval */
    updateClock = [NSTimer scheduledTimerWithTimeInterval:rate target:self selector:@selector(updateIfScheduled) userInfo:nil repeats:YES];
}

/* Set x-axis hard limit constraining pinch zoom */
- (void)setHardXLim:(float)xMin max:(float)xMax {
    minPlotMin.x = xMin;
    maxPlotMax.x = xMax;
    [self setVisibleXLim:xMin max:xMax];
}
/* Set y-axis hard limit constraining pinch zoom */
- (void)setHardYLim:(float)yMin max:(float)yMax {
    minPlotMin.y = yMin;
    maxPlotMax.y = yMax;
    [self setVisibleYLim:yMin max:yMax];
}

/* Set the range of the x-axis */
- (void)setVisibleXLim:(float)xMin max:(float)xMax {
    
    if (xMin >= xMax) {
        NSLog(@"%s: Invalid x-axis limits", __PRETTY_FUNCTION__);
        return;
    }
    
    visiblePlotMin.x = xMin;
    visiblePlotMax.x = xMax;
    
    /* Horizontal units per pixel */
    unitsPerPixel.x = (visiblePlotMax.x - visiblePlotMin.x) / self.frame.size.width;
    
    /* Rescale the grid */
    [self setPlotUnitsPerTick:tickUnits.x vertical:tickUnits.y];
}

/* Set the range of the y-axis */
- (void)setVisibleYLim:(float)yMin max:(float)yMax {
    
    if (yMin >= yMax) {
        NSLog(@"%s: Invalid y-axis limits", __PRETTY_FUNCTION__);
        return;
    }
    
    visiblePlotMin.y = yMin;
    visiblePlotMax.y = yMax;
    
    /* Vertical units per pixel */
    unitsPerPixel.y = (visiblePlotMax.y - visiblePlotMin.y) / self.frame.size.height;
    
    /* Rescale the grid */
    [self setPlotUnitsPerTick:tickUnits.x vertical:tickUnits.y];
}

/* Set ticks and grid scale by specifying the input magnitude per tick/grid block */
- (void)setPlotUnitsPerXTick:(float)xTick {
    [self setPlotUnitsPerTick:xTick vertical:tickUnits.y];
}
- (void)setPlotUnitsPerYTick:(float)yTick {
    [self setPlotUnitsPerTick:tickUnits.x vertical:yTick];
}
- (void)setPlotUnitsPerTick:(float)xTick vertical:(float)yTick {
    
    if (xTick <= 0 || yTick <= 0) {
        NSLog(@"%s: Invalid grid scale", __PRETTY_FUNCTION__);
        return;
    }
    
    /* Rescale the grid to keep a specified number of ticks */
    if (autoScaleGrid) {
        
        CGPoint ticksInFrame;
        ticksInFrame.x = ((visiblePlotMax.x - visiblePlotMin.x) / xTick);
        ticksInFrame.y = ((visiblePlotMax.y - visiblePlotMin.y) / yTick);
    
        if (autoScaleXGrid) {
            if (ticksInFrame.x > METScopeView_AutoGrid_MaxXTicksInFrame)
                tickUnits.x = xTick + (visiblePlotMax.x - visiblePlotMin.x) / 10;
            else if (ticksInFrame.x < METScopeView_AutoGrid_MinXTicksInFrame) {
                tickUnits.x = xTick - (visiblePlotMax.x - visiblePlotMin.x) / 10;
            }
            else tickUnits.x = xTick;
        }
        else tickUnits.x = xTick;

        if (autoScaleYGrid) {
            if (ticksInFrame.y > METScopeView_AutoGrid_MaxYTicksInFrame)
                tickUnits.y = yTick + (visiblePlotMax.y - visiblePlotMin.y) / 10;
            else if (ticksInFrame.y < METScopeView_AutoGrid_MinYTicksInFrame) {
                tickUnits.y = yTick - (visiblePlotMax.y - visiblePlotMin.y) / 10;
            }
            else tickUnits.y = yTick;
        }
        else tickUnits.y = yTick;
    }
    else {
        tickUnits.x = xTick;
        tickUnits.y = yTick;
    }
    tickPixels.x = tickUnits.x / unitsPerPixel.x;
    tickPixels.y = tickUnits.y / unitsPerPixel.y;
    
    origin = [self plotScaleToPixel:0.0 y:0.0];
    
    doUpdate = true;
}

/* Set axis on/off, update the view */
- (void)toggleAxes {
    
    if(axesOn)  axesOn = false;
    else        axesOn = true;
    
    doUpdate = true;
}

/* Set grid on/off, update the view */
- (void)toggleGrid {
    
    if(gridOn)  gridOn = false;
    else        gridOn = true;
    
    doUpdate = true;
}

/* Set labels on/off, update the view */
- (void)toggleLabels {
    
    if (xLabelsOn | yLabelsOn) {
        xLabelsOn = false;
        yLabelsOn = false;
    }
    else {
        xLabelsOn = true;
        yLabelsOn = true;
    }
    
    doUpdate = true;
}
- (void)toggleXLabels {
    
    if (xLabelsOn)
        xLabelsOn = false;
    else
        xLabelsOn = true;
    
    doUpdate = true;
}
- (void)toggleYLabels {
    
    if (yLabelsOn)
        yLabelsOn = false;
    else
        yLabelsOn = true;
    
    doUpdate = true;
}

- (void)togglePinchZoom {
    
    if (pinchZoomEnabled)
        pinchZoomEnabled = false;
    else
        pinchZoomEnabled = true;
}

- (void)togglePinchZoom:(char)axis {
    
    if (axis == 'x') {
        if (pinchZoomXEnabled)
            pinchZoomXEnabled = false;
        else
            pinchZoomXEnabled = true;
    }
    else if (axis == 'y') {
        if (pinchZoomYEnabled)
            pinchZoomYEnabled = false;
        else
            pinchZoomYEnabled = true;
    }
    else
        NSLog(@"%s: Invalid axis. Specify 'x' or 'y' only.", __PRETTY_FUNCTION__);
    
    /* If both axes are disabled, disable pinch zooming in general. Saves computation time in handlePinch() method */
    if (!pinchZoomXEnabled && !pinchZoomYEnabled)
        pinchZoomEnabled = false;
    
    else if (pinchZoomXEnabled || pinchZoomYEnabled)
        pinchZoomEnabled = true;
}

- (void)toggleAutoGrid {
    
    if (autoScaleGrid)
        autoScaleGrid = false;
    else
        autoScaleGrid = true;
}

- (void)toggleAutoGrid:(char)axis {
    
    if (axis == 'x') {
        if (autoScaleXGrid)
            autoScaleXGrid = false;
        else
            autoScaleXGrid = true;
    }
    else if (axis == 'y') {
        if (autoScaleYGrid)
            autoScaleYGrid = false;
        else
            autoScaleYGrid = true;
    }
    else
        NSLog(@"%s: Invalid axis. Specify 'x' or 'y' only.", __PRETTY_FUNCTION__);
    
    /* If both axes are disabled, disable auto grid scaling altogether */
    if (!autoScaleXGrid && !autoScaleYGrid)
        autoScaleGrid = false;
    
    else if (autoScaleXGrid || autoScaleYGrid)
        autoScaleGrid = true;
}

/* Append new plot data to the array */
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy {
    [self setDataAtIndex:-1 withLength:length xData:xx yData:yy color:[UIColor blueColor] lineWidth:1.0];
}

/* Append new plot data to the array with a specified color */
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color {
    [self setDataAtIndex:-1 withLength:length xData:xx yData:yy color:color lineWidth:1.0];
}

/* Append new plot data to the array with a specified color and line width */
- (void)appendDataWithLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color lineWidth:(float)width {
    [self setDataAtIndex:-1 withLength:length xData:xx yData:yy color:color lineWidth:width];
}

/* Update plot data at a specified index in the array */
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy {
    [self setDataAtIndex:index withLength:length xData:xx yData:yy color:[UIColor blueColor] lineWidth:1.0];
}

/* Update plot data at a specified index in the array with a specified color */
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color {
    [self setDataAtIndex:index withLength:length xData:xx yData:yy color:color lineWidth:1.0];
}

/* Update plot data at a specified index in the array with a specified color and line width */
- (void)setDataAtIndex:(int)index withLength:(int)length xData:(float *)xx yData:(float *)yy color:(UIColor *)color lineWidth:(float)width {
    
    float *xBuffer = (float *)calloc(length, sizeof(float));
    float *yBuffer = (float *)calloc(length, sizeof(float));

    /* Data needs to be updated synchronously in the main thread  */
    dispatch_sync(dispatch_get_main_queue(), ^{
        
        /* Perform an FFT if we're in frequency domain mode */
        if (displayMode == kMETScopeViewFrequencyDomainMode) {
            
            [self computeMagnitudeFFT:yy outMagnitude:yBuffer seWindow:false];
            [self linspace:0.0 max:samplingRate/2 numElements:fftSize/2 array:xBuffer];
        }
        /* Otherwise, just copy into the input plot data buffers */
        else {
            memcpy(xBuffer, xx, length*sizeof(float));
            memcpy(yBuffer, yy, length*sizeof(float));
        }
        
        int startingIdx = 0;
        
        if (trackingOn)
            startingIdx = [self getStableStartingIndex:yBuffer length:length];
        
        NSMutableArray *newData = [NSMutableArray arrayWithCapacity:plotResolution];
        
        /* If the waveform has more samples than the plot resolution, resample the waveform */
        if (length - startingIdx > plotResolution) {
            
            float *indices = (float *)calloc(plotResolution, sizeof(float));
            [self linspace:startingIdx max:length numElements:plotResolution array:indices];
            
            int idx;
            for (int i = 0; i < plotResolution; i++) {
                
                idx = (int)round(indices[i]);
                [newData insertObject:[NSValue valueWithCGPoint:
                                       CGPointMake(xBuffer[idx] - xBuffer[startingIdx], yBuffer[idx])]
                              atIndex:i];
            }
            
            free(indices);
        }
        
        /* If the waveform has fewer samples than the plot resolution, interpolate the waveform */
        else if (length < plotResolution) {
            
            /* Get $plotResolution$ linearly-spaced x-values */
            float *targetXVals = (float *)calloc(plotResolution, sizeof(float));
            [self linspace:xBuffer[0] max:xBuffer[length-1] numElements:plotResolution array:targetXVals];
            
            CGPoint current, next, target;
            float perc;
            int j = 0;
            for (int i = 0; i < length-1; i++) {
                
                current.x = xBuffer[i];
                current.y = yBuffer[i];
                next.x = xBuffer[i+1];
                next.y = yBuffer[i+1];
                target.x = targetXVals[j];
                
                while (target.x < next.x) {
                    perc = (target.x - current.x) / (next.x - current.x);
                    target.y = current.y * (1-perc) + next.y * perc;
                    [newData addObject:[NSValue valueWithCGPoint:target]];
                    j++;
                    target.x = targetXVals[j];
                }
            }
            
            current.x = xBuffer[length-2];
            current.y = yBuffer[length-2];
            next.x = xBuffer[length-1];
            next.y = yBuffer[length-1];
            target.x = targetXVals[j];
            
            while (j < plotResolution) {
                j++;
                perc = (target.x - current.x) / (next.x - current.x);
                target.y = current.y * (1-perc) + next.y * perc;
                [newData addObject:[NSValue valueWithCGPoint:target]];
            }
            
            free(targetXVals);
        }
        
        /* If waveform has number of samples == plot resolution, just copy */
        else {
            for (int i = 0; i < length; i++) {
                [newData insertObject:[NSValue valueWithCGPoint:
                                       CGPointMake(xBuffer[i], yBuffer[i])]
                              atIndex:i];
            }
        }
        
        /* Append new waveform for index -1 */
        if (index == -1) {
            [plotData addObject:newData];
            [plotColors addObject:color];
            [lineWidths addObject:[NSNumber numberWithFloat:width]];
        }
        /* Append for index i if plot has i-1 waveforms */
        else if (index == [plotData count]) {
            [plotData addObject:newData];
            [plotColors addObject:color];
            [lineWidths addObject:[NSNumber numberWithFloat:width]];
        }
        /* Otherwise, replace plot data at the specified index */
        else if (index >= 0 && index < [plotData count]) {
            [plotData replaceObjectAtIndex:index withObject:newData];
            [plotColors replaceObjectAtIndex:index withObject:color];
            [lineWidths addObject:[NSNumber numberWithFloat:width]];
        }
        else
            NSLog(@"Invalid plot data index %d\n[plotData count] = %lu", index, (unsigned long)[plotData count]);
            
    });
    
    free(xBuffer);
    free(yBuffer);
    
    doUpdate = true;
}

/* Set/update plot color for a waveform at some index */
- (void)setPlotColor:(UIColor *)color atIndex:(int)index {
    
    if (index > 0 && index < [plotColors count])
        [plotColors replaceObjectAtIndex:index withObject:color];
}

/* Set/update line width for a waveform at some index */
- (void)setLineWidth:(float)width atIndex:(int)index {
    
    if (index > 0 && index < [lineWidths count])
        [lineWidths replaceObjectAtIndex:index withObject:[NSNumber numberWithFloat:width]];
}

#pragma mark -
#pragma mark Render Methods
/* Main render method */
- (void)drawRect:(CGRect)rect {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint current;                // Reusable current point
    
    int nWaveforms = (int)[plotData count];
    
    /* Keep nWaveforms previous points (in plot units) for each waveform */
    NSMutableArray *previous = [[NSMutableArray alloc] initWithCapacity:nWaveforms];
    for(int n = 0; n < nWaveforms; n++) {
        
        /* Get first index from each waveform */
        current = [self plotScaleToPixel:[plotData[n][0] CGPointValue]];
        [previous addObject:[NSValue valueWithCGPoint:current]];
    }
    
    /* Draw on the view from left to right, cycling through each waveform in the inner loop. Doesn't work the other way around for some reason */
    for (int i = 1; i < plotResolution-2; i++) {
        
        for (int n = 0; n < nWaveforms; n++) {
            
            /* Current point: n^th waveform, i^th sample */
            current = [self plotScaleToPixel:[plotData[n][i] CGPointValue]];
            
            CGContextBeginPath(context);
            
            /* Set the color for this waveform */
            CGContextSetStrokeColorWithColor(context, ((UIColor *)[plotColors objectAtIndex:n]).CGColor);
            CGContextSetLineWidth(context, [[lineWidths objectAtIndex:n] floatValue]);
            
            /* Append line from previous point to current point */
            CGContextMoveToPoint(context, [previous[n] CGPointValue].x, [previous[n] CGPointValue].y);
            CGContextAddLineToPoint(context, current.x, current.y);
            
            /* Draw */
            CGContextStrokePath(context);
            
            /* Current point becomes the previous point */
            [previous replaceObjectAtIndex:n withObject:[NSValue valueWithCGPoint:current]];
        }
    }
    
    if (axesOn)     [self drawAxes];
    if (xLabelsOn)  [self drawXLabels];
    if (yLabelsOn)  [self drawYLabels];
    if (trackingOn) [self drawTrackingLevel];
    if (gridOn)     [self drawGrid];
}

- (void)drawAxes {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint loc;            // Reusable current location
    
    CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextSetAlpha(context, 1.0);
    CGContextSetLineWidth(context, 2.0);
    
    /* If the x-axis is within the plot's bounds */
    if(visiblePlotMin.y <= 0 && visiblePlotMax.y >= 0) {
        
        loc = [self plotScaleToPixel:visiblePlotMin.x y:0.0];
        
        /* Draw the x-axis */
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.frame.size.width, loc.y);
        CGContextStrokePath(context);
        
        /* Starting at the plot origin, draw ticks in the positive x direction */
        loc = origin;
        while(loc.x <= self.bounds.size.width) {
            
            CGContextMoveToPoint(context, loc.x, loc.y - 3);
            CGContextAddLineToPoint(context, loc.x, loc.y + 3);
            CGContextStrokePath(context);
            
            loc.x += tickPixels.x;
        }
        
        /* Draw ticks in negative x direction */
        loc = origin;
        while(loc.x >= 0) {
            
            CGContextMoveToPoint(context, loc.x, loc.y - 3);
            CGContextAddLineToPoint(context, loc.x, loc.y + 3);
            CGContextStrokePath(context);
            
            loc.x -= tickPixels.x;
        }
    }
    
    /* If the y-axis is within the plot's bounds */
    if(visiblePlotMin.x <= 0 && visiblePlotMax.x >= 0) {
        
        loc = [self plotScaleToPixel:0.0 y:visiblePlotMax.y];
        
        /* Draw the y-axis */
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.frame.size.height);
        CGContextStrokePath(context);
        
        /* Starting at the plot origin, draw ticks in the positive y direction */
        loc = origin;
        while(loc.y <= self.bounds.size.height) {
            
            CGContextMoveToPoint(context, loc.x - 3, loc.y);
            CGContextAddLineToPoint(context, loc.x + 3, loc.y);
            CGContextStrokePath(context);
            
            loc.y += tickPixels.y;
        }
        
        /* Draw ticks in negative y direction */
        loc = origin;
        while(loc.y >= 0) {
            
            CGContextMoveToPoint(context, loc.x - 3, loc.y);
            CGContextAddLineToPoint(context, loc.x + 3, loc.y);
            CGContextStrokePath(context);
            
            loc.y -= tickPixels.y;
        }
    }
}

- (void)drawXLabels {
    
    CGPoint loc;            // Current point in pixels
    NSString *label;
    
    /* If the x-axis is within the plot's bounds */
    if(visiblePlotMin.y <= 0 && visiblePlotMax.y >= 0) {
        
        /* Starting at the plot origin, add labels in the positive x direction */
        loc = origin;
        loc.y += 2;
        while(loc.x <= self.bounds.size.width) {
            
            loc.x += self.frame.origin.x;
            label = [NSString stringWithFormat:xLabelFormatString, [self pixelToPlotScale:loc].x];
            loc.x -= self.frame.origin.x;
            loc.x += 2;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.x -= 2;
            loc.x += tickPixels.x;
        }
        
        /* Add labels in negative x direction */
        loc = origin;
        loc.y += 2;
        while(loc.x >= 0) {
            
            loc.x += self.frame.origin.x;
            label = [NSString stringWithFormat:xLabelFormatString, [self pixelToPlotScale:loc].x];
            loc.x -= self.frame.origin.x;
            loc.x += 2;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.x -= 2;
            loc.x -= tickPixels.x;
        }
    }
}

- (void)drawYLabels {
    
    CGPoint loc;        // Current points in pixels
    NSString *label;
    
    /* If the y-axis is within the plot's bounds */
    if(visiblePlotMin.x <= 0 && visiblePlotMax.x >= 0) {
        
        /* Starting at the plot origin, add labels in the positive y direction */
        loc = origin;
        loc.x += 2;
        while(loc.y <= self.bounds.size.height) {
            
            loc.y += self.frame.origin.y;
            label = [NSString stringWithFormat:yLabelFormatString, [self pixelToPlotScale:loc].y];
            loc.y -= self.frame.origin.y;
            loc.y -= 14;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.y += 14;
            loc.y += tickPixels.y;
        }
        
        /* Add labels in negative y direction */
        loc = origin;
        loc.x += 2;
        while(loc.y >= 0) {
            
            loc.y += self.frame.origin.y;
            label = [NSString stringWithFormat:yLabelFormatString, [self pixelToPlotScale:loc].y];
            loc.y -= self.frame.origin.y;
            loc.y -= 14;
            [label drawAtPoint:loc withAttributes:labelAttributes];
            loc.y += 14;
            loc.y -= tickPixels.y;
        }
    }
}

- (void)drawGrid {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint loc;            // Reusable current location
    
    /* Dashed-line parameters */
    CGContextSetStrokeColorWithColor(context, [UIColor blackColor].CGColor);
    CGContextSetAlpha(context, 0.5);
    CGContextSetLineWidth(context, 0.5);
    CGContextSetLineDash(context, M_PI, (CGFloat *)&gridDashLengths, 2);
    
    loc.y = 0;
    loc.x = origin.x;
    
    /* Draw in-bound vertical grid lines in positive x direction until we excede the frame width */
    while (loc.x < 0) loc.x += tickPixels.x;
    while (loc.x <= self.bounds.size.width) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.bounds.size.height);
        CGContextStrokePath(context);
        
        loc.x += tickPixels.x;
    }
    
    loc.y = 0;
    loc.x = origin.x;
    
    /* Draw in-bound vertical grid lines in negative x direction until we pass zero */
    while (loc.x > self.bounds.size.width) loc.x -=tickPixels.x;
    while (loc.x >= 0) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, loc.x, self.bounds.size.height);
        CGContextStrokePath(context);
        
        loc.x -= tickPixels.x;
    }
    
    loc.x = 0;
    loc.y = origin.y;
    
    /* Draw in-bound horizontal grid lines in negative y direction until we excede the frame height */
    while (loc.y < 0) loc.y += tickPixels.y;
    while (loc.y <= self.bounds.size.height) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.bounds.size.width, loc.y);
        CGContextStrokePath(context);
        
        loc.y += tickPixels.y;
    }
    
    loc.x = 0;
    loc.y = origin.y;
    
    /* Draw in-bound horizontal grid lines in positive y direction until we excede 0 */
    while (loc.y > self.bounds.size.height) loc.y -= tickPixels.y;
    while (loc.y >= 0) {
        
        CGContextMoveToPoint(context, loc.x, loc.y);
        CGContextAddLineToPoint(context, self.bounds.size.width, loc.y);
        CGContextStrokePath(context);
        
        loc.y -= tickPixels.y;
    }
}

- (void)drawTrackingLevel {
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGPoint loc;            // Reusable current location
    
    CGContextSetStrokeColorWithColor(context, [UIColor orangeColor].CGColor);
    CGContextSetAlpha(context, 1.0);
    CGContextSetLineWidth(context, 2.0);
    
    /* Draw tracking level on the y-axis */
    loc = [self plotScaleToPixel:0.0 y:trackingLevel];
    
    /* If the y-axis is outside the plot's bounds, put the tracking level at the plot xMin */
    if(visiblePlotMin.x >= 0 || visiblePlotMax.x <= 0) {
        loc.x = self.bounds.origin.x + 10;
    }
    
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, loc.x, loc.y);
    loc.x -= 5;
    loc.y += 5;
    CGContextAddLineToPoint(context, loc.x, loc.y);
    CGContextStrokePath(context);
    
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, loc.x, loc.y);
    loc.y -= 10;
    CGContextAddLineToPoint(context, loc.x, loc.y);
    CGContextStrokePath(context);
    
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, loc.x, loc.y);
    loc.x += 5;
    loc.y += 5;
    CGContextAddLineToPoint(context, loc.x, loc.y);
    CGContextStrokePath(context);
}

#pragma mark -
#pragma mark Gesture Handlers
- (void)handlePinch:(UIPinchGestureRecognizer *)sender {
    
    if (!pinchZoomEnabled)
        return;
    
    /* If the number of touches became 1, save the current remaining touch location at index 0 and wait until the number of touches goes from 1 to 2, and overwrite the old previous touch location at index 1 with a new incoming touch location to restart the pinch with the correct previous touch location */
    
    if ([sender numberOfTouches] == 1) {
        /* If the remaining touch is to the left of the previously lost second touch, store it at index 0 */
        if ([sender locationOfTouch:0 inView:sender.view].x)
        
        previousPinchTouches[0] = [sender locationOfTouch:0 inView:sender.view];
        previousNumPinchTouches = 1;
        return;
    }
    else if (previousNumPinchTouches == 1 && [sender numberOfTouches] == 2) {
        previousPinchTouches[1] = [sender locationOfTouch:1 inView:sender.view];
        previousNumPinchTouches = 2;
    }
    
    if ([sender numberOfTouches] != 2) {
        return;
    }
    
    /* Get the two touch locations */
    CGPoint touches[2];
    touches[0] = [sender locationOfTouch:0 inView:sender.view];
    touches[1] = [sender locationOfTouch:1 inView:sender.view];
    
    /* Get the distance between them */
    CGPoint pinchDistance;
    pinchDistance.x = abs(touches[0].x - touches[1].x);
    pinchDistance.y = abs(touches[0].y - touches[1].y);
    
    /* If this is the first touch, save the scale */
    if (sender.state == UIGestureRecognizerStateBegan) {
        previousNumPinchTouches = 2;
        previousPinchTouches[0] = touches[0];
        previousPinchTouches[1] = touches[1];
    }
    
    /* Otherwise, expand/contract the plot bounds */
    else {
        
        /* Maintain indices of which touch is left and which is lower */
        int currLeftIdx = (touches[0].x < touches[1].x) ? 0 : 1;
        int currLowIdx =  (touches[0].y > touches[1].y) ? 0 : 1;
        int prevLeftIdx = (previousPinchTouches[0].x < previousPinchTouches[1].x) ? 0 : 1;
        int prevLowIdx =  (previousPinchTouches[0].y > previousPinchTouches[1].y) ? 0 : 1;
        
        CGPoint pixelShift[2];
        pixelShift[0].x = previousPinchTouches[currLeftIdx].x - touches[prevLeftIdx].x;
        pixelShift[0].y = touches[currLowIdx].y - previousPinchTouches[prevLowIdx].y;
        pixelShift[1].x = previousPinchTouches[!currLeftIdx].x - touches[!prevLeftIdx].x;
        pixelShift[1].y = touches[!currLowIdx].y - previousPinchTouches[!prevLowIdx].y;
        
        float newXMin = visiblePlotMin.x + pixelShift[0].x * unitsPerPixel.x;
        float newXMax = visiblePlotMax.x + pixelShift[1].x * unitsPerPixel.x;
        float newYMin = visiblePlotMin.y + pixelShift[0].y * unitsPerPixel.y;
        float newYMax = visiblePlotMax.y + pixelShift[1].y * unitsPerPixel.y;
        
        /* Rescale if we're within the hard limit */
        if (pinchZoomXEnabled && newXMin > minPlotMin.x && newXMax < maxPlotMax.x)
            [self setVisibleXLim:newXMin max:newXMax];
        if (pinchZoomYEnabled && newYMin > minPlotMin.y && newYMax < maxPlotMax.y)
            [self setVisibleYLim:newYMin max:newYMax];
        
        previousPinchTouches[0] = touches[0];
        previousPinchTouches[1] = touches[1];
    }
}

/* UIGestureRecognizerDelegate method to enable simultaneous gesture recognition if any gesture recognizers are attached externally */
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer{
    return YES;
}

#pragma mark -
#pragma mark Utility methods
/* Oscilloscope-style triggering for waveform stabilization */
- (int)getStableStartingIndex:(float *)waveform length:(int)length {
    
    int retVal = 0;
    int indices[trackingBufferLength];
    float errSum = 0;
    
    int i = 0;
    int j = 0;
    while (j < trackingBufferLength && i < length-1) {
        
        /* Find the frist $trackingBufferLength$ indices where a rising edge passes the tracking level */
        if (waveform[i] < trackingLevel && waveform[i+1] > trackingLevel) {
            
            indices[j] = i;         // Current index
            
            /* Error between previous tracking buffer and the current */
            errSum += fabs(indices[j] - trackingBuffer[j]);
            
            trackingBuffer[j] = j;  // New previous index
            j++;
        }
        i++;
    }
    
    /* Look for troughs in a circular buffer of tracking errors */
    trackingError[trackingErrorIdx] = errSum;
    
    bool success = true;
    for (int i = trackingErrorIdx, j = 0; j < trackingErrorLength-1; i--, j++) {
        
        if (i <= 0)
            i = trackingErrorLength-1;
        
        /* Detect when we're exiting a trough (positive first differences for the entire buffer length) */
        if (trackingError[i] < trackingError[i-1])
            success = false;
    }
    
    trackingErrorIdx++;
    if (trackingErrorIdx >= trackingErrorLength)
        trackingErrorIdx = 0;
    
    if (success && indices[0] < length && indices[0] > 0)
        retVal = indices[0];
    
    return retVal;
}

/* Return a pixel location in the view for a given plot-scale value */
- (CGPoint)plotScaleToPixel:(float)pX y:(float)pY {
    
    CGPoint retVal;
    
    retVal.x = self.frame.size.width * (pX - visiblePlotMin.x) / (visiblePlotMax.x - visiblePlotMin.x);
    retVal.y = self.frame.size.height * (1 - (pY - visiblePlotMin.y) / (visiblePlotMax.y - visiblePlotMin.y));
    
    return retVal;
}

/* Return a pixel location in the view for a given plot-scale value */
- (CGPoint)plotScaleToPixel:(CGPoint)plotScale {
    
    CGPoint pixelVal;
    
    pixelVal.x = self.frame.size.width * (plotScale.x - visiblePlotMin.x) / (visiblePlotMax.x - visiblePlotMin.x);
    pixelVal.y = self.frame.size.height * (1 - (plotScale.y - visiblePlotMin.y) / (visiblePlotMax.y - visiblePlotMin.y));
    
    return pixelVal;
}

/* Return a plot-scale value for a given pixel location in the view */
- (CGPoint)pixelToPlotScale:(CGPoint)point {
    
    float px, py;
    px = (point.x - self.frame.origin.x) / self.frame.size.width;
    py = (point.y - self.frame.origin.y) / self.frame.size.height;
    py = 1 - py;
    
    CGPoint plotScale;
    plotScale.x = visiblePlotMin.x + px * (visiblePlotMax.x - visiblePlotMin.x);
    plotScale.y = visiblePlotMin.y + py * (visiblePlotMax.y - visiblePlotMin.y);
    
    return plotScale;
}

/* Generate a linearly-spaced set of indices for sampling an incoming waveform */
- (void)linspace:(float)minVal max:(float)maxVal numElements:(int)size array:(float*)array {
    
    float step = (maxVal - minVal) / (size-1);
    array[0] = minVal;
    for (int i = 1; i < size-1 ;i++) {
        array[i] = array[i-1] + step;
    }
    array[size-1] = maxVal;
}

/* Compute the single-sided magnitude spectrum using Accelerate's vDSP methods */
- (void)computeMagnitudeFFT:(float *)inBuffer outMagnitude:(float *)magnitude seWindow:(bool)doWindow {
    
    if (fftSetup == NULL) {
        printf("%s: Warning: must call [METScopeView setUpFFTWithSize] before enabling frequency domain mode\n", __PRETTY_FUNCTION__);
        return;
    }
    
    /* Multiply by Hann window */
    if (doWindow)
        vDSP_vmul(inBuffer, 1, window, 1, inRealBuffer, 1, fftSize);
    
    /* Otherwise just copy into the real input buffer */
    else
        cblas_scopy(fftSize, inBuffer, 1, inRealBuffer, 1);
    
    /* Transform the real input data into the even-odd split required by vDSP_fft_zrip() explained in: https://developer.apple.com/library/ios/documentation/Performance/Conceptual/vDSP_Programming_Guide/UsingFourierTransforms/UsingFourierTransforms.html */
    vDSP_ctoz((COMPLEX *)inRealBuffer, 2, &splitBuffer, 1, fftSize/2);
    
    /* Computer the FFT */
    vDSP_fft_zrip(fftSetup, &splitBuffer, 1, log2f(fftSize), FFT_FORWARD);
    
    splitBuffer.imagp[0] = 0.0;     // ?? Shitty did this
    
    /* Convert the split complex data splitBuffer to an interleaved complex coordinate pairs */
    vDSP_ztoc(&splitBuffer, 1, (COMPLEX *)inRealBuffer, 2, fftSize/2);
    
    /* Convert the interleaved complex vector to interleaved polar coordinate pairs (magnitude, phase) */
    vDSP_polar(inRealBuffer, 2, outRealBuffer, 2, fftSize/2);
    
    /* Copy the even indices (magnitudes) */
    cblas_scopy(fftSize/2, outRealBuffer, 2, magnitude, 1);
    
    /* Normalize the magnitude */
    for (int i = 0; i < fftSize; i++)
        magnitude[i] *= scale;
    
//    /* Copy the odd indices (phases) */
//    cblas_scopy(fftSize/2, outRealBuffer+1, 2, phase, 1);
}

@end
























