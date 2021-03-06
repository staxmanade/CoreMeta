//
//  NSObject+PerformBlock.m
//  CoreMeta
//
//  Created by Joshua Gretz on 12/28/12.
//  Copyright (c) 2012 TrueFit Solutions. All rights reserved.
//

#import "NSObject+Perform.h"

@implementation NSObject (Perform)

-(void) performBlock: (void (^)(void)) block afterDelay:(NSTimeInterval)delay {
    int64_t delta = (int64_t)(1.0e9 * delay);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delta), dispatch_get_main_queue(), block);
}

-(void) performBlockInMainThread: (void (^)(void)) block {
    dispatch_async(dispatch_get_main_queue(), block);
}

-(void) performBlockInBackground: (void (^)(void)) block {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), block);
}

-(void) performSelectorInBackground: (SEL) selector withObject: (id) object afterDelay: (NSTimeInterval) delay {
    [self performBlockInMainThread: ^{
        [self performBlock: ^{
            [self performSelectorInBackground: selector withObject: object];
        } afterDelay: delay];
    }];
}

@end