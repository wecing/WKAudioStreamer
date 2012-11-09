//
//  WKAudioStreamer.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>


// WKAudioStreamer does more than a streamer.
// It will also play the audio file it's streaming.
// 
// The client can control when to stream/play.


@protocol WKAudioStreamerDelegate;

/////////////////////////////////////////////////
//////////////// WKAudioStreamer ////////////////
/////////////////////////////////////////////////

@interface WKAudioStreamer : NSObject {
@private
    id<WKAudioStreamerDelegate> delegate;
    NSURL *songUrl;
    NSURLConnection *connection;
    BOOL isMetaDataReady;
    double availRangeFrom;
    double availRangeTo;
    NSMutableArray *dataList;
    AudioFileStreamID afsID;

    
    // helper variables used for seeking

    
    AudioStreamBasicDescription *streamDesc;
    SInt64 dataOffset;
    UInt64 fileSize;
    
    // processed packets,
    // number of frames in these packets,
    // total size of them.
    // 
    UInt64 packetCount, frameCount;//, sizeCount;
    
    // bit rate fetched from metadata.
    // supposed to be used only through getter/setter methods. (whyyyyy?)
    UInt32 _bitRate;
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

- (double)duration;

// seek to the target time.
//
// if data at targetTime is not streamed, all data already stored
// in the object will be thrown away.
//
// *** important ***
// if you call seek before streaming has started,
// the seeking request will be simply ignored.
- (BOOL)seek:(double)targetTime;

//////////////////////////
/// the streamer APIs: ///
//////////////////////////

// once started, no way to pause...
// but why would anyone want to pause and then resume?
- (void)startStreaming;

// // return a pair of doubles (packed in NSNumber) indicating the
// // range of time where data is available.
// - (WKDataPair *)availableRange;

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
                   fullData:(NSArray *)dataList;

- (void)onPlayingFinished;

- (void)onDataReceived:(NSData *)newData
        availRangeFrom:(double)s
                    to:(double)e;

@optional
- (void)onErrorOccured:(NSError *)error;

@end