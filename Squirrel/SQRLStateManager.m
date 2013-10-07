//
//  SQRLStateManager.m
//  Squirrel
//
//  Created by Justin Spahr-Summers on 2013-10-04.
//  Copyright (c) 2013 GitHub. All rights reserved.
//

#import "SQRLStateManager.h"
#import <ReactiveCocoa/EXTScope.h>

NSString * const SQRLTargetBundleDefaultsKey = @"SQRLTargetBundleDefaultsKey";
NSString * const SQRLUpdateBundleDefaultsKey = @"SQRLUpdateBundleDefaultsKey";
NSString * const SQRLBackupBundleDefaultsKey = @"SQRLBackupBundleDefaultsKey";
NSString * const SQRLApplicationSupportDefaultsKey = @"SQRLApplicationSupportDefaultsKey";
NSString * const SQRLRequirementDataDefaultsKey = @"SQRLRequirementDataDefaultsKey";
NSString * const SQRLStateDefaultsKey = @"SQRLStateDefaultsKey";
NSString * const SQRLWaitForBundleIdentifierDefaultsKey = @"SQRLWaitForBundleIdentifierDefaultsKey";
NSString * const SQRLShouldRelaunchDefaultsKey = @"SQRLShouldRelaunchDefaultsKey";

@interface SQRLStateManager ()

// The identifier for the preferences domain to use.
@property (nonatomic, copy, readonly) NSString *applicationIdentifier;

// Use only while synchronized on `self`.
@property (nonatomic, strong, readonly) NSMutableDictionary *preferences;

@end

@implementation SQRLStateManager

#pragma mark Properties

- (NSURL *)targetBundleURL {
	return [self fileURLForKey:SQRLTargetBundleDefaultsKey];
}

- (void)setTargetBundleURL:(NSURL *)fileURL {
	[self setFileURL:fileURL forKey:SQRLTargetBundleDefaultsKey];
}

- (NSURL *)updateBundleURL {
	return [self fileURLForKey:SQRLUpdateBundleDefaultsKey];
}

- (void)setUpdateBundleURL:(NSURL *)fileURL {
	[self setFileURL:fileURL forKey:SQRLUpdateBundleDefaultsKey];
}

- (NSURL *)backupBundleURL {
	return [self fileURLForKey:SQRLBackupBundleDefaultsKey];
}

- (void)setBackupBundleURL:(NSURL *)fileURL {
	[self setFileURL:fileURL forKey:SQRLBackupBundleDefaultsKey];
}

- (NSURL *)applicationSupportURL {
	return [self fileURLForKey:SQRLApplicationSupportDefaultsKey];
}

- (void)setApplicationSupportURL:(NSURL *)fileURL {
	[self setFileURL:fileURL forKey:SQRLApplicationSupportDefaultsKey];
}

- (NSData *)requirementData {
	return [self objectForKey:SQRLRequirementDataDefaultsKey ofClass:NSData.class];
}

- (void)setRequirementData:(NSData *)data {
	NSParameterAssert(data == nil || [data isKindOfClass:NSData.class]);
	self[SQRLRequirementDataDefaultsKey] = data;
}

- (SQRLShipItState)state {
	NSNumber *number = [self objectForKey:SQRLStateDefaultsKey ofClass:NSNumber.class];
	return number.integerValue;
}

- (void)setState:(SQRLShipItState)state {
	self[SQRLStateDefaultsKey] = @(state);

	if (![self synchronize]) {
		NSLog(@"Failed to synchronize state for manager %@", self);
	}
}

- (NSString *)waitForBundleIdentifier {
	return [self objectForKey:SQRLWaitForBundleIdentifierDefaultsKey ofClass:NSString.class];
}

- (void)setWaitForBundleIdentifier:(NSString *)identifier {
	NSParameterAssert([identifier isKindOfClass:NSString.class]);
	self[SQRLWaitForBundleIdentifierDefaultsKey] = identifier;
}

- (BOOL)relaunchAfterInstallation {
	NSNumber *number = [self objectForKey:SQRLShouldRelaunchDefaultsKey ofClass:NSNumber.class];
	return number.boolValue;
}

- (void)setRelaunchAfterInstallation:(BOOL)shouldRelaunch {
	self[SQRLShouldRelaunchDefaultsKey] = @(shouldRelaunch);
}

#pragma mark Lifecycle

- (id)initWithIdentifier:(NSString *)identifier {
	NSParameterAssert(identifier != nil);

	self = [super init];
	if (self == nil) return nil;

	_applicationIdentifier = [identifier copy];
	NSLog(@"%@ initialized", self);

	NSDictionary *existingPrefs = [NSDictionary dictionaryWithContentsOfURL:[self.class stateURLWithIdentifier:self.applicationIdentifier]];
	_preferences = [existingPrefs mutableCopy] ?: [NSMutableDictionary dictionary];

	return self;
}

- (void)dealloc {
	[self synchronize];
}

#pragma mark Generic Accessors

- (id)objectForKey:(NSString *)key ofClass:(Class)class {
	NSParameterAssert(class != nil);

	id obj = self[key];
	if (obj == nil) return nil;

	NSAssert([obj isKindOfClass:class], @"Key \"%@\" was not associated with an instance of %@: %@", key, class, obj);
	return obj;
}

- (id)objectForKeyedSubscript:(NSString *)key {
	NSParameterAssert(key != nil);

	@synchronized (self) {
		return _preferences[key];
	}
}

- (void)setObject:(id)object forKeyedSubscript:(NSString *)key {
	NSParameterAssert(key != nil);

	@synchronized (self) {
		_preferences[key] = object;
	}
}

- (NSURL *)fileURLForKey:(NSString *)key {
	NSParameterAssert(key != nil);

	NSString *path = [self objectForKey:key ofClass:NSString.class];
	if (path == nil) return nil;

	return [NSURL fileURLWithPath:path];
}

- (void)setFileURL:(NSURL *)fileURL forKey:(NSString *)key {
	NSParameterAssert(key != nil);
	NSParameterAssert(fileURL == nil || [fileURL isFileURL]);

	self[key] = fileURL.filePathURL.path;
}

#pragma mark Synchronization

+ (NSURL *)stateURLWithIdentifier:(NSString *)identifier {
	NSParameterAssert(identifier != nil);

	NSError *error = nil;
	NSURL *folderURL = [NSFileManager.defaultManager URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:&error];
	if (folderURL == nil) {
		NSLog(@"Could not find Application Support URL: %@", error);
		return nil;
	}

	return [[folderURL URLByAppendingPathComponent:identifier] URLByAppendingPathComponent:@"state.plist"];
}

+ (BOOL)clearStateWithIdentifier:(NSString *)identifier {
	NSURL *fileURL = [self stateURLWithIdentifier:identifier];
	NSError *error = nil;
	if (![NSFileManager.defaultManager removeItemAtURL:fileURL error:&error]) {
		NSLog(@"Could not remove %@: %@", fileURL, error);
	}

	return YES;
}

- (BOOL)synchronize {
	NSURL *fileURL = [self.class stateURLWithIdentifier:self.applicationIdentifier];

	@synchronized (self) {
		return [_preferences writeToURL:fileURL atomically:YES];
	}
}

#pragma mark NSObject

- (NSString *)description {
	return [NSString stringWithFormat:@"<%@: %p>{ applicationIdentifier: %@ }", self.class, self, self.applicationIdentifier];
}

@end
