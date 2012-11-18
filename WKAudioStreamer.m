//
//  WKAudioStreamer.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 11/16/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"
#import <AudioToolbox/AudioToolbox.h>

#define AQBUF_N  5
#define AQBUF_DEFAULT_SIZE  0x25000 // 160kb

// WKAudioStreamer only stores the audio data part as parsed packets.
// Clients could get the original full data (including audio header, ...) with the delegate method onDataReceived:availFrom:to.
//
// WKAudioStreamer uses a two layer caching structure:
// L1: emptyQueueBuffers
// L2: parsedPackets
//
// initial values:
// BOOL audioQueuePaused = YES              set to YES iff:    L2.next == nil and L1.n == AQBUF_N   ("no data" in L1,L2)
//                                                          or playerPlaying = NO                   (paused/finished)
// BOOL playerPlaying = NO
// BOOL finishedFeedingParser = NO          set to YES iff:    no new incoming data from HTTP connection
// BOOL streamerRunning = NO
//
// L1's callback:
// onNewEmptyQueueBufferReceived:      @synchronized (self)
//     push new data onto L1
//     feedL1()
//
// L2's callback:
// onParsedPacketsReceived:            @synchronized (self)
//     push new data onto L2
//     feedL1()
//
// feedL1:                             @synchronized (self)
//     while L2.next != nil and L1.n != 0:
//         buf <- L1.pop()
//         if L2.next.size > buf.capacity:
//             free & allocate buf
//         while L2.next != nil:
//             fill in buf with L2
//             L2.next = L2.next.next
//         enqueue buf
//         if audioQueuePaused and playerPlaying:
//             audioQueue.start()
//             audioQueuePaused = NO
//     if L2.next == nil and L1.n == AQBUF_N:                      // no data in L1,L2
//         if !audioQueuePaused and playerPlaying:                 // not paused by user, audio queue still playing
//             audioQueuePaused = YES
//             audioQueue.pause()
//             if finishedFeedingParser:                           // also no incoming data
//                 playerPlaying = NO
//                 set L2.current to L2.head
//                 send onPlayingFinished to delegate
//
// play:                               @synchronized (self)
//     if playerPlaying: // still playing (maybe still waiting for data)
//         return
//     if !streamerRunning and !finishedFeedingParser:
//         startStreaming
//     playerPlaying = YES
//     if L2.next != nil and L1.n != AQBUF_N: // previously paused by user
//         audioQueue.start()
//         audioQueuePaused = NO
//
// connection:didReceiveData:          @synchronized (self)
//     feed parser
//     send onDataReceived to delegate
//
// connectionDidFinishedLoading:       @synchronized (self)
//     finishedFeedingParser = YES                                 // no new incoming data
//     if audioQueuePaused and playerPlaying:                      // no data in L1,L2; not paused by user
//         playerPlaying = NO
//         set L2.current to L2.head
//         send onPlayerFinished to delegate


@interface WKAudioStreamer () {
@private
    id<WKAudioStreamerDelegate> _delegate;
    NSString *_url;
    
    NSURLConnection *_connection;
    
    AudioFileStreamID _afsID;
    AudioQueueRef _aq;
    AudioQueueBufferRef _aqBufs[AQBUF_N]; // FIXME: remember to call AudioQueueFreeBuffer().
    
    NSMutableArray *_emptyQueueBuffers;
    NSMutableArray *_parsedPackets;
    NSMutableArray *_packetsDesc;
    
    BOOL _audioQueuePaused;
    BOOL _playerPlaying;
    BOOL _finishedFeedingParser;
    BOOL _streamerRunning;
    
    // BOOL _playerReady;
    // BOOL _deferedPause;
    
    int _l2_curIdx;
    
    int _fileSize;
    BOOL _finishedParsingHeader;
    AudioStreamBasicDescription *_streamDesc;
    
    unsigned int _packetCount;
    unsigned int _frameCount;
    UInt32 _bitRate;
    SInt64 _dataOffset;
}

// callbacks
- (void)onParsedPacketsReceived:(const void *)d
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc;
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id;
- (void)onNewEmptyQueueBufferReceived:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer;

- (void)feedL1;

// some helper methods used for seeking
- (UInt32)bitRate;
- (Float64)framesPerPacket;
- (Float64)bytesPerPacket;
@end

static void afs_audio_data_cb(void                          *inClientData,
                              UInt32                        inNumberBytes,
                              UInt32                        inNumberPackets,
                              const void                    *inInputData,
                              AudioStreamPacketDescription  *inPacketDescriptions) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inClientData;
    [s onParsedPacketsReceived:inInputData
                 audioDataSize:inNumberBytes
               numberOfPackets:inNumberPackets
            packetDescriptions:inPacketDescriptions];
}

