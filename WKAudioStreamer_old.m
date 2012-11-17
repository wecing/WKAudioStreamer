//
//  WKAudioStreamer_old.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"


@interface WKAudioStreamer ()

@property UInt32 bitRate;

- (void)onParsedPacketsReceived:(const void *)d
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc;
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id;
- (void)onNewEmptyQueueBufferReceived:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer;

- (void)feedL1;
// - (void)feedL2;

@end

// AudioFileStream_PacketsProc:
//     callback for decoded audio data.
//
// parameters:
//     inClientData: the "user data" passed to AudioFileStreamOpen().
//     inNumberBytes: number of bytes in inInputData.
//     inNumberPackets: number of packets in inInputData.
//     inInputData: decoded audio data.
//     inPacketDescriptions: an array of AudioStreamPacketDescription structs, each of which describes a packet.
//
// AudioStreamPacketDescription is a struct consists of three elements:
//     SInt64 mStartOffset;   // where the current packet starts in the data buffer.
//     UInt32 mDataByteSize;  // how many bytes are in the packet.
//   and:
//     UInt32 mVariableFramesInPacket;  // number of sample frames of data in the packet.
//                                      // for formats with a fixed number of frames per packet,
//                                      // this field is set to 0.
static void decoded_audio_data_cb(void                          *inClientData,
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

// AudioFileStream_PropertyListenerProc
//     callback for properties.
//
// parameters:
//     inClientData: the "user data" passed to AudioFileStreamOpen().
//     inAudioFileStream: id of the audio file stream parser.
//     inPropertyID: id of the property that is available.
//     ioFlags: not important... it's used to indicate if the properties are cached;
//              but we will save these values ourself.
static void decoded_properties_cb(void                         *inClientData,
                                  AudioFileStreamID            inAudioFileStream,
                                  AudioFileStreamPropertyID    inPropertyID,
                                  UInt32                       *ioFlags) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inClientData;
    [s onPropertyAcquired:inPropertyID audioFileStreamID:inAudioFileStream];
}

// AudioQueueInputCallback
//     callback for the audio queue service to get new data to play.
static void audioqueue_output_cb (void                 *inUserData,
                                  AudioQueueRef        inAQ,
                                  AudioQueueBufferRef  inBuffer) {
    // NSLog(@"dafuq?"); // DEBUG
    WKAudioStreamer *streamer = (__bridge WKAudioStreamer *)inUserData;
    [streamer onNewEmptyQueueBufferReceived:inAQ buffer:inBuffer];
}


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
    // streamer->availRangeFrom = streamer->availRangeTo = 0.0f;
    // streamer->dataList = [NSMutableArray new];
    streamer->streamDesc = nil;
    streamer->dataOffset = -1;
    streamer->fileSize = 0;
    streamer->maxAQBufferSize = 0x50000; // 320kb; this is the value used in Apple's example.
    streamer->packetCount = streamer->frameCount = 0; // streamer->sizeCount = 0;
    streamer->finishedParsingHeader = NO;
    // streamer->aqStarted = NO;
    
    streamer->emptyQueueBuffers = [NSMutableArray new]; // L1
    streamer->parsedPackets = [NSMutableArray new];     // L2
    streamer->availRawData = [NSMutableArray new];      // L3
    // aqBufsSize is initialized after creation of the buffers.
    streamer->parsedPacketsSize = 0;    // L2.SIZE
    // streamer->notUsedAvailDataSize = 0; // L3.SIZE
    streamer->curUsingRawDataIdx = 0;   // L3.curIdx
    streamer->parsedPacketsDesc = [NSMutableArray new]; // L2's info
    streamer->playerPlaying = NO;
    streamer->streamingFinished = NO;

    [streamer setBitRate:0];

    AudioFileStreamOpen((__bridge void *)(streamer), decoded_properties_cb, decoded_audio_data_cb, 0, &(streamer->afsID));
    
    return streamer;
}

