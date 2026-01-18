//
//  codesigner.m
//  codesign
//
//  Created by samsam on 1/15/26.
//

#import "CodeSigner.h"
#import "SecCodeSignerSPI.h"
#import "SecCodeSigner.h"
#import "SecCode.h"
#import "CSCommon.h"
#import "SecCodePriv.h"
#import "SecStaticCode.h"
#import "CodeSigner.h"
#import <Security/Security.h>
#import <dlfcn.h>
#import <sys/stat.h>
@import Security;

OSStatus SecCodeSignerCreate(CFDictionaryRef, SecCSFlags, SecCodeSignerRef *);
OSStatus SecCodeSignerAddSignatureWithErrors(SecCodeSignerRef, SecStaticCodeRef, SecCSFlags, CFErrorRef *);
typedef CFTypeRef CMSDecoderRef;
OSStatus CMSDecoderCreate(CMSDecoderRef * cmsDecoderOut);
OSStatus CMSDecoderUpdateMessage(CMSDecoderRef cmsDecoder, const void * msgBytes, size_t msgBytesLen);
OSStatus CMSDecoderFinalizeMessage(CMSDecoderRef cmsDecoder);
OSStatus CMSDecoderCopyContent(CMSDecoderRef cmsDecoder, CFDataRef * contentOut);
OSStatus CMSDecoderCopyAllCerts(CMSDecoderRef cmsDecoder, CFArrayRef * certsOut);
CFArrayRef SecCertificateCopyOrganizationalUnit(SecCertificateRef certificate);
CFAbsoluteTime SecCertificateNotValidAfter(SecCertificateRef certificate);

extern CFStringRef kSecPropertyKeyValue;
extern CFStringRef kSecPropertyKeyLabel;
extern CFStringRef kSecOIDAuthorityInfoAccess;

void refreshFile(NSString* objcPath) {
    if(![NSFileManager.defaultManager fileExistsAtPath:objcPath]) {
        return;
    }
    NSString* newPath = [NSString stringWithFormat:@"%@.tmp", objcPath];
    NSError* error;
    [NSFileManager.defaultManager copyItemAtPath:objcPath toPath:newPath error:&error];
    [NSFileManager.defaultManager removeItemAtPath:objcPath error:&error];
    [NSFileManager.defaultManager moveItemAtPath:newPath toPath:objcPath error:&error];
}

NSArray<NSURL *> *allNestedCodePathsSorted(NSURL *bundleURL) {
	NSMutableArray<NSURL *> *results = [NSMutableArray array];
	NSFileManager *fm = [NSFileManager defaultManager];

	NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:bundleURL
								 includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLIsPackageKey]
													options:0
											   errorHandler:nil];

	for (NSURL *fileURL in enumerator) {
		NSString *filename = [fileURL lastPathComponent];
		
		if ([filename hasPrefix:@"."]) continue;

		NSNumber *isDirectory = nil;
		[fileURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
		
		NSString *extension = [[fileURL pathExtension] lowercaseString];

		if (![isDirectory boolValue]) {
			BOOL isMachO = NO;
			if ([extension isEqualToString:@"dylib"]) {
				isMachO = YES;
			} else {
                void* base = NULL;
                const char* path = fileURL.path.UTF8String;
                
                chmod(path, 0755);
                int fd = open(path, O_RDONLY);
                struct stat s;
                fstat(fd, &s);
                if (fd > 0) {
                    base = mmap(NULL, s.st_size, PROT_READ, MAP_SHARED, fd, 0);
                    if (MAP_FAILED == base) {
                        base = NULL;
                    }
                    close(fd);
                }
                
                if(base && s.st_size > 4) {
                    uint32_t magic = *(const uint32_t *)base;
                    if (magic == 0xfeedface || magic == 0xcefaedfe || // 32-bit
                        magic == 0xfeedfacf || magic == 0xcffaedfe || // 64-bit
                        magic == 0xcafebabe || magic == 0xbebafeca) { // Universal/Fat
                        isMachO = YES;
                    }
                }
                munmap(base, s.st_size);
                close(fd);
			}
			
			if (isMachO) {
				[results addObject:fileURL];
			}
		}
	}

	[results sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
		NSUInteger countA = [[a pathComponents] count];
		NSUInteger countB = [[b pathComponents] count];
		
		if (countA > countB) return NSOrderedAscending;
		if (countA < countB) return NSOrderedDescending;
		return [a.path compare:b.path];
	}];

	return results;
}

static NSError *codesign_apply_signature(NSURL *fileURL,
                                         NSDictionary<NSString *, id> *parameters,
                                         BOOL signNested);

NSError *codesign_sign_with_p12(
    NSURL *fileURL,
    SecIdentityRef identity,
    BOOL shallow
                           );

SecIdentityRef readP12Certificate(NSData *p12Data, NSString *p12Password, NSError** error) {
    if (!p12Data) {
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:405
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Missing PKCS#12 data" }];
        return nil;
    }
    
    CFArrayRef items = NULL;
    NSArray* possiblePasswords = @[p12Password, @""];
    BOOL readP12Success = NO;
    OSStatus secStatus;
    for(NSString* password in possiblePasswords) {
        NSDictionary *options = @{ (__bridge id)kSecImportExportPassphrase : password };
        
        secStatus = SecPKCS12Import((__bridge CFDataRef)p12Data, (__bridge CFDictionaryRef)options, &items);
        if (secStatus == errSecSuccess && CFArrayGetCount(items) != 0) {
            readP12Success = YES;
            break;
        }
    }
    if(!readP12Success) {
        if (items) {
            CFRelease(items);
        }
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:406
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Failed to import PKCS#12 data" }];
        return nil;
    }


    CFDictionaryRef identityDict = CFArrayGetValueAtIndex(items, 0);
    SecIdentityRef identity = (SecIdentityRef)CFDictionaryGetValue(identityDict, kSecImportItemIdentity);
    CFRetain(identity);
    CFRelease(items);
    return identity;
}

int codesignAllNested(NSURL *bundleURL,
                      NSData *p12Data,
                      NSString *p12Password,
                      NSProgress* progress,
                      void (^completionHandler)(BOOL success, NSError *error)
                      )
{

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString* g3certStr = @"MIIEUTCCAzmgAwIBAgIQfK9pCiW3Of57m0R6wXjF7jANBgkqhkiG9w0BAQsFADBiMQswCQYDVQQGEwJVUzETMBEGA1UEChMKQXBwbGUgSW5jLjEmMCQGA1UECxMdQXBwbGUgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkxFjAUBgNVBAMTDUFwcGxlIFJvb3QgQ0EwHhcNMjAwMjE5MTgxMzQ3WhcNMzAwMjIwMDAwMDAwWjB1MUQwQgYDVQQDDDtBcHBsZSBXb3JsZHdpZGUgRGV2ZWxvcGVyIFJlbGF0aW9ucyBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTELMAkGA1UECwwCRzMxEzARBgNVBAoMCkFwcGxlIEluYy4xCzAJBgNVBAYTAlVTMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2PWJ/KhZC4fHTJEuLVaQ03gdpDDppUjvC0O/LYT7JF1FG+XrWTYSXFRknmxiLbTGl8rMPPbWBpH85QKmHGq0edVny6zpPwcR4YS8Rx1mjjmi6LRJ7TrS4RBgeo6TjMrA2gzAg9Dj+ZHWp4zIwXPirkbRYp2SqJBgN31ols2N4Pyb+ni743uvLRfdW/6AWSN1F7gSwe0b5TTO/iK1nkmw5VW/j4SiPKi6xYaVFuQAyZ8D0MyzOhZ71gVcnetHrg21LYwOaU1A0EtMOwSejSGxrC5DVDDOwYqGlJhL32oNP/77HK6XF8J4CjDgXx9UO0m3JQAaN4LSVpelUkl8YDib7wIDAQABo4HvMIHsMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgwFoAUK9BpR5R2Cf70a40uQKb3R01/CF4wRAYIKwYBBQUHAQEEODA2MDQGCCsGAQUFBzABhihodHRwOi8vb2NzcC5hcHBsZS5jb20vb2NzcDAzLWFwcGxlcm9vdGNhMC4GA1UdHwQnMCUwI6AhoB+GHWh0dHA6Ly9jcmwuYXBwbGUuY29tL3Jvb3QuY3JsMB0GA1UdDgQWBBQJ/sAVkPmvZAqSErkmKGMMl+ynsjAOBgNVHQ8BAf8EBAMCAQYwEAYKKoZIhvdjZAYCAQQCBQAwDQYJKoZIhvcNAQELBQADggEBAK1lE+j24IF3RAJHQr5fpTkg6mKp/cWQyXMT1Z6b0KoPjY3L7QHPbChAW8dVJEH4/M/BtSPp3Ozxb8qAHXfCxGFJJWevD8o5Ja3T43rMMygNDi6hV0Bz+uZcrgZRKe3jhQxPYdwyFot30ETKXXIDMUacrptAGvr04NM++i+MZp+XxFRZ79JI9AeZSWBZGcfdlNHAwWx/eCHvDOs7bJmCS1JgOLU5gm3sUjFTvg+RTElJdI+mUcuER04ddSduvfnSXPN/wmwLCTbiZOTCNwMUGdXqapSqqdv+9poIZ4vvK7iqF0mDr8/LvOnP6pVxsLRFoszlh6oKw0E6eVzaUDSdlTs=";
        
        NSData* g3certData = [[NSData alloc] initWithBase64EncodedString:g3certStr options:NSDataBase64DecodingIgnoreUnknownCharacters];
        SecCertificateRef g3cert = SecCertificateCreateWithData(nil, (__bridge CFDataRef)g3certData);
        NSMutableDictionary *certificateQuery = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                (__bridge id)kSecClassCertificate, (__bridge id)kSecClass, // Specify the item type is a certificate
                                                 g3cert, kSecValueRef, // The certificate data
                nil];

        OSStatus status = SecItemAdd((__bridge CFDictionaryRef)certificateQuery, NULL);
        
//        __SecCodeSignerCreate = dlsym(RTLD_DEFAULT, "SecCodeSignerCreate");
//        __SecCodeSignerAddSignatureWithErrors = dlsym(RTLD_DEFAULT, "SecCodeSignerAddSignatureWithErrors");
    });
    
    

    NSError* error;
//    if (!__SecCodeSignerCreate || !__SecCodeSignerAddSignatureWithErrors) {
//        error = [NSError errorWithDomain:NSOSStatusErrorDomain
//                                             code:404
//                                         userInfo:@{ NSLocalizedDescriptionKey : @"Failed to load private SecCodeSigner symbols" }];
//        if (completionHandler) {
//            completionHandler(NO, error);
//        }
//        return 404;
//    }
    
    
    SecIdentityRef identity = readP12Certificate(p12Data, p12Password, &error);
    if(error) {
        if (completionHandler) {
            completionHandler(NO, error);
        }
        return 406;
    }
    
    if (!identity) {
        NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                             code:407
                                         userInfo:@{ NSLocalizedDescriptionKey : @"Identity not found in PKCS#12 payload" }];
        if (completionHandler) {
            completionHandler(NO, error);
        }
        return 407;
    }
	
    NSArray<NSURL *> *urls = allNestedCodePathsSorted(bundleURL);
    NSLog(@"Signing: %@", urls);

    if (progress) {
        progress.totalUnitCount = urls.count;
        progress.completedUnitCount = 0;
    }
    NSMutableArray<NSString*>* failedPaths = [NSMutableArray new];
    [urls enumerateObjectsUsingBlock:^(NSURL *url, NSUInteger idx, BOOL *stop) {
        NSLog(@"Signing: %@", url);
        refreshFile(url.path);
        NSError *error = codesign_sign_with_p12(url, identity, YES);
        if (error) {
            [failedPaths addObject:url.path];
        } else {
            refreshFile(url.path);
        }

        if (progress) {
            progress.completedUnitCount = (int64_t)(idx + 1);
        }
    }];

    if (progress) {
        progress.completedUnitCount = progress.totalUnitCount;
    }

    if (completionHandler) {
        if([failedPaths count] > 0) {
            NSString* failedPathStr = [failedPaths componentsJoinedByString:@"\n"];
            NSError *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                 code:407
                                             userInfo:@{ NSLocalizedDescriptionKey : failedPathStr }];
            completionHandler(YES, error);
        }
        completionHandler(YES, nil);
    }

    return 0;
}

