//
//  Container.m
//  core
//
//  Created by Joshua Gretz on 12/23/10.
//  Copyright 2010 TrueFit Solutions. All rights reserved.
//

#import "Container.h"
#import "Reflection.h"
#import "Mixin.h"

#pragma mark - RegistryMap Helper
@interface RegistryMap : NSObject
@property (assign) Class classType;
@property BOOL cache;
@property (copy) void(^onCreate)();
@end

@implementation RegistryMap
@end

#pragma mark - Private Category
@interface Container() {
	NSMutableDictionary* objectRegistry;
	NSMutableDictionary* mapRegistry;
    
    NSMutableArray* classesSeen;    
    NSMutableArray* conventions;
    
    NSObject* sync;
}

-(id) create: (Class) classType;
-(RegistryMap*) getMapRegisteredForProtocol: (Protocol*) protocol;
-(RegistryMap*) getMapRegisteredForKey: (NSString*) key;

@end

@implementation Container

#pragma mark - Shared Singleton
+(Container*) sharedContainer {
    static Container* sharedContainerInstance;
    
    @synchronized(self) {
        if (!sharedContainerInstance)
            sharedContainerInstance = [[Container alloc] init];
        
        return sharedContainerInstance;
    }
}


#pragma mark - Init
-(id) init {
	if ((self = [super init])) {
		objectRegistry = [[NSMutableDictionary alloc] init];
		mapRegistry = [[NSMutableDictionary alloc] init];
        
        classesSeen = [[NSMutableArray alloc] init];
        
        conventions = [[NSMutableArray alloc] init];
        
        sync = [[NSObject alloc] init];
		
		[self put: self];
	}
	return self;
}

#pragma mark - Create
-(id) create: (Class) classType {
    NSString* className = NSStringFromClass(classType);
    
	id object = [objectRegistry objectForKey: className];
	if (object)
		return object;
	
	object = [[classType alloc] init];
    @synchronized(classesSeen) {
        if (![classesSeen containsObject: className]) {
            [classesSeen addObject: className];
            
            for (ContainerConvention* convention in conventions) {
                if ([convention respondsToEvent: ApplyMixin]) {
                    Class mixinType = [convention classToMixIntoClass: classType];
                    if (mixinType)
                        [Mixin mixClass: mixinType into: classType inherit: NO replaceExistingMethods: NO];
                }
            }
        }
    }
    
	[self inject: object];
	
	return object;
}

#pragma mark - Mapping
-(RegistryMap*) getMapRegisteredForProtocol: (Protocol*) protocol {
	return [mapRegistry valueForKey: NSStringFromProtocol(protocol)];
}

-(RegistryMap*) getMapRegisteredForKey: (NSString*) key {
	return [mapRegistry valueForKey: key];
}

-(id) objectForKey: (NSString*) key {	
	// if we have an object, return it
	id object = [objectRegistry objectForKey: key];
	if (object)
		return object;
	
	// see if we have a mapped class to create
	RegistryMap* map = [self getMapRegisteredForKey: key];
	if (map) {
        object = [self create: map.classType];
        if (object && map.onCreate)
            map.onCreate(object);
        
        if (object && map.cache)
            [self put: object];
        return object;
    }

    // check conventions
    for (ContainerConvention* convention in conventions) {
        if ([convention respondsToEvent: MapClass]) {
            Class mapType = [convention mapKey: key];
            if (mapType)
                return [self objectForClass: mapType];
        }
    }
    
    // nothing found
    return nil;
}

-(id) objectForClass: (Class) classType {
	return [self objectForClass: classType cache: NO];
}

-(id) objectForClass: (Class) classType withPropertyValues: (NSDictionary*) dictionary {
    id object = [self objectForClass: classType];
    
    for (id key in dictionary.keyEnumerator) {
        id value = dictionary[key];
        if (!value)
            continue;
        
        [object setValue: [dictionary objectForKey: key] forKey: key];
    }
    
    return object;
}

-(id) objectForClass: (Class) classType cache: (BOOL) cache {
	id object = [self objectForKey: NSStringFromClass(classType)];
	if (object)
		return object;
    
	object = [self create: classType];	
	if (cache)
		[self put: object];
	
	return object;	
}

