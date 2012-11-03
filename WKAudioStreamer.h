//
//  WKAudioStreamer.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>

// WKAudioStreamer does more than a streamer.
// It will also play the audio file it's streaming.
// 
// The client can control when to stream/play.

/////////////////////////////////////////////////
//////////////// code starts here ///////////////
/////////////////////////////////////////////////

@protocol WKAudioStreamerDelegate;

/////////////////////////////////////////////////
/////////////////// WKDataPair //////////////////
/////////////////////////////////////////////////

@interface WKDataPair : NSObject
@property id v1;
@property id v2;
+ (id)pairWithData:(id)v1 And:(id)v2;
@end

/////////////////////////////////////////////////
//////////////// WKAudioStreamer ////////////////
/////////////////////////////////////////////////

@interface WKAudioStreamer : NSObject {
@private
    id<WKAudioStreamerDelegate> delegate;
}

// streaming will not start right after the streamer is created.
// the user would have to call start by hand.
+ (id)streamerWithURLString:(NSString *)url
                   delegate:(id<WKAudioStreamerDelegate>)delegate;

////////////////////////
/// the player APIs: ///
////////////////////////

- (void)play;
- (void)pause;
- (void)stop;

// seek to the target time.
//
// if data at targetTime is not streamed, all data already stored
// in the object will be thrown away.
//
// *** important ***
// this might be called when streaming has not started yet...
- (BOOL)seek:(double)targetTime;

//////////////////////////
/// the streamer APIs: ///
//////////////////////////

// once started, no way to pause...
// but why would anyone want to pause and then resume?
- (void)startStreaming;

// return a pair of doubles (packed in NSNumber) indicating the
// range of time where data is available.
- (WKDataPair *)availableRange;

@end

////////////////////////////////////////////////
///////////////// the delegate /////////////////
////////////////////////////////////////////////

@protocol WKAudioStreamerDelegate <NSObject>

@required
// called when streaming has finished.
// data could be nil in the case where seeking to
// unstreamed parts was requested.
- (void)onStreamingFinished:(WKAudioStreamer *)streamer
                       data:(NSData *)data;

- (void)onDataReceived:(NSData *)data;

@optional
- (void)onErrorOccured:(NSError *)error;

@end