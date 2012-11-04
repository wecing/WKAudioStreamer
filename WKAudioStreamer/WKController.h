//
//  WKController.h
//  WKAudioStreamer
//
//  Created by Chenguang Wang on 10/31/12.
//  Copyright (c) 2012 Chenguang Wang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WKAudioStreamer.h"

@interface WKController : NSObject <WKAudioStreamerDelegate>

@property IBOutlet NSTextField *urlField;

- (IBAction)play:(id)sender;

@end
