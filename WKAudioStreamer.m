//
//  WKAudioStreamer.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"

/////////////////////////////////////////////////
////////////////// WKDataPair ///////////////////
/////////////////////////////////////////////////

@implementation WKDataPair

+ (id)pairWithData:(id)v1 And:(id)v2 {
    WKDataPair *p = [self new];
    if (p != nil) {
        [p setV1:v1];
        [p setV2:v2];
    }
    return p;
}

@end

/////////////////////////////////////////////////
//////////////// WKAudioStreamer ////////////////
/////////////////////////////////////////////////

@implementation WKAudioStreamer

+ (id)streamerWithURLString:(NSString *)url
                   delegate:(id<WKAudioStreamerDelegate>)aDelegate {
}

- (void)start {
}

- (BOOL)seek:(double)targetTime {
}

@end
