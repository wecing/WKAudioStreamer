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

- (IBAction)play:(id)sender {
    NSString *url = [[self urlField] stringValue];
    NSLog(@"\n-> requested url: %@", url); // DEBUG
    
    if (as == nil) {
        as = [WKAudioStreamer streamerWithURLString:url delegate:self];
        [as startStreaming];
        NSLog(@"\n-> streaming started."); // DEBUG
        
        [as play];
        NSLog(@"\n-> playing started."); // DEBUG
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
    as = nil;
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

- (void)onErrorOccured:(WKAudioStreamer *)streamer
                 error:(NSError *)error {
    NSLog(@"\n-> %@", error);
}

@end