static void afs_properties_cb(void                         *inClientData,
                              AudioFileStreamID            inAudioFileStream,
                              AudioFileStreamPropertyID    inPropertyID,
                              UInt32                       *ioFlags) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inClientData;
    [s onPropertyAcquired:inPropertyID audioFileStreamID:inAudioFileStream];
}

static void aq_new_buffer_cb(void                 *inUserData,
                             AudioQueueRef        inAQ,
                             AudioQueueBufferRef  inBuffer) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inUserData;
    [s onNewEmptyQueueBufferReceived:inAQ buffer:inBuffer];
}

//
//
// actual implementation
//
//

@implementation WKAudioStreamer

+ (id)streamerWithURLString:(NSString *)url
                   delegate:(id<WKAudioStreamerDelegate>)delegate {
    WKAudioStreamer *streamer = [WKAudioStreamer new];
    streamer->_delegate = delegate;
    streamer->_url = url;
    return streamer;
}

- (NSString *)requestedURL {
    return _url;
}

- (id)init {
    self = [super init];
    if (self != nil) {        
        _emptyQueueBuffers = [NSMutableArray new];
        _parsedPackets = [NSMutableArray new];
        _packetsDesc = [NSMutableArray new];
        
        _dataOffset = -1;
        _l2_curIdx = -1;
        
        _audioQueuePaused = YES;
    }
    return self;
}

- (void)dealloc {
    // if (_aq) {
    //     for (int i = 0; i < AQBUF_N; i++) {
    //         if (_aqBufs[i]) {
    //             AudioQueueFreeBuffer(_aq, _aqBufs[i]);
    //         }
    //     }
    // }
    
    if (_afsID) {
        AudioFileStreamClose(_afsID);
    }
    
    if (_streamDesc) {
        free(_streamDesc);
    }
}

- (void)play {
    @synchronized(self) {
        if (_playerPlaying) {
            return;
        }
        
        if (_connection == nil && !_finishedFeedingParser) {
            [self startStreaming];
        }
        
        _playerPlaying = YES;
        
        if (_aq == NULL && _streamDesc != NULL) {
            // FIXME: error checking
            AudioQueueNewOutput(_streamDesc, aq_new_buffer_cb, (__bridge void *)(self), NULL, NULL, 0, &_aq);
            for (int i = 0; i < AQBUF_N; i++) {
                AudioQueueAllocateBuffer(_aq, AQBUF_DEFAULT_SIZE, &_aqBufs[i]);
                [_emptyQueueBuffers addObject:[NSData dataWithBytes:&_aqBufs[i] length:sizeof(AudioQueueBufferRef)]];
            }
        }
        
        // this should be able to handle the situation of:
        //     1. previously paused
        //     2. calling play after fully streamed
        [self feedL1];
        if (_audioQueuePaused && _aq != NULL) {
            AudioQueueStart(_aq, NULL);
            _audioQueuePaused = NO;
        }
    }
}

- (void)pause {
    // pause will still work even if:
    //     1. the streamer is still streaming the header; or
    //     2. play is not called previously.
    //
    // because we check _playerPlaying first. it would not be YES if play is not called previously; and
    // after play, we are 100% sure that audio queue is created; so pause _aq should have no problem at all.
    @synchronized(self) {
        if (_playerPlaying) {
            if (!_audioQueuePaused) {
                AudioQueuePause(_aq);
                _audioQueuePaused = YES;
            }
            _playerPlaying = NO;
        }
    }
}

- (BOOL)seek:(double)targetTime {
    // FIXME
    return NO;
}

- (double)duration {
    if (_fileSize != 0 && _dataOffset != -1) {
        return (_fileSize - _dataOffset) / [self bitRate] * 8;
    }
    return 0.0;
}

- (void)startStreaming {
    @synchronized(self) {
        if (_connection != nil) {
            return;
        }
        if (!_afsID) {
            // FIXME: add error checking
            AudioFileStreamOpen((__bridge void *)self, afs_properties_cb, afs_audio_data_cb, 0, &_afsID);
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:_url]];
        [req setValue:@"" forHTTPHeaderField:@"User-Agent"];
        _connection = [NSURLConnection connectionWithRequest:req delegate:self];
    }
}

//
// afs callbacks
//

// L2's callback
- (void)onParsedPacketsReceived:(const void *)data
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc {
    @autoreleasepool {
        @synchronized(self) {
            _packetCount += packet_n;
            for (int i = 0; i < packet_n; i++) {
                _frameCount += packet_desc[i].mVariableFramesInPacket;
            }
            
            // NSLog(@"\n-> bit rate: %u", [self bitRate]); // DEBUG
            
            // push data into L2
            for (int i = 0; i < packet_n; i++) {
                NSData *d = [NSData dataWithBytes:data+packet_desc[i].mStartOffset
                                           length:packet_desc[i].mDataByteSize];
                [_parsedPackets addObject:d];
                
                d = [NSData dataWithBytes:packet_desc+i
                                   length:sizeof(AudioStreamPacketDescription)];
                AudioStreamPacketDescription *ds = (AudioStreamPacketDescription *)[d bytes];
                ds->mStartOffset = 0;
                [_packetsDesc addObject:d];
            }
        }
        [self feedL1];
    }
}

- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id {
    @autoreleasepool {
        UInt32 ppt_size;
        AudioFileStreamGetPropertyInfo(afs_id, ppt_id, &ppt_size, nil);
        
        // I will just assume the value could be completely read at once...
        void *buff = malloc(ppt_size);
        UInt32 buff_size = ppt_size;
        // FIXME: error checking?
        AudioFileStreamGetProperty(afs_id, ppt_id, &buff_size, buff);
        
        if (ppt_id == kAudioFileStreamProperty_ReadyToProducePackets) {
            _finishedParsingHeader = YES;
            
            NSLog(@"\n-> finished parsing header."); // DEBUG
            
            NSLog(@"\n-> audio duration: %.2lfs", [self duration]); // DEBUG
            
            // _playerReady = YES;
            // [_delegate onPlayerReady:self];
            
            // FIXME: if streamDesc == nil, fail
            
            // for (int i = 0; i < AQBUF_N; i++) {
            //     AudioQueueAllocateBuffer(_aq, AQBUF_DEFAULT_SIZE, &_aqBufs[i]);
            //     NSData *d = [NSData dataWithBytes:&_aqBufs[i] length:sizeof(_aqBufs[i])];
            //     [_emptyQueueBuffers addObject:d];
            // }
        } else if (ppt_id == kAudioFileStreamProperty_DataFormat) {
            _streamDesc = buff;
            
            @synchronized(self) {
                if (_playerPlaying && _aq == NULL) {
                    // FIXME: check error.
                    AudioQueueNewOutput(_streamDesc, aq_new_buffer_cb, (__bridge void *)(self), NULL, NULL, 0, &_aq);
                    for (int i = 0; i < AQBUF_N; i++) {
                        AudioQueueAllocateBuffer(_aq, AQBUF_DEFAULT_SIZE, &_aqBufs[i]);
                        [_emptyQueueBuffers addObject:[NSData dataWithBytes:&_aqBufs[i] length:sizeof(AudioQueueBufferRef)]];
                    }
                    
                    NSLog(@"\n-> audio queues created in properties' callback");
                }
            }
            
            return; // don't free _streamDesc!
        } else if (ppt_id == kAudioFileStreamProperty_BitRate) {
            _bitRate = *(UInt32 *)buff;
        } else if (ppt_id == kAudioFileStreamProperty_DataOffset) {
            _dataOffset = *(SInt64 *)buff;
        }
        
        // kAudioFileStreamProperty_AudioDataByteCount      and
        // kAudioFileStreamProperty_AudioDataPacketCount
        //
        // seems very helpful as well, but the document didn't specify what will
        // byte count be if there's no valid data available.
        
        // farewell!
        if (buff != NULL) {
            free(buff);
        }
    }
}

- (void)onNewEmptyQueueBufferReceived:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer {
    @autoreleasepool {
        @synchronized(self) {
            NSData *d = [NSData dataWithBytes:&inBuffer length:sizeof(AudioQueueBufferRef)];
            [_emptyQueueBuffers addObject:d];
        }
        [self feedL1];
    }
}

