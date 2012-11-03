//
//  WKController.m
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import "WKController.h"
#import "WKAudioStreamer.h"

static WKAudioStreamer *as = nil;

@implementation WKController

- (IBAction)play:(id)sender {
    NSLog(@"%@", [[self urlField] stringValue]);
}

@end