-(id) objectForProtocol: (Protocol*) protocol {
    // check explicit map
	RegistryMap* map = [self getMapRegisteredForProtocol: protocol];
	if (map)
        return [self objectForClass: map.classType cache: map.cache];
    
    // check conventions
    for (ContainerConvention* convention in conventions) {
        if ([convention respondsToEvent: MapProtocol]) {
            Class mapType = [convention mapProtocol: protocol];
            if (mapType)
                return [self objectForClass: mapType cache: NO];
        }
    }
    
    // nothing found
    return nil;
}

#pragma mark - Registration
-(void) registerClass: (Class)classType {
    [self registerClass: classType forKey: NSStringFromClass(classType) cache: NO];
}

-(void) registerClass: (Class)classType cache: (BOOL)cache {
    [self registerClass: classType forKey: NSStringFromClass(classType) cache: cache];
}

-(void) registerClass: (Class)classType cache: (BOOL)cache onCreate: (void(^)(id)) onCreate {
    [self registerClass: classType forKey: NSStringFromClass(classType) cache: cache onCreate: onCreate];
}

-(void) registerClass: (Class) classType forProtocol: (Protocol*) protocol {
	[self registerClass: classType forProtocol: protocol cache: NO];
}

-(void) registerClass: (Class) classType forProtocol: (Protocol*) protocol cache: (BOOL) cache {
	[self registerClass: classType forKey: NSStringFromProtocol(protocol) cache: cache];
}

-(void) registerClass: (Class)classType forClass: (Class) keyClass {
    [self registerClass: classType forClass: keyClass cache: NO];
}

-(void) registerClass: (Class)classType forClass: (Class) keyClass cache: (BOOL) cache {
    [self registerClass: classType forKey: NSStringFromClass(keyClass) cache: cache];
}

-(void) registerClass: (Class)classType forKey:(NSString*) key {
	[self registerClass: classType forKey: key cache: NO];
}

-(void) registerClass: (Class)classType forKey:(NSString*) key cache: (BOOL) cache {
    [self registerClass: classType forKey: key cache: cache onCreate: nil];
}

-(void) registerClass: (Class)classType forKey:(NSString*) key cache: (BOOL) cache onCreate:(void (^)(id))onCreate {
	RegistryMap* map = [[RegistryMap alloc] init];
	map.classType = classType;
	map.cache = cache;
    map.onCreate = onCreate;
	
	[mapRegistry setValue: map forKey: key];
}

#pragma mark - Put
-(void) put: (id) object {	
	[objectRegistry setValue: object forKey: NSStringFromClass([object class])];
}

-(void) put: (id) object forKey: (NSString*) key {
	[objectRegistry setValue: object forKey: key];
}

-(void) put: (id) object forClass: (Class) classType {
	[objectRegistry setValue: object forKey: NSStringFromClass(classType)];	
}

-(void) put: (id) object forProtocol: (Protocol*) protocol {
	[self registerClass: [object class] forProtocol: protocol];
	[self put: object];
}

#pragma mark - Injection
-(void) inject: (id) object {
	[self inject: object asClass: [object class]];
}

-(void) inject: (id) object asClass: (Class) classType {
    for (PropertyInfo* propertyInfo in [Reflection propertiesForClass: classType includeInheritance: YES]) {
        if (propertyInfo.readonly)
            continue;
        
        @synchronized(sync) {
            id propertyValue = [self objectForKey: propertyInfo.typeName];         
            if (!propertyValue && propertyInfo.protocol) {                
                RegistryMap* map = [mapRegistry objectForKey: propertyInfo.typeName];
                if (!map)			
                    continue;
                
                propertyValue = [self objectForClass: map.classType cache: map.cache];
            }
            
            if (propertyValue)
                [object setValue: propertyValue forKey: propertyInfo.name];
        }
    }
}

#pragma mark - Conventions
-(void) addConvention:(ContainerConvention *)convention {
    [conventions addObject: convention];
}

@end