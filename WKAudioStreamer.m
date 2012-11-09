//
//  WKAudioStreamer.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKAudioStreamer.h"

@interface WKAudioStreamer ()

@property UInt32 bitRate;

- (void)onDecodedAudioReceived:(const void *)d
                 audioDataSize:(UInt32)d_size
               numberOfPackets:(UInt32)packet_n
            packetDescriptions:(AudioStreamPacketDescription *)packet_desc;
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id;

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
void decoded_audio_data_cb(void                          *inClientData,
                           UInt32                        inNumberBytes,
                           UInt32                        inNumberPackets,
                           const void                    *inInputData,
                           AudioStreamPacketDescription  *inPacketDescriptions) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inClientData;
    [s onDecodedAudioReceived:inInputData
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
void decoded_properties_cb(void                         *inClientData,
                           AudioFileStreamID            inAudioFileStream,
                           AudioFileStreamPropertyID    inPropertyID,
                           UInt32                       *ioFlags) {
    WKAudioStreamer *s = (__bridge WKAudioStreamer *)inClientData;
    [s onPropertyAcquired:inPropertyID audioFileStreamID:inAudioFileStream];
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
    streamer->availRangeFrom = streamer->availRangeTo = 0.0f;
    streamer->dataList = [NSMutableArray new];
    streamer->streamDesc = nil;
    streamer->dataOffset = -1;
    streamer->fileSize = 0;
    streamer->packetCount = streamer->frameCount = 0; // streamer->sizeCount = 0;

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

- (void)play {}
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
        
        Float64 bytes_per_frame;
        if (sample_rate != 0.0f) {
            // (bytes/packet) / (frames/packet) = bytes/frame
            bytes_per_frame = [self bytesPerPacket] / [self framesPerPacket];
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
    
    return (Float64)frameCount / packetCount;
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
/////////// callback for the decoder ////////////
/////////////////////////////////////////////////

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
- (void)onDecodedAudioReceived:(const void *)d
                 audioDataSize:(UInt32)d_size
               numberOfPackets:(UInt32)packet_n
            packetDescriptions:(AudioStreamPacketDescription *)packet_desc {
    // sizeCount += d_size;
    packetCount += packet_n;
    for (int i = 0; i < packet_n; i++) {
        frameCount += packet_desc[i].mVariableFramesInPacket;
    }
    
    // FIXME
}

// callback for newly acquired properties.
- (void)onPropertyAcquired:(AudioFilePropertyID)ppt_id
         audioFileStreamID:(AudioFileStreamID)afs_id {
    // get size of the property first.
    UInt32 ppt_size; // in bytes, of course.
    AudioFileStreamGetPropertyInfo(afs_id, ppt_id, &ppt_size, nil);

    // I will just assume the value could be completely read at once...
    void *buff = malloc(ppt_size);
    UInt32 buff_size = ppt_size;
    AudioFileStreamGetProperty(afs_id, ppt_id, &buff_size, buff);
    
    if (ppt_id == kAudioFileStreamProperty_ReadyToProducePackets) {
        // NSLog(@"Ready to produce packets");
    } else if (ppt_id == kAudioFileStreamProperty_DataFormat) {
        streamDesc = buff;
        return; // don't free it!
    } else if (ppt_id == kAudioFileStreamProperty_BitRate) {
        [self setBitRate:*(UInt32 *)buff];
    } else if (ppt_id == kAudioFileStreamProperty_DataOffset) {
        dataOffset = *(SInt64 *)buff;
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

/////////////////////////////////////////////////
//////// NSURLConnectionDelegate methods ////////
/////////////////////////////////////////////////

// data received.
//
// FIXME: need to call the delegate method onDataReceived:availRangeFrom:to.
//        (have to calculate and update availRangeFrom/availRangeTo first)
- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    AudioFileStreamParseBytes(afsID, (UInt32)[data length], [data bytes], 0);
    
    // FIXME
    [self->delegate onDataReceived:data availRangeFrom:0.0f to:0.0f]; // DEBUG
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
