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
    NSLog(@"%@", url); // DEBUG
    
    if (as == nil) {
        as = [WKAudioStreamer streamerWithURLString:url delegate:self];
        [as startStreaming];
    }
    NSLog(@"%@", as); // DEBUG
}

/////////////////////////////////////////////////
//////////////// delegate methods ///////////////
/////////////////////////////////////////////////

- (void)onStreamingFinished:(WKAudioStreamer *)streamer
                   fullData:(NSData *)data {
    NSLog(@"streaming finished"); // DEBUG
}

- (void)onPlayingFinished {
    NSLog(@"playing finished"); // DEBUG
    as = nil;
}

- (void)onDataReceived:(NSData *)newData
        availRangeFrom:(double)s
                    to:(double)e{
    // NSLog(@"new data: %@; avail range: %lf - %lf", newData, s, e);
    NSLog(@"%@", [[NSString alloc] initWithData:newData encoding:NSASCIIStringEncoding]);
}

- (void)onErrorOccured:(NSError *)error {
    NSLog(@"%@", error);
}

@end
