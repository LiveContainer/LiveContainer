#include "zsign.hpp"
#include "common/common.h"
#include "common/json.h"
#include "openssl.h"
#include "macho.h"
#include <libgen.h>
#include <dirent.h>
#include <getopt.h>
#include <stdlib.h>
#include <openssl/ocsp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/ssl.h>
#include <openssl/err.h>
#include <openssl/asn1.h>
#include "timer.h"
#include "common/log.h"
#include "Utils.hpp"
#include "zsigner.h"

// copy, remove and rename back the file to prevent crash due to kernel signature cache
// see https://developer.apple.com/documentation/security/updating-mac-software
void refreshFile(NSString* path) {
    if(![NSFileManager.defaultManager fileExistsAtPath:path]) {
        return;
    }
    NSString* newPath = [NSString stringWithFormat:@"%@.tmp", path];
    NSError* error;
    [NSFileManager.defaultManager copyItemAtPath:path toPath:newPath error:&error];
    [NSFileManager.defaultManager removeItemAtPath:path error:&error];
    [NSFileManager.defaultManager moveItemAtPath:newPath toPath:path error:&error];
}


extern "C" {

int checkCert(NSData *key,
              NSString *pass,
              void(^completionHandler)(int status, NSDate* expirationDate, NSString* organizationalUnitName, NSString *error)) {
    const char* strPKeyFileData = (const char*)[key bytes];

    string strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
    
    ZLog::clearLogs();

    __block ZSignAsset zSignAsset;
    
    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[key length], nil, 0, strPassword)) {
        ZLog::clearLogs();
        completionHandler(2, nil, nil, @"Unable to initialize certificate. Please check your password.");
        return -1;
    }
    
    X509* cert = (X509*)zSignAsset.m_x509Cert;
    BIO *brother1;
    unsigned long issuerHash = X509_issuer_name_hash((X509*)cert);
    if (0x817d2f7a == issuerHash) {
        brother1 = BIO_new_mem_buf(ZSignAsset::s_szAppleDevCACert, (int)strlen(ZSignAsset::s_szAppleDevCACert));
    } else if (0x9b16b75c == issuerHash) {
        brother1 = BIO_new_mem_buf(ZSignAsset::s_szAppleDevCACertG3, (int)strlen(ZSignAsset::s_szAppleDevCACertG3));
    } else {
        completionHandler(2, nil, nil, @"Unable to determine issuer of the certificate. Is it signed by Apple Developer?");
        return -2;
    }
    
    if (!brother1)
    {
        completionHandler(2, nil, nil, @"Unable to initialize issuer certificate.");
        return -3;
    }
    
    X509 *issuer = PEM_read_bio_X509(brother1, NULL, 0, NULL);
    
    if (!cert || !issuer) {
        completionHandler(2, nil, nil, @"Error loading cert or issuer");
        return -4;
    }

    
    // Extract OCSP URL from cert
    STACK_OF(ACCESS_DESCRIPTION)* aia = (STACK_OF(ACCESS_DESCRIPTION)*)X509_get_ext_d2i((X509*)cert, NID_info_access, 0, 0);
    if (!aia) {
        completionHandler(2, nil, nil, @"No AIA (OCSP) extension found in certificate");
        return -5;
    }
    
    ASN1_IA5STRING* uri = nullptr;
    for (int i = 0; i < sk_ACCESS_DESCRIPTION_num(aia); i++) {
        ACCESS_DESCRIPTION* ad = sk_ACCESS_DESCRIPTION_value(aia, i);
        if (OBJ_obj2nid(ad->method) == NID_ad_OCSP &&
            ad->location->type == GEN_URI) {
            uri = ad->location->d.uniformResourceIdentifier;
            
            break;
        }
    }

    
    if (!uri) {
        completionHandler(2, nil, nil, @"No OCSP URI found in certificate.");
        return -6;
    }

    OCSP_REQUEST* req = OCSP_REQUEST_new();
    OCSP_CERTID* cert_id = OCSP_cert_to_id(nullptr, (X509*)cert, issuer);
    OCSP_request_add0_id(req, cert_id);  // Ownership transferred to request
    cert_id = OCSP_cert_to_id(nullptr, (X509*)cert, issuer);
    unsigned char* der = 0;
    int len = i2d_OCSP_REQUEST(req, &der);

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:(const char *)uri->data]]];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[NSData dataWithBytes:der length:len]];
    [request setValue:@"application/ocsp-request" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/ocsp-response" forHTTPHeaderField:@"Accept"];
    
    OPENSSL_free(der);
    if (aia) {
        sk_ACCESS_DESCRIPTION_pop_free(aia, ACCESS_DESCRIPTION_free);
    }
    OCSP_REQUEST_free(req);
    X509_free(issuer);
    BIO_free(brother1);

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData * _Nullable data,
                                                                NSURLResponse * _Nullable response,
                                                                NSError * _Nullable error) {
        if (error) {
            completionHandler(2, nil, nil, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode == 200 && data) {
            // You can save `data` or parse the response
            const void *respBytes = [data bytes];
            OCSP_RESPONSE *resp = 0;
            d2i_OCSP_RESPONSE(&resp, (const unsigned char**)&respBytes, data.length);
            if(!resp) {
                completionHandler(2, nil, nil, @"Failed to decode OCSP response.");
                return;
            }
            OCSP_BASICRESP *basic = OCSP_response_get1_basic(resp);
            ASN1_TIME *expirationDateAsn1 = X509_get_notAfter(cert);
            NSString* organizationalUnitName = nil;
            X509_NAME* subject_name = X509_get_subject_name(cert);
            int ouIndex = X509_NAME_get_index_by_NID(subject_name, NID_organizationalUnitName, -1);
            if(ouIndex >= 0) {
                X509_NAME_ENTRY* ext = X509_NAME_get_entry(subject_name, ouIndex);
                ASN1_STRING* ouAsn1Str = X509_NAME_ENTRY_get_data(ext);
                organizationalUnitName = @((const char*)ASN1_STRING_get0_data(ouAsn1Str));
            }
            NSLog(@"organizationalUnitName = %@", organizationalUnitName);
            NSString *fullDateString = [NSString stringWithFormat:@"20%s", expirationDateAsn1->data];

            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyyMMddHHmmss'Z'";
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            formatter.locale = NSLocale.currentLocale;
            NSDate *expirationDate = [formatter dateFromString:fullDateString];

            int status, reason;
            if (OCSP_resp_find_status(basic, cert_id, &status, &reason, NULL, NULL, NULL)) {
                completionHandler(status, expirationDate, organizationalUnitName, nil);
            } else {
                completionHandler(2, expirationDate, organizationalUnitName, nil);
            }
            
            OCSP_CERTID_free(cert_id);
            OCSP_BASICRESP_free(basic);
            OCSP_RESPONSE_free(resp);
            
            
        } else {
            completionHandler(2, nil, nil, @"Invalid response or no data");
            return;
        }
    }];

    [task resume];
    return 1;
}

@implementation ZSigner
+ (NSProgress*)signMachOPathArr:(NSArray<NSString*>*)machoPathArr bundleId:(NSString *)bundleId cert:(NSData *)key
                            pass:(NSString *)pass completionHandler:(void(^)(BOOL success, NSError *error))completionHandler {
    NSProgress* progress = [NSProgress progressWithTotalUnitCount:(int64_t)machoPathArr.count];
    ZLog::clearLogs();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        ZSignAsset* pSignAsset = new ZSignAsset();
        const char* strPKeyFileData = (const char*)[key bytes];
        const char* strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
        string strBundleId(bundleId.UTF8String);

        bool ret = pSignAsset->InitSimple(strPKeyFileData, (int)[key length], nil, 0, strPassword);
        if (!ret) {
            delete pSignAsset;
            NSError* initError = [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:@{
                NSLocalizedDescriptionKey: @"Failed to initialize zSignAsset. Maybe wrong password?"
            }];
            dispatch_async(dispatch_get_main_queue(), ^{
                completionHandler(NO, initError);
            });
            return;
        }

        NSMutableArray<NSString *>* errorList = [NSMutableArray new];
        // serialQueue serializes errorList writes and progress updates from concurrent tasks
        dispatch_queue_t serialQueue = dispatch_queue_create("com.zsign.signqueue", DISPATCH_QUEUE_SERIAL);
        dispatch_group_t group = dispatch_group_create();
        dispatch_queue_t concurrentQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

        for (NSString* machoPath in machoPathArr) {
            dispatch_group_async(group, concurrentQueue, ^{
                ZMachO* macho = new ZMachO();
                NSString* errorMsg = nil;
                refreshFile(machoPath);
                if (!macho->Init(machoPath.UTF8String)) {
                    ZLog::ErrorV(">>> Invalid mach-o file! %s\n", machoPath.UTF8String);
                    errorMsg = [NSString stringWithFormat:@"Invalid mach-o file! %@", machoPath];
                } else {
                    bool bRet = macho->Sign(pSignAsset, true, strBundleId, "", "", "");
                    if (!bRet) {
                        errorMsg = [NSString stringWithFormat:@"Failed to Sign %@", machoPath];
                    } else {
                        refreshFile(machoPath);
                    }
                }
                delete macho;

                // Serialize errorList mutation and progress counter increment
                dispatch_sync(serialQueue, ^{
                    if (errorMsg) {
                        [errorList addObject:errorMsg];
                    }
                    progress.completedUnitCount++;
                });
            });
        }

        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);

        delete pSignAsset;
        if (errorList.count > 0) {
            NSError* signingError = [NSError errorWithDomain:@"Failed to Sign" code:-1 userInfo:@{
                NSLocalizedDescriptionKey: [errorList componentsJoinedByString:@"\n"]
            }];
            completionHandler(NO, signingError);
        } else {
            completionHandler(YES, nil);
        }

    });

    return progress;
}