- (void)feedL1 {
    @synchronized(self) {
        // NSLog(@"\n-> feedL1 called!!"); // DEBUG
        while (_l2_curIdx + 1 < [_parsedPackets count] && [_emptyQueueBuffers count] > 0) {
            AudioQueueBufferRef aqbuf = *(AudioQueueBufferRef *)[(NSData *)[_emptyQueueBuffers objectAtIndex:0] bytes];
            [_emptyQueueBuffers removeObjectAtIndex:0];
            aqbuf->mAudioDataByteSize = 0;
            
            NSData *next_packet = [_parsedPackets objectAtIndex:(_l2_curIdx + 1)];
            if (aqbuf->mAudioDataBytesCapacity < [next_packet length]) {
                int cur_buf_idx = -1;
                for (int i = 0; i < AQBUF_N; i++) {
                    if (_aqBufs[i] == aqbuf) {
                        cur_buf_idx = i;
                        break;
                    }
                }
                AudioQueueFreeBuffer(_aq, _aqBufs[cur_buf_idx]);
                AudioQueueAllocateBuffer(_aq, (UInt32)[next_packet length], &aqbuf);
                _aqBufs[cur_buf_idx] = aqbuf;
            }
            
            // while (next_packet != nil &&
            //        aqbuf->mAudioDataByteSize + [next_packet length] <= aqbuf->mAudioDataBytesCapacity) {
            //     memcpy(aqbuf->mAudioData + aqbuf->mAudioDataByteSize,
            //            [next_packet bytes], [next_packet length]);
            //     aqbuf->mAudioDataByteSize += [next_packet length];
            //
            //     _l2_curIdx++;
            //     if (_l2_curIdx + 1 < [_parsedPackets count]) {
            //         next_packet = [_parsedPackets objectAtIndex:(_l2_curIdx + 1)];
            //     } else {
            //         next_packet = nil;
            //     }
            // }
            
            memcpy(aqbuf->mAudioData, [next_packet bytes], [next_packet length]);
            aqbuf->mAudioDataByteSize = (UInt32)[next_packet length];
            const AudioStreamPacketDescription *desc = [[_packetsDesc objectAtIndex:(_l2_curIdx + 1)] bytes];
            
            AudioQueueEnqueueBuffer(_aq, aqbuf, 1, desc);
            _l2_curIdx++;
            
            // NSLog(@"\n-> new audio buffer filled & enqueued"); // DEBUG
            
            if (_playerPlaying && _audioQueuePaused) {
                AudioQueueStart(_aq, NULL);
                _audioQueuePaused = NO;
            }
        }
        
        if (_l2_curIdx + 1 == [_parsedPackets count] && [_emptyQueueBuffers count] == AQBUF_N) {
            if (_playerPlaying && !_audioQueuePaused) {
                AudioQueuePause(_aq);
                _audioQueuePaused = YES;
                if (_finishedFeedingParser) {
                    _playerPlaying = NO;
                    _l2_curIdx = -1;
                    [_delegate onPlayingFinished:self];
                }
            }
        }
    }
}

//
// helper methods for seeking
//

- (UInt32)bitRate {
    if (_bitRate != 0) {
        return _bitRate;
    } else if (_streamDesc != nil) {
        // sample rate: frames / sec
        Float64 sample_rate = _streamDesc->mSampleRate;
        
        Float64 bytes_per_frame = 0;
        if (sample_rate != 0.0f) {
            // (bytes/packet) / (frames/packet) = bytes/frame
            Float64 bytes_per_packet = [self bytesPerPacket];
            Float64 frames_per_packet = [self framesPerPacket];
            if (bytes_per_packet != 0 && frames_per_packet != 0) {
                bytes_per_frame = bytes_per_frame / frames_per_packet;
            }
        }
        
        // (bytes/frame) * (frames/sec) * 8 = bits/sec
        return bytes_per_frame * sample_rate * 8;
    }
    return 0;
}

- (Float64)framesPerPacket {
    if (_streamDesc->mFramesPerPacket) {
        return _streamDesc->mFramesPerPacket;
    } else if (_packetCount != 0) {
        return (Float64)_frameCount / _packetCount;
    }
    return 0;
}

- (Float64)bytesPerPacket {
    if (_streamDesc->mBytesPerPacket) {
        return _streamDesc->mBytesPerPacket;
    } else {
        Float64 t;
        UInt32 _size = sizeof(Float64);
        // FIXME: error checking
        AudioFileStreamGetProperty(_afsID, kAudioFileStreamProperty_AverageBytesPerPacket, &_size, &t);
        return t;
    }
}

//
// NSURLConnection delegate methods
//

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    if (connection != _connection) { return; }
    
    // FIXME: on seeking forward the last parameter has to be kAudioFileStreamParseFlag_Discontinuity.
    AudioFileStreamParseBytes(_afsID, (UInt32)[data length], [data bytes], 0);
    [_delegate onDataReceived:self data:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    if (connection != _connection) { return; }
    @synchronized(self) {
        _finishedFeedingParser = YES;

        _connection = nil;
        [_delegate onStreamingFinished:self];
        
        if (_playerPlaying && _audioQueuePaused) {
            _playerPlaying = NO;
            _l2_curIdx = -1;
            [_delegate onPlayingFinished:self];
        }
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    if (connection != _connection) { return; }
    
    _connection = nil;
    [_delegate onErrorOccured:self error:error];
}

// get response header from the server.
// used for getting the file size.
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    if (connection != _connection) { return; }
    
    NSDictionary *d = [(NSHTTPURLResponse *)response allHeaderFields];
    NSString *content_length_string = [d objectForKey:@"Content-Length"];
    if (content_length_string != nil) {
        _fileSize = [content_length_string intValue];
    }
    
    NSLog(@"\n-> file size: %d bytes.\n", _fileSize);
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)redirectResponse {
    return request; // just redirect.
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection
                  willCacheResponse:(NSCachedURLResponse *)cachedResponse {
    return nil; // don't do caching on response.
}

@end