static NSError *codesign_apply_signature(NSURL *fileURL,
                                         NSDictionary<NSString *, id> *parameters,
                                         BOOL signNested) {
    SecCodeSignerRef signerRef = NULL;
    SecCSFlags createFlags = signNested ? kSecCSSignNestedCode : 0;

    OSStatus secStatus = SecCodeSignerCreate((__bridge CFDictionaryRef)parameters, createFlags, &signerRef);
    if (secStatus != errSecSuccess || !signerRef) {
        NSString *description = [NSString stringWithFormat:@"SecCodeSignerCreate failed for %@ (OSStatus %d)", fileURL, (int)secStatus];
        return [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:secStatus
                               userInfo:@{ NSLocalizedDescriptionKey : description }];
    }

    SecStaticCodeRef staticCode = NULL;
    secStatus = SecStaticCodeCreateWithPathAndAttributes((__bridge CFURLRef)fileURL,
                                                         kSecCSDefaultFlags,
                                                         (__bridge CFDictionaryRef)@{},
                                                         &staticCode);
    if (secStatus != errSecSuccess || !staticCode) {
        CFRelease(signerRef);
        NSString *description = [NSString stringWithFormat:@"SecStaticCodeCreateWithPathAndAttributes failed for %@ (OSStatus %d)", fileURL, (int)secStatus];
        return [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:secStatus
                               userInfo:@{ NSLocalizedDescriptionKey : description }];
    }

    CFErrorRef errorRef = NULL;
    secStatus = SecCodeSignerAddSignatureWithErrors(signerRef, staticCode, kSecCSDefaultFlags, &errorRef);

    NSError *resultError = nil;
    if (secStatus != errSecSuccess) {
        if (errorRef) {
            resultError = CFBridgingRelease(errorRef);
        } else {
            NSString *description = [NSString stringWithFormat:@"Error signing %@ (OSStatus %d)", fileURL, (int)secStatus];
            resultError = [NSError errorWithDomain:NSOSStatusErrorDomain
                                              code:secStatus
                                          userInfo:@{ NSLocalizedDescriptionKey : description }];
        }
    }

    CFRelease(staticCode);
    CFRelease(signerRef);

    return resultError;
}

NSError *codesign_sign_with_p12(NSURL *fileURL, SecIdentityRef identity, BOOL shallow) {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[(__bridge NSString *)kSecCodeSignerIdentity] = (__bridge id)identity;
    parameters[(__bridge NSString *)kSecCodeSignerIdentifier] = NSBundle.mainBundle.bundleIdentifier;

    NSError *error = codesign_apply_signature(fileURL, parameters, !shallow);
    if (error) {
        NSLog(@"Failed signing %@ with identity: %@", fileURL, error.localizedDescription);
    }

    return error;
}

NSError *codesign_adhoc(NSURL *fileURL, NSString* bundleId, NSData* xmlData) {
    NSMutableDictionary *parameters = [NSMutableDictionary dictionary];
    parameters[(__bridge NSString *)kSecCodeSignerIdentifier] = bundleId ?: @"";
    parameters[(__bridge NSString *)kSecCodeSignerIdentity] = (__bridge id)(kCFNull);

    if (xmlData) {
        uint32_t entitlementsData[xmlData.length + 8];
        entitlementsData[0] = OSSwapHostToBigInt32(0xFADE7171);
        entitlementsData[1] = OSSwapHostToBigInt32((uint32_t)(xmlData.length + 8));
        [xmlData getBytes:&entitlementsData[2] length:xmlData.length];

        parameters[(__bridge NSString *)kSecCodeSignerEntitlements] =
            [NSData dataWithBytes:entitlementsData length:xmlData.length + 8];
    }

    NSError *error = codesign_apply_signature(fileURL, parameters, NO);
    if (error) {
        NSLog(@"Failed ad-hoc signing %@: %@", fileURL, error.localizedDescription);
    }

    return error;
}




@implementation SecuritySigner
+ (NSProgress*)signWithAppURL:(NSURL *)appURL key:(NSData *)key pass:(NSString *)pass
             completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {
    NSProgress* ans = [NSProgress progressWithTotalUnitCount:1000];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            codesignAllNested(appURL, key, pass, ans, completionHandler);
        });
    return ans;
}

+ (BOOL)adhocSignMachOAtPath:(NSURL *)fileURL bundleId:(NSString*)bundleId entitlementData:(NSData *)entitlementData {
    return codesign_adhoc(fileURL, bundleId, entitlementData) == nil;
}

@end


@implementation LCCertWrapper {
    SecCertificateRef cert;
}

+ (instancetype)initWithCertData:(NSData*)certData password:(NSString*)password error:(NSError**)error {
    LCCertWrapper* ans = [self alloc];
    SecIdentityRef identity = readP12Certificate(certData, password, error);
    if(*error || !identity) {
        return nil;
    }

    SecCertificateRef cert;
    OSStatus secStatus = SecIdentityCopyCertificate(identity, &cert);
    if(!cert) {
        NSString *description = [NSString stringWithFormat:@"SecIdentityCopyCertificate failed (OSStatus %d)", (int)secStatus];
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:secStatus
                               userInfo:@{ NSLocalizedDescriptionKey : description }];
        return nil;
    }
    ans->cert = cert;
    return ans;
}

- (NSString*)organizationalUnit {
    CFStringRef ou;

    CFArrayRef ouList = SecCertificateCopyOrganizationalUnit(cert);
    ou = CFArrayGetValueAtIndex(ouList, 0);
    if(CFGetTypeID(ou) != CFStringGetTypeID()) {
        ou = nil;
    }
    return (__bridge NSString *)(ou);
}

- (NSDate*)notValidAfter {
    CFAbsoluteTime notValidAfter = SecCertificateNotValidAfter(cert);
    NSDate *expirationDate = CFBridgingRelease(CFDateCreate(nil, notValidAfter));
    return expirationDate;
}

- (NSString*)checkValidityWithError:(NSError**)error1 {
    CFArrayRef certs = CFArrayCreate(nil, (const void **)(&cert), 1, &kCFTypeArrayCallBacks);
    SecPolicyRef policy = SecPolicyCreateBasicX509();
    SecPolicyRef policy2 = SecPolicyCreateRevocation(kSecRevocationOCSPMethod | kSecRevocationRequirePositiveResponse);
    NSArray* policies = @[(__bridge id)policy, (__bridge id)policy2];
    SecTrustRef trust;
    OSStatus status = SecTrustCreateWithCertificates(certs,(__bridge CFArrayRef)policies, &trust);
    if(status!= errSecSuccess) {
        return 0;
    }
    SecTrustSetNetworkFetchAllowed(trust, true);
    CFErrorRef error = NULL;
    bool isValid = SecTrustEvaluateWithError(trust, &error);
    if(isValid) {
        return @"Valid";
    }
    status = (OSStatus)CFErrorGetCode(error);
    if(status == errSecCertificateRevoked) {
        return @"Revoked";
    } else if (status == errSecCertificateExpired) {
        return @"Expired";
    } else {
        NSLog(@"Trust evaluation failed: %@", (__bridge NSError *)error);
        *error1 = (__bridge NSError*)error;
        return nil;
    }

}

@end

@implementation LCMobileProvisionWarpepr

+ (instancetype)initWithMPData:(NSData*)mpData error:(NSError**)error {
    if (!mpData) {
        return nil;
    }
    CMSDecoderRef decoder = NULL;
    OSStatus secStatus;
    CFDataRef plistData = NULL;
    if ((secStatus = CMSDecoderCreate(&decoder)) == errSecSuccess &&
        (secStatus = CMSDecoderUpdateMessage(decoder, mpData.bytes, mpData.length)) == errSecSuccess &&
        (secStatus = CMSDecoderFinalizeMessage(decoder)) == errSecSuccess &&
        (secStatus = (CMSDecoderCopyContent(decoder, &plistData)) == errSecSuccess) && plistData) {
        
    } else {
        CFRelease(decoder);
        NSString *description = [NSString stringWithFormat:@"CSMDecoder failed (OSStatus %d)", (int)secStatus];
        *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                   code:secStatus
                               userInfo:@{ NSLocalizedDescriptionKey : description }];
        return nil;
    }
    
    CFRelease(decoder);
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:(__bridge NSData *)plistData
                                                                            options:NSPropertyListImmutable
                                                                             format:nil
                                                                              error:error];
    if(!plist) {
        CFRelease(plistData);
        return nil;
    }
    
    LCMobileProvisionWarpepr* wrapper = [LCMobileProvisionWarpepr new];
    wrapper.mpContent = plist;
    return wrapper;
}

- (NSString*)getTeamId {
    NSDictionary *entitlements;
    NSString* provTeamId;
    if(!(entitlements = _mpContent[@"Entitlements"]) || !(provTeamId = entitlements[@"com.apple.developer.team-identifier"])) {
        return nil;
    }
    return provTeamId;
}
@end