+ (NSProgress*)signWithAppPath:(NSString *)appPath bundleId:(NSString *)bundleId cert:(NSData *)key pass:(NSString *)pass
             completionHandler:(void (^)(BOOL success, NSError *error))completionHandler {

    NSURL* bundleURL = [NSURL fileURLWithPath:appPath];
        
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:bundleURL includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:nil];
    NSMutableArray* filesToSign = [NSMutableArray new];
    
    NSError* error;
    
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        if (![fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:&error] || ![isRegularFile boolValue]) {
            continue;
        }
        if(!is_64bit_macho(fileURL.path.UTF8String)) {
            continue;
        }
        [filesToSign addObject:fileURL.path];
    }
    
    return [ZSigner signMachOPathArr:filesToSign bundleId:bundleId cert:key pass:pass completionHandler:completionHandler];
}

+ (BOOL)adhocSignMachOAtPath:(NSString *)path bundleId:(NSString*)bundleId entitlementData:(NSData *)entitlementData {
    ZLog::clearLogs();
    
    ZSignAsset zSignAsset;
    zSignAsset.InitAdhoc([entitlementData bytes], (int)[entitlementData length]);
    
    ZMachO* macho = new ZMachO();
    if (!macho->Init(path.UTF8String)) {
        ZLog::ErrorV(">>> Invalid mach-o file! %s\n", path.UTF8String);
        return false;
    }

    string strInfoSHA1;
    string strInfoSHA256;
    string strCodeResourcesData;
    string strBundleId(bundleId.UTF8String);
    bool bRet = macho->Sign(&zSignAsset, true, strBundleId, strInfoSHA1, strInfoSHA256, strCodeResourcesData);
    return bRet;
}

// this method is used to get teamId for ADP/Enterprise certs ,don't use it in normal jitless
+ (NSString*)getTeamIdWithCert:(NSData *)cert pass:(NSString *)pass {
    string strPassword;

    const char* strPKeyFileData = (const char*)[cert bytes];

    strPassword = [pass cStringUsingEncoding:NSUTF8StringEncoding];
    
    ZLog::clearLogs();

    __block ZSignAsset zSignAsset;
    
    if (!zSignAsset.InitSimple(strPKeyFileData, (int)[cert length], nil, 0, strPassword)) {
        ZLog::clearLogs();
        return nil;
    }
    NSString* teamId = [NSString stringWithUTF8String:zSignAsset.m_strTeamId.c_str()];
    return teamId;
}

+ (int)checkCert:(NSData *)cert pass:(NSString *)pass completionHandler:(void(^)(int status, NSDate* expirationDate, NSString* organizationalUnitName, NSString *error))completionHandler {
    return checkCert(cert, pass, completionHandler);
}
@end

}
