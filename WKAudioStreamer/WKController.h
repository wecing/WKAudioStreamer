//
//  WKController.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WKAudioStreamer.h"

@interface WKController : NSObject <WKAudioStreamerDelegate>

@property IBOutlet NSTextField *urlField;
@property IBOutlet NSButton *toggleButton;
@property IBOutlet NSSlider *playerPosSlider;

- (IBAction)play:(id)sender;

- (IBAction)startStreaming:(id)sender;
- (IBAction)pauseStreaming:(id)sender;

- (IBAction)restartStreaming:(id)sender;

- (IBAction)onSliderValueChanged:(id)sender;

@end
