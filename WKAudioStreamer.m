//
//  WKAudioStreamer.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"

///////////////////////////////////////////////////
//////////////////// WKDataPair ///////////////////
///////////////////////////////////////////////////
//
//@implementation WKDataPair
//
//+ (id)pairWithData:(id)v1 And:(id)v2 {
//    WKDataPair *p = [self new];
//    if (p != nil) {
//        [p setV1:v1];
//        [p setV2:v2];
//    }
//    return p;
//}
//
//@end

/////////////////////////////////////////////////
//////////////// WKAudioStreamer ////////////////
/////////////////////////////////////////////////

@interface WKAudioStreamer () <NSURLConnectionDelegate>
@end

@implementation WKAudioStreamer

+ (id)streamerWithURLString:(NSString *)url
                   delegate:(id<WKAudioStreamerDelegate>)aDelegate {
    WKAudioStreamer *streamer = [self new];
    streamer->delegate = aDelegate;
    streamer->songUrl = [NSURL URLWithString:url];
    streamer->connection = nil;
    streamer->availRangeFrom = streamer->availRangeTo = 0.0f;
    streamer->isMetaDataReady = NO;
    streamer->dataList = [NSMutableArray new];
    return streamer;
}

- (NSString *)description {
    NSString *s = [super description];
    return [s stringByAppendingFormat:@" songUrl:%@", songUrl];
}

/////////////////////////////////////////////////
/////////////// playback control ////////////////
/////////////////////////////////////////////////

- (void)play {}
- (void)pause {}
- (void)stop {}

// be careful when calling the delegate methods if seeking is implemented.
// @synchronized{} might be necessary to avoid some weird situations.
//
// FIXME: remember to set self->availRangeFrom and self->availRangeTo.
- (BOOL)seek:(double)targetTime {
    if (self->isMetaDataReady) {
        return NO;
    }
    
    // FIXME
    
    return YES;
}

/////////////////////////////////////////////////
////////////////// stremer API //////////////////
/////////////////////////////////////////////////

// FIXME:
// what should I do if streaming just stopped and just resend the request will fix?
// (before receiving any data or during streaming)
- (void)startStreaming {
    NSURLRequest *req = [NSURLRequest requestWithURL:songUrl];
    connection = [NSURLConnection connectionWithRequest:req delegate:self];
}

/////////////////////////////////////////////////
//////// NSURLConnectionDelegate methods ////////
/////////////////////////////////////////////////

// data received.
//
// FIXME: need to call the delegate method onDataReceived:availRangeFrom:to.
//        (have to calculate and update availRangeFrom/availRangeTo first)
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (self->isMetaDataReady) {
        // FIXME
        [self->delegate onDataReceived:data availRangeFrom:0.0f to:0.0f]; // DEBUG
    } else {
        [self->delegate onDataReceived:data availRangeFrom:0.0f to:0.0f];
    }
}

// downloading finished.
//
// this method is supposed to be called after connection:didReceiveData.
// so when it is called, dataList has ready included the last packet.
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (self->availRangeFrom == 0.0f) {
        [self->delegate onStreamingFinished:self fullData:dataList];
    } else {
        [self->delegate onStreamingFinished:self fullData:nil];
    }
}

// oops... challange failed.
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self->connection = nil;
    [self->delegate onErrorOccured:error];
}

/////////////////////////////////////////////////////////////////////////
// the following methods are not that important in this case... sorry! //
/////////////////////////////////////////////////////////////////////////

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse {
    return request; // just redirect.
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // "Sent when the connection has received sufficient data
    //  to construct the URL response for its request."
    //
    // wtf?
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil; // don't do caching on response.
}

@end
