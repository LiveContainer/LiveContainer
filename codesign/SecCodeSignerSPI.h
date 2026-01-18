//
//  SecCodeSignerSPI.h
//  codesign
//
//  Created by samsam on 1/15/26.
//

#ifndef SecCodeSignerSPI_h
#define SecCodeSignerSPI_h

#include <CoreFoundation/CoreFoundation.h>

extern const CFStringRef kSecCodeSignerApplicationData;
extern const CFStringRef kSecCodeSignerDetached;
extern const CFStringRef kSecCodeSignerDigestAlgorithm;
extern const CFStringRef kSecCodeSignerDryRun;
extern const CFStringRef kSecCodeSignerEntitlements;
extern const CFStringRef kSecCodeSignerFlags;
extern const CFStringRef kSecCodeSignerForceLibraryEntitlements;
extern const CFStringRef kSecCodeSignerIdentifier;
extern const CFStringRef kSecCodeSignerIdentifierPrefix;
extern const CFStringRef kSecCodeSignerIdentity;
extern const CFStringRef kSecCodeSignerPageSize;
extern const CFStringRef kSecCodeSignerRequirements;
extern const CFStringRef kSecCodeSignerResourceRules;
extern const CFStringRef kSecCodeSignerSDKRoot;
extern const CFStringRef kSecCodeSignerSigningTime;
extern const CFStringRef kSecCodeSignerRequireTimestamp;
extern const CFStringRef kSecCodeSignerTimestampServer;
extern const CFStringRef kSecCodeSignerTimestampAuthentication;
extern const CFStringRef kSecCodeSignerTimestampOmitCertificates;
extern const CFStringRef kSecCodeSignerPreserveMetadata;
extern const CFStringRef kSecCodeSignerTeamIdentifier;
extern const CFStringRef kSecCodeSignerPlatformIdentifier;
extern const CFStringRef kSecCodeSignerRuntimeVersion;
extern const CFStringRef kSecCodeSignerPreserveAFSC;
extern const CFStringRef kSecCodeSignerOmitAdhocFlag;

extern const CFStringRef kSecCodeSignerLaunchConstraintSelf;
extern const CFStringRef kSecCodeSignerLaunchConstraintParent;
extern const CFStringRef kSecCodeSignerLaunchConstraintResponsible;
extern const CFStringRef kSecCodeSignerLibraryConstraint;

extern const CFStringRef kSecCodeSignerEditCpuType;
extern const CFStringRef kSecCodeSignerEditCpuSubtype;
extern const CFStringRef kSecCodeSignerEditCMS;

#endif /* SecCodeSignerSPI_h */
