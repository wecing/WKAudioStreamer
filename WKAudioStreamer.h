//
//  WKAudioStreamer.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 11/16/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol WKAudioStreamerDelegate;

@interface WKAudioStreamer : NSObject
// streaming will not start right after the streamer is created.
// the user would have to call startStreaming by hand.
+ (id)streamerWithURLString:(NSString *)url
                   delegate:(id<WKAudioStreamerDelegate>)delegate;

- (void)play;
- (void)pause;

// if seek returns YES, it means later data received by the delegate will not be continuous
// with the previous ones -- which means you cannot save them onto your disk as a single file anymore.
- (BOOL)seek:(double)targetTime;

- (double)duration;

- (void)startStreaming;

- (NSString *)requestedURL;

@end

////////////////////////////////////////////////
///////////////// the delegate /////////////////
////////////////////////////////////////////////

@protocol WKAudioStreamerDelegate <NSObject>

@required
// - (void)onPlayerReady:(WKAudioStreamer *)streamer;
- (void)onStreamingFinished:(WKAudioStreamer *)streamer;
- (void)onPlayingFinished:(WKAudioStreamer *)streamer;

- (void)onDataReceived:(WKAudioStreamer *)streamer
                  data:(NSData *)newData;

@optional
- (void)onErrorOccured:(WKAudioStreamer *)streamer
                 error:(NSError *)error;

@end
