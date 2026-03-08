//
//  Utils.cpp
//  feather
//
//  Created by samara on 30.09.2024.
//

#include "Utils.hpp"
#import <Foundation/Foundation.h>

extern "C" {

const char* getDocumentsDirectory() {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	NSString *documentsDirectory = [paths firstObject];
	const char *documentsPath = [documentsDirectory UTF8String];
	return documentsPath;
}

void writeToNSLog(const char* msg) {
    NSLog(@"[LC] singner msg: %s", msg);
}

// copy, remove and rename back the file to prevent crash due to kernel signature cache
// see https://developer.apple.com/documentation/security/updating-mac-software
void refreshFile(const char* path) {
    NSString* objcPath = @(path);
    if(![NSFileManager.defaultManager fileExistsAtPath:objcPath]) {
        return;
    }
    NSString* newPath = [NSString stringWithFormat:@"%s.tmp", path];
    NSError* error;
    [NSFileManager.defaultManager copyItemAtPath:objcPath toPath:newPath error:&error];
    [NSFileManager.defaultManager removeItemAtPath:objcPath error:&error];
    [NSFileManager.defaultManager moveItemAtPath:newPath toPath:objcPath error:&error];
}

}
