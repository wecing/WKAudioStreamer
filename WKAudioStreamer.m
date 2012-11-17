//
//  WKAudioStreamer.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 11/16/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"

@interface WKAudioStreamer ()
// callbacks
- (void)onParsedPacketsReceived:(const void *)d
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc;
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id;
// - (void)onNewEmptyQueueBufferReceived:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer;

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

- (id)init {
    self = [super init];
    if (self != nil) {        
        _emptyQueueBuffers = [NSMutableArray new];
        _parsedPackets = [NSMutableArray new];
        
        _dataOffset = -1;
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
    [self startStreaming];
    
    // FIXME
}

- (void)pause {
    // FIXME
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
- (void)onParsedPacketsReceived:(const void *)d
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc {
    @autoreleasepool {
        _packetCount += packet_n;
        for (int i = 0; i < packet_n; i++) {
            _frameCount += packet_desc[i].mVariableFramesInPacket;
        }
        
        // NSLog(@"\n-> bit rate: %u", [self bitRate]); // DEBUG
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
            
            NSLog(@"\n-> audio duration: %lfs", [self duration]);
            
            // FIXME: if streamDesc == nil, fail
            
            // for (int i = 0; i < AQBUF_N; i++) {
            //     AudioQueueAllocateBuffer(_aq, AQBUF_DEFAULT_SIZE, &_aqBufs[i]);
            //     NSData *d = [NSData dataWithBytes:&_aqBufs[i] length:sizeof(_aqBufs[i])];
            //     [_emptyQueueBuffers addObject:d];
            // }
        } else if (ppt_id == kAudioFileStreamProperty_DataFormat) {
            _streamDesc = buff;
            
            // FIXME: what if data format is never acquired?
            //        check error.
            // AudioQueueNewOutput(_streamDesc, audioqueue_output_cb, (__bridge void *)(self), NULL, NULL, 0, &aqRef);
            
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
    
    [_delegate onStreamingFinished:self];
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
