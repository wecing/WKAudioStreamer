//
//  WKAudioStreamer.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 11/16/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define AQBUF_N  3
#define AQBUF_DEFAULT_SIZE  0x25000 // 160kb

@protocol WKAudioStreamerDelegate;

@interface WKAudioStreamer : NSObject {
@private
    id<WKAudioStreamerDelegate> _delegate;
    NSString *_url;
    
    NSURLConnection *_connection;
    
    AudioFileStreamID _afsID;
    // AudioQueueRef _aq;
    // AudioQueueBufferRef _aqBufs[AQBUF_N]; // FIXME: remember to call AudioQueueFreeBuffer().
    
    NSMutableArray *_emptyQueueBuffers;
    NSMutableArray *_parsedPackets;
    
    int _fileSize;
    BOOL _finishedParsingHeader;
    AudioStreamBasicDescription *_streamDesc;
    
    unsigned int _packetCount;
    unsigned int _frameCount;
    UInt32 _bitRate;
    SInt64 _dataOffset;
}

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

@end

////////////////////////////////////////////////
///////////////// the delegate /////////////////
////////////////////////////////////////////////

@protocol WKAudioStreamerDelegate <NSObject>

@required
- (void)onStreamingFinished:(WKAudioStreamer *)streamer;
- (void)onPlayingFinished:(WKAudioStreamer *)streamer;

- (void)onDataReceived:(WKAudioStreamer *)streamer
                  data:(NSData *)newData;

@optional
- (void)onErrorOccured:(WKAudioStreamer *)streamer
                 error:(NSError *)error;

@end
