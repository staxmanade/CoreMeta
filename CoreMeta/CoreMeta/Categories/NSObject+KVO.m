//
//  NSObject+KVO.m
//  core
//
//  Created by Joshua Gretz on 4/17/12.
//  Copyright (c) 2012 TrueFit Solutions. All rights reserved.
//

#import "NSObject+KVO.h"
#import <objc/runtime.h>
#import "NSObject+IOC.h"
#import "NSArray+Helpers.h"

#pragma mark NSObject Category
@interface NSObject(KVOPrivate)
@property (retain) NSMutableDictionary* kvoInfo;
@end

@implementation NSObject(KVOPrivate)

const NSString* KVO_INFO = @"KVO_INFO";

-(NSMutableDictionary*) kvoInfo {
    return objc_getAssociatedObject(self, &KVO_INFO);
}

-(void) setKvoInfo: (NSMutableDictionary*) kvoInfo {
    objc_setAssociatedObject(self, &KVO_INFO, kvoInfo, OBJC_ASSOCIATION_RETAIN);
}

@end

#pragma mark Helper Class
@interface Observer : NSObject
@property (copy) NSString* keyPath;
@property (copy) void (^changeBlock)(id, NSDictionary*);
@property (copy) BOOL (^testBlock)(id, NSDictionary*);
@property (assign) BOOL inUse;
@end

@implementation Observer
@end

#pragma mark NSObject(KVO)
@implementation NSObject (KVO)

#pragma mark When
-(void) when: (NSString*) keyPath changes: (void (^)()) block {
    [self when: keyPath changesExecute:^(id object, NSDictionary* changes) { block(); }];
}

-(void) when: (NSString*) keyPath becomes: (BOOL (^)()) testBlock do: (void (^)()) block {
    [self when: keyPath becomes: testBlock execute:^(id object, NSDictionary* changes) { block(); }];
}

-(void) when: (NSString*) keyPath changesExecute: (void (^)(id, NSDictionary*)) block {
    [self when: keyPath becomes: ^BOOL(id object, NSDictionary * changes) { return YES; } execute: block];
}

-(void) when: (NSString*) keyPath becomes: (BOOL (^)(id, NSDictionary*)) testBlock execute: (void (^)(id, NSDictionary *))block {
    @synchronized(self.kvoInfo) {
        if (!self.kvoInfo)
            self.kvoInfo = [NSMutableDictionary dictionary];
        
        NSMutableArray* observers = [self.kvoInfo objectForKey: keyPath];
        if (!observers) {
            observers = [NSMutableArray array];
            [self.kvoInfo setObject: observers forKey: keyPath];
        }
        
        Observer* observer = [observers firstWhere:^BOOL(Observer* evaluatedObject) { return [evaluatedObject.keyPath isEqual: keyPath]; }];
        BOOL exists = observer != nil;
        if (!exists) {
            observer = [Observer object];
            [observers addObject: observer];
        }
        
        observer.keyPath = keyPath;
        observer.changeBlock = block;
        observer.testBlock = testBlock;
        
        if (!exists)
            [self addObserver: self forKeyPath: keyPath options: NSKeyValueObservingOptionNew context: nil];
    }    
}

#pragma mark Clear
-(void) clearKVO {
    @synchronized(self.kvoInfo) {
        if (!self.kvoInfo)
            return;
        
        for (NSString* key in self.kvoInfo.allKeys)
            [self removeObserver: self forKeyPath: key];
        [self.kvoInfo removeAllObjects];
    }
}

-(void) clearKVOForPath: (NSString*) keyPath {
    @synchronized(self.kvoInfo) {
        if (!self.kvoInfo)
            return;
        
        [self.kvoInfo removeObjectForKey: keyPath];
        [self removeObserver: self forKeyPath: keyPath];
    }
}

#pragma mark React Event
-(void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    @synchronized(self.kvoInfo) {
        if (!self.kvoInfo)
            return;
        
        NSMutableArray* observers = [self.kvoInfo objectForKey: keyPath];
        if (!observers)
            return;
        
        for (Observer* observer in observers) {
            if (observer.inUse)
                continue;
            
            observer.inUse = YES;
            if (observer.testBlock(object, change))
                observer.changeBlock(object, change);
            observer.inUse = NO;
        }
    }
}

@end
