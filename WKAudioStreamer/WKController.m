//
//  WKController.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKController.h"

static WKAudioStreamer *as = nil;

@implementation WKController

// - (void)awakeFromNib {
//     [[self toggleButton] setEnabled:NO];
// }

- (IBAction)play:(id)sender {
    NSString *url = [[self urlField] stringValue];
    if (as == nil && ![url isEqualToString:[as requestedURL]]) {
        NSLog(@"\n-> requested url: %@", url); // DEBUG
        as = [WKAudioStreamer streamerWithURLString:url delegate:self];
        [as startStreaming];
        NSLog(@"\n-> streaming started."); // DEBUG
        // [[self toggleButton] setEnabled:NO];
    }
    
    NSButton *but = [self toggleButton];
    if ([[but title] isEqualToString:@"Play"]) {
        [as play];
        [but setTitle:@"Pause"];
        
        NSLog(@"\n-> playing started."); // DEBUG
    } else {
        [as pause];
        [but setTitle:@"Play"];
        
        NSLog(@"\n-> paused!"); // DEBUG
    }
}

/////////////////////////////////////////////////
//////////////// delegate methods ///////////////
/////////////////////////////////////////////////

- (void)onStreamingFinished:(WKAudioStreamer *)streamer {
    NSLog(@"\n-> streaming finished."); // DEBUG
}

- (void)onPlayingFinished:(WKAudioStreamer *)streamer {
    NSLog(@"\n-> playing finished."); // DEBUG
    [[self toggleButton] setTitle:@"Play"];
}

- (void)onDataReceived:(WKAudioStreamer *)streamer
                  data:(NSData *)newData {
    // DEBUG
    static BOOL debug_info_printed = NO;
    if (!debug_info_printed) {
        NSLog(@"\n-> streaming data...");
        debug_info_printed = YES;
    }
}

// - (void)onPlayerReady:(WKAudioStreamer *)streamer {
//     NSLog(@"\n-> audio duration: %lfs", [streamer duration]); // DEBUG
//     [streamer play];
// }

- (void)onErrorOccured:(WKAudioStreamer *)streamer
                 error:(NSError *)error {
    NSLog(@"\n-> %@", error);
}

@end
