//
//  NSOperationQueue+LAUtils.m
//  Letters
//
//  Created by Jim Puls on 1/23/10.
//  Copyright 2010 Letters App. All rights reserved.
//

#import "NSOperationQueue+LAUtils.h"

@implementation NSOperationQueue(LAUtils)

+ (id) globalOperationQueue {
    @synchronized([NSOperationQueue class]) {
        static NSOperationQueue *sharedQueue = nil;
        if (!sharedQueue) {
            sharedQueue = [NSOperationQueue new];
        }
        return sharedQueue;
    }
}

@end