- (NSString *)description {
    NSString *s = [super description];
    return [s stringByAppendingFormat:@" songUrl:%@", songUrl];
}

/////////////////////////////////////////////////
/////////////// playback control ////////////////
/////////////////////////////////////////////////

- (void)play { // FIXME: what if playing has finished?
    // @synchronized(self) {
        if (aqStarted) {
            return;
        } /*else if (!finishedParsingHeader) {
            playerPlaying = YES;
        } else if ([emptyQueueBuffers count] != AQBUF_N) { // this is for resuming...
            @synchronized(self) {
                playerPlaying = YES;
                AudioQueueStart(aqRef, NULL);
                aqStarted = YES;
            }
        } else if ([parsedPackets count] != 0) {
            playerPlaying = YES;
            [self feedL1]; // feedL1 will start audio queue for us
        } else {
            // now we know both L1 and L2 are empty.
            // if L3 is also empty, playing has already end.
            // so we could just quit.
            
            // ** L2 is empty **
            // if streaming has not finished, L3 will try to push data onto L2 --
            // feedL2 will be called, then L2's callback will call feedL1; then audio queue will be started.
            //
            // but, what if the remaining data not streamed is not enough to trigger a packet? (ie. tailing packing data)
            // -- well, if so, we could just ignore these data...
            
            // but, if streaming has already stopped...
            // [self feedL2];
            playerPlaying = YES;
            // this must be the craziest code I have ever written...
            [self feedL2]; [self feedL2]; [self feedL2]; [self feedL2]; [self feedL2];
            // [self feedL2]; [self feedL2]; [self feedL2]; [self feedL2]; [self feedL2];
            
            // if (streamingFinished) {
            //     [NSThread ]
            //
            //     while (curUsingRawDataIdx < [availRawData count] && !aqStarted) {
            //         [self feedL2];
            //     }
            // }
           
        }*/

    playerPlaying = YES; // FIXME: what if finished playing?
    
    // }
}
- (void)pause {}
- (void)stop {}

- (double)duration {
    if (fileSize != 0 && dataOffset != -1) {
        return (fileSize - dataOffset) / [self bitRate] * 8;
    }
    return 0.0;
}

// be careful when calling the delegate methods if seeking is implemented.
// @synchronized{} might be necessary to avoid some weird situations.
//
// FIXME: remember to set self->availRangeFrom and self->availRangeTo.
- (BOOL)seek:(double)targetTime {
    
    // FIXME
    
    return YES;
}

/////////////////////////////////////////////////
///////////////// streamer API //////////////////
/////////////////////////////////////////////////

// FIXME:
// what should I do if streaming just stopped and just resend the request will fix?
// (before receiving any data or during streaming)
- (void)startStreaming {
    // without setting User-Agent to empty string, the full HTTP request header is:
    //
    // GET /4/145/63845/537161/01_1771257374_3640897.mp3 HTTP/1.1
    // Host: f3.xiami.net
    // User-Agent: WKAudioStreamer/1 CFNetwork/596.2.3 Darwin/12.2.0 (x86_64) (MacBookAir3%2C2)
    // Accept: */*
    // Accept-Language: en-us
    // Accept-Encoding: gzip, deflate
    // Connection: keep-alive
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:songUrl];
    [req setValue:@"" forHTTPHeaderField:@"User-Agent"];
    connection = [NSURLConnection connectionWithRequest:req delegate:self];
}

/////////////////////////////////////////////////
////////////////// for seeking //////////////////
/////////////////////////////////////////////////

- (UInt32)bitRate {
    if (_bitRate != 0) {
        return _bitRate;
    }

    if (streamDesc != nil) {
        // sample rate: frames / sec
        Float64 sample_rate = streamDesc->mSampleRate;
        
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
    
    return 0; // FIXME: should be calculated
}

- (void)setBitRate:(UInt32)bit_rate {
    _bitRate = bit_rate;
}

- (Float64)framesPerPacket {
    if (streamDesc->mFramesPerPacket) {
        return streamDesc->mFramesPerPacket;
    }
    
    if (packetCount != 0) {
        return (Float64)frameCount / packetCount;
    }
    
    return 0;
}

- (Float64)bytesPerPacket {
    if (streamDesc->mBytesPerPacket) {
        return streamDesc->mBytesPerPacket;
    }
    
    Float64 bytes_per_packet;
    UInt32 _size = sizeof(Float64);
    AudioFileStreamGetProperty(afsID, kAudioFileStreamProperty_AverageBytesPerPacket, &_size, &bytes_per_packet);
    return bytes_per_packet;
}

/////////////////////////////////////////////////
////////////////// feed L1/L2 ///////////////////
/////////////////////////////////////////////////
- (void)feedL1 {
    @synchronized(self) {
        if ([emptyQueueBuffers count] != 0 && [parsedPackets count] != 0) {
            NSData *buf_data = [emptyQueueBuffers lastObject];
            AudioQueueBufferRef buf = *(AudioQueueBufferRef *)[(NSData *)buf_data bytes];
            // AudioQueueBufferRef buf = (__bridge AudioQueueBufferRef)([emptyQueueBuffers lastObject]);
            
            
            NSData *packet = [parsedPackets objectAtIndex:0];
            NSData *desc = [parsedPacketsDesc objectAtIndex:0];
            
            if (buf->mAudioDataBytesCapacity < [packet length]) {
                int i;
                for (i = 0; i < AQBUF_N; i++) {
                    if (aqBufRef[i] == buf) {
                        break;
                    }
                }
                if (i == AQBUF_N) {
                    NSLog(@"We are screwed up!");
                    return;
                }
                AudioQueueFreeBuffer(aqRef, buf);
                OSStatus s = AudioQueueAllocateBuffer(aqRef, (UInt32)[packet length], &aqBufRef[i]);
                if (s != 0) {
                    NSLog(@"Cannot create new buffer?");
                    aqBufRef[i] = NULL;
                    return;
                }
                buf = aqBufRef[i];
            }
            
            // [parsedPackets insertObject:packet atIndex:0];
            [emptyQueueBuffers removeLastObject];
            [parsedPackets removeObjectAtIndex:0];
            [parsedPacketsDesc removeObjectAtIndex:0];
            
            // fill in data
            memcpy(buf->mAudioData, [packet bytes], [packet length]);
            buf->mAudioDataByteSize = (UInt32)[packet length];

            // enqueue
            const AudioStreamPacketDescription *_desc = [desc bytes];
            AudioQueueEnqueueBuffer(aqRef, buf, 1, _desc); // FIXME: only one packet each time? are you sure?
            
            // start
            if (!aqStarted && playerPlaying) {
                AudioQueueStart(aqRef, NULL);
                aqStarted = YES;
            }
        }
    }
}
/*
- (void)feedL2 {
    @synchronized(self) {
        // NSLog(@"hi feedL2!"); // DEBUG
        // NSLog(@"%d | %lu %lu", curUsingRawDataIdx < [availRawData count], parsedPacketsSize, aqBufsSize); // DEBUG
        
        // checking finishedParsingHeader here is for in case audio buffers are not created yet --
        // which means, aqBufsSize is zero.
        if (curUsingRawDataIdx < [availRawData count] && (parsedPacketsSize < aqBufsSize || !finishedParsingHeader)) {
            NSData *data = [availRawData objectAtIndex:curUsingRawDataIdx];
            curUsingRawDataIdx++;
            
            NSLog(@"feedL2() called: [data length] = %lu", [data length]); // DEBUG
            
            // FIXME: "If there is a discontinuity from the last data you passed to the parser, set the
            //         kAudioFileStreamParseFlag_Discontinuity flag."
            AudioFileStreamParseBytes(afsID, (UInt32)[data length], [data bytes], 0);
        }
    }
}*/

/////////////////////////////////////////////////
/////// callback for Audio Queue Service ////////
/////////////////////////////////////////////////

// L1's callback
- (void)onNewEmptyQueueBufferReceived:(AudioQueueRef)inAQ buffer:(AudioQueueBufferRef)inBuffer {
    @autoreleasepool {
        @synchronized(self) {
            // [emptyQueueBuffers addObject:(__bridge id)(inBuffer)];
            NSData *d = [NSData dataWithBytes:&inBuffer length:sizeof(inBuffer)];
            [emptyQueueBuffers addObject:d];
            [self feedL1];
            if ([emptyQueueBuffers count] == AQBUF_N) {
                AudioQueuePause(inAQ);
                aqStarted = NO;
                if (streamingFinished) {
                    NSLog(@"Done!"); // DEBUG
                }
            }
        }
    }
}

/////////////////////////////////////////////////
/////////// callback for the decoder ////////////
/////////////////////////////////////////////////

// L2's callback.
// callback for decoded data.
//
// d: decoded audio data.
// d_size: size of d in bytes.
// packet_n: number of packets in d.
// packet_desc: a array containing description on each packet.
//
// AudioStreamPacketDescription is a struct consists of three elements:
//     SInt64 mStartOffset;   // where the current packet starts in the data buffer.
//     UInt32 mDataByteSize;  // how many bytes are in the packet.
//   and:
//     UInt32 mVariableFramesInPacket;  // number of sample frames of data (wtf?) in the packet.
//                                      // for formats with a fixed number of frames per packet,
//                                      // this field is set to 0.
- (void)onParsedPacketsReceived:(const void *)d
                  audioDataSize:(UInt32)d_size
                numberOfPackets:(UInt32)packet_n
             packetDescriptions:(AudioStreamPacketDescription *)packet_desc {
    @autoreleasepool {
        // do some counting job for seeking
        packetCount += packet_n;
        for (int i = 0; i < packet_n; i++) {
            frameCount += packet_desc[i].mVariableFramesInPacket;
        }
        
        // pushing data into L2
        @synchronized(self) {
            for (int i = 0; i < packet_n; i++) {
                NSData *data = [NSData dataWithBytes:d+packet_desc[i].mStartOffset length:packet_desc[i].mDataByteSize];
                NSData *desc = [NSData dataWithBytes:&packet_desc[i] length:sizeof(AudioStreamPacketDescription)];
                AudioStreamPacketDescription *d = (AudioStreamPacketDescription *)[desc bytes];
                d->mStartOffset = 0;
                [parsedPackets addObject:data];
                [parsedPacketsDesc addObject:desc];
                
                parsedPacketsSize += [data length];
            }
            [self feedL1];
        }
    }
}

// callback for newly acquired properties.
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id {
    @autoreleasepool {
        // get size of the property first.
        UInt32 ppt_size; // in bytes, of course.
        AudioFileStreamGetPropertyInfo(afs_id, ppt_id, &ppt_size, nil);

        // I will just assume the value could be completely read at once...
        void *buff = malloc(ppt_size);
        UInt32 buff_size = ppt_size;
        AudioFileStreamGetProperty(afs_id, ppt_id, &buff_size, buff);
        
        // it seems that in the test case ( http://f3.xiami.net/4/145/63845/537161/01_1771257374_3640897.mp3 ),
        // both MaximumPacketSize and streamDesc->mBytesPerPacket are not valid.
        
        if (ppt_id == kAudioFileStreamProperty_ReadyToProducePackets) {
            finishedParsingHeader = YES;
            // NSLog(@"Finished parsing header"); // DEBUG
            
            // FIXME:
            //     if streamDesc == nil -> fail?
            
            for (int i = 0; i < AQBUF_N; i++) {
                OSStatus s = AudioQueueAllocateBuffer(aqRef, maxAQBufferSize, &aqBufRef[i]);
                // AudioQueueEnqueueBuffer(aqRef, aqBufRef[i], 0, NULL);
                if (s != 0) {
                    NSLog(@"AudioQueueAllocateBuffer returned non-zero: %d", (int)s);
                } else {
                    aqBufsSize += maxAQBufferSize;
                    NSData *d = [NSData dataWithBytes:&aqBufRef[i] length:sizeof(aqBufRef[i])];
                    // [emptyQueueBuffers addObject:(__bridge id)(aqBufRef[i])];
                    [emptyQueueBuffers addObject:d];
                }
            }
        } else if (ppt_id == kAudioFileStreamProperty_DataFormat) {
            streamDesc = buff;
            
            // FIXME: what if data format is never acquired?
            OSStatus s = AudioQueueNewOutput(streamDesc, audioqueue_output_cb, (__bridge void *)(self), NULL, NULL, 0, &aqRef);
            // NSLog(@"new audio queue created."); // DEBUG
            // FIXME: show error if return code is non-zero.
            if (s != 0) {
                NSLog(@"failed to create new audio queue. error code: %d", (int)s); // DEBUG
            }
            
            // NSLog(@"bytes per packet: %u", streamDesc->mBytesPerPacket); // DEBUG
            return; // don't free it!
        } else if (ppt_id == kAudioFileStreamProperty_BitRate) {
            [self setBitRate:*(UInt32 *)buff];
        } else if (ppt_id == kAudioFileStreamProperty_DataOffset) {
            dataOffset = *(SInt64 *)buff;
        } else if (ppt_id == kAudioFileStreamProperty_MaximumPacketSize) {
            maxAQBufferSize = *(UInt32 *)buff;
            // NSLog(@"max aq buffer size: %u", maxAQBufferSize); // DEBUG
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

/////////////////////////////////////////////////
//////// NSURLConnectionDelegate methods ////////
/////////////////////////////////////////////////

// L3's callback.
// data received.
//
// FIXME: need to call the delegate method onDataReceived:availRangeFrom:to.
//        (have to calculate and update availRangeFrom/availRangeTo first)
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // NSLog(@"hi?"); // DEBUG
    
    @synchronized(self) {
        // NSLog(@"hi didReceiveData!"); // DEBUG
        [availRawData addObject:data];
        // notUsedAvailDataSize += [data length];
        
        // [self feedL2];
        AudioFileStreamParseBytes(afsID, (UInt32)[data length], [data bytes], 0);
    }
    
    // FIXME
    [self->delegate onDataReceived:data availRangeFrom:0.0f to:0.0f]; // DEBUG
}

// downloading finished.
//
// this method is supposed to be called after connection:didReceiveData.
// so when it is called, dataList has ready included the last packet.
- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    // FIXME: use availRangeFrom.
    /*
    if (self->availRangeFrom == 0.0f) {
        [self->delegate onStreamingFinished:self fullData:dataList];
    } else {
        [self->delegate onStreamingFinished:self fullData:nil];
    }
     */
    
    // @synchronized(self) {
    //     if (playerPlaying && !aqStarted) {}
    // }
    streamingFinished = YES;
    
    [self->delegate onStreamingFinished:self fullData:availRawData];
}

// oops... challange failed.
- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self->connection = nil;
    [self->delegate onErrorOccured:error];
}

// get response header from the server.
// used for getting the file size.
- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    // "Sent when the connection has received sufficient data
    //  to construct the URL response for its request."
    //
    // wtf?
    NSDictionary *d = [(NSHTTPURLResponse *)response allHeaderFields];
    NSString *content_length_string = [d objectForKey:@"Content-Length"];
    if (content_length_string != nil) {
        fileSize = [content_length_string intValue];
    }
}

/////////////////////////////////////////////////////////////////////////
// the following methods are not that important in this case... sorry! //
/////////////////////////////////////////////////////////////////////////

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
