/*
 * Copyright (c) 2006-2014 Apple Inc. All Rights Reserved.
 * 
 * @APPLE_LICENSE_HEADER_START@
 * 
 * This file contains Original Code and/or Modifications of Original Code
 * as defined in and that are subject to the Apple Public Source License
 * Version 2.0 (the 'License'). You may not use this file except in
 * compliance with the License. Please obtain a copy of the License at
 * http://www.opensource.apple.com/apsl/ and read it before using this
 * file.
 * 
 * The Original Code and all software distributed under the License are
 * distributed on an 'AS IS' basis, WITHOUT WARRANTY OF ANY KIND, EITHER
 * EXPRESS OR IMPLIED, AND APPLE HEREBY DISCLAIMS ALL SUCH WARRANTIES,
 * INCLUDING WITHOUT LIMITATION, ANY WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, QUIET ENJOYMENT OR NON-INFRINGEMENT.
 * Please see the License for the specific language governing rights and
 * limitations under the License.
 * 
 * @APPLE_LICENSE_HEADER_END@
 */

/*!
	@header SecCodeSigner
	SecCodeSigner represents an object that can sign code.
*/
#ifndef _H_SECCODESIGNER
#define _H_SECCODESIGNER

#include "CSCommon.h"

#ifdef __cplusplus
extern "C" {
#endif

/*!
	@typedef SecCodeSignerRef
	This is the type of a reference to a code requirement.
*/
#ifdef BRIDGED_SECCODESIGNER
typedef struct CF_BRIDGED_TYPE(id) __SecCodeSigner *SecCodeSignerRef
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#else
typedef struct __SecCodeSigner *SecCodeSignerRef
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#endif


/*!
	@function SecCodeGetTypeID
	Returns the type identifier of all SecCodeSigner instances.
*/
CFTypeID SecCodeSignerGetTypeID(void)
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

/*!
	The following CFString constants can be used as keys in the parameters argument
	of SecCodeSignerCreate to specify various modes and options of the signing operation.
	Passing any keys not specified here may lead to undefined behavior and is not supported.
	The same applies to passing objects of types not explicitly allowed here.

	@constant kSecCodeSignerDetached Determines where the signature is written.
		If this key is absent, the code being signed is modified to contain the signature,
		replacing any signature already embedded there.
		If the value is kCFNull, the signature is written to the system-wide detached
		signature database. (You must have root privileges to write there.)
		If the value of this key is a CFURL, the signature is written to a file at that location,
		replacing any data there.
		If the value is a CFMutableData, the signature is appended to that data.
	@constant kSecCodeSignerDryRun A boolean value. If present and true, the actual writing
		of the signature is inhibited, and the code is not modified, but all operations
		leading up to this are performed normally, including the cryptographic access to
		the signing identity (if any).
	@constant kSecCodeSignerFlags A CFNumber specifying which flags to set in the code signature.
		Note that depending on circumstances, this value may be augmented or modified
		as part of the signing operation.
 	@constant kSecCodeSignerForceLibraryEntitlements A boolean value. If true, and entitlements
 		are present, entitlements will be included in signature of libraries (non-main executables).
	@constant kSecCodeSignerIdentifier If present, a CFString that explicitly specifies
		the unique identifier string sealed into the code signature. If absent, the identifier
		is derived implicitly from the code being signed.
	@constant kSecCodeSignerIdentifierPrefix If the unique identifier string of the code signature
		is implicitly generated, and the resulting string does not contain any "." (dot)
		characters, then the (string) value of this parameter is prepended to the identifier.
		By convention, the prefix is usually of the form "com.yourcompany.", but any value
		is acceptable. If the kSecCodeSignerIdentifier parameter is specified, this parameter
		is ineffective (but still allowed).
	@constant kSecCodeSignerIdentity A SecIdentityRef describing the signing identity
		to use for signing code. This is a mandatory parameter for signing operations.
		Its value must be either a SecIdentityRef specifying a cryptographic identity
		valid for Code Signing, or the special value kCFNull to indicate ad-hoc signing.
	@constant kSecCodeSignerOperation The type of operation to be performed. Valid values
		are kSecCodeSignerOperationSign to sign code, and kSecCodeSignerOperationRemove
		to remove any existing signature from code. The default operation is to sign code.
	@constant kSecCodeSignerPageSize An integer value explicitly specifying the page size
		used to sign the main executable. This must be a power of two. A value of zero indicates
		infinite size (no paging).
		Only certain page sizes are allowed in most circumstances, and specifying an inappropriate
		size will lead to spurious verification failures. This is for expert use only.
	@constant kSecCodeSignerRequirements Specifies the internal requirements to be sealed into
		the code signature. Must be either a CFData containing the binary (compiled) form of
		a requirements set (SuperBlob), or a CFString containing a valid text form to be
		compiled into binary form. Default requirements are automatically generated if this
		parameter is omitted, and defaults may be applied to particular requirement types
		that are not specified; but any requirement type you specify is sealed exactly as
		specified.
	@constant kSecCodeSignerResourceRules A CFDictionary containing resource scanning rules
		determining what resource files are sealed into the signature (and in what way).
		A situation-dependent default is applied if this parameter is not specified.
	@constant kSecCodeSignerSDKRoot A CFURLRef indicating an alterate directory root
		where signing operations should find subcomponents (libraries, frameworks, modules, etc.).
		The default is the host system root "/".
	@constant kSecCodeSignerSigningTime Specifies what date and time is sealed into the
		code signature's CMS data. Can be either a CFDate object specifying a date, or
		the value kCFNull indicating that no date should be included in the signature.
		If not specified, the current date is chosen and sealed.
		Since an ad-hoc signature has no CMS data, this argument is ineffective
		for ad-hoc signing operations.
	@constant kSecCodeSignerRequireTimestamp A CFBoolean indicating (if kCFBooleanTrue) that
		the code signature should be certified by a timestamp authority service. This option
		requires access to a timestamp server (usually over the Internet). If requested and
		the timestamp server cannot be contacted or refuses service, the signing operation fails.
		The timestamp value is not under the caller's control.
		If the value is kCFBooleanFalse, no timestamp service is contacted and the resulting signature
		has no certified timestamp.
		If this key is omitted, a default is used that may vary from release to release.
		Note that when signing multi-architectural ("fat") programs, each architecture will
		be signed separately, and thus each architecture will have a slightly different timestamp.
	@constant kSecCodeSignerTimestampServer A CFURL specifying which timestamp authority service
		to contact for timestamping if requested by the kSecCodeSignerRequireTimestamp argument.
		If omitted (and timestamping is performed), a system-defined default value is used, referring
		to an Apple-operated timestamp service. Note that this service may not freely serve all requests.
	@constant kSecCodeSignerTimestampAuthentication A SecIdentityRef describing the identity
        used to authenticate to the timestamp authority server, if the server requires client-side
		(SSL/TLS) authentication. This will not generally be the identity used to sign the actual
		code, depending on the requirements of the timestamp authority service used.
		If omitted, the timestamp server is contacted using unauthenticated HTTP requests.
	@constant kSecCodeSignerTimestampOmitCertificates A CFBoolean indicating (if kCFBooleanTrue)
		that the timestamp embedded in the signature, if requested, not contain the full certificate chain
		of the timestamp service used. This will make for a marginally smaller signature, but may not
		verify correctly unless all such certificates are available (through the keychain system)
		on the verifying system.
		The default is to embed enough certificates to ensure proper verification of Apple-generated
		timestamp signatures.
	@constant kSecCodeSignerRuntimeVersion A CFString indicating the version of runtime hardening policies
		that the process should be opted into. The string should be of the form "x", "x.x", or "x.x.x" where
		x is a number between 0 and 255. This parameter is optional. If the signer specifies
		kSecCodeSignatureRuntime but does not provide this parameter, the runtime version will be the SDK
		version built into the Mach-O.

 */
extern const CFStringRef kSecCodeSignerApplicationData
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerDetached
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerDigestAlgorithm
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerDryRun
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerEntitlements
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerFlags
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerForceLibraryEntitlements
SPI_AVAILABLE(macos(15.0), ios(18.0), macCatalyst(18.0));

extern const CFStringRef kSecCodeSignerIdentifier
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerIdentifierPrefix
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerIdentity
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerPageSize
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerRequirements
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerResourceRules
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerSDKRoot
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerSigningTime
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerTimestampAuthentication
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerRequireTimestamp
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerTimestampServer
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerTimestampOmitCertificates
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerPreserveMetadata
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerTeamIdentifier
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerPlatformIdentifier
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerRuntimeVersion
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerPreserveAFSC
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerOmitAdhocFlag
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerEditCpuType
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerEditCpuSubtype
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerEditCMS
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));

extern const CFStringRef kSecCodeSignerLaunchConstraintSelf
SPI_AVAILABLE(macos(13.0), ios(16.0), macCatalyst(16.0));

extern const CFStringRef kSecCodeSignerLaunchConstraintParent
SPI_AVAILABLE(macos(13.0), ios(16.0), macCatalyst(16.0));

extern const CFStringRef kSecCodeSignerLaunchConstraintResponsible
SPI_AVAILABLE(macos(13.0), ios(16.0), macCatalyst(16.0));

extern const CFStringRef kSecCodeSignerLibraryConstraint
SPI_AVAILABLE(macos(14.0), ios(17.0), macCatalyst(17.0));

enum {
    kSecCodeSignerPreserveIdentifier = 1 << 0,		// preserve signing identifier
    kSecCodeSignerPreserveRequirements = 1 << 1,	// preserve internal requirements (including DR)
    kSecCodeSignerPreserveEntitlements = 1 << 2,	// preserve entitlements
    kSecCodeSignerPreserveResourceRules = 1 << 3,	// preserve resource rules (and thus resources)
    kSecCodeSignerPreserveFlags = 1 << 4,			// preserve signing flags
	kSecCodeSignerPreserveTeamIdentifier = 1 << 5,  // preserve team identifier flags
	kSecCodeSignerPreserveDigestAlgorithm = 1 << 6, // preserve digest algorithms used
	kSecCodeSignerPreservePEH = 1 << 7,				// preserve pre-encryption hashes
	kSecCodeSignerPreserveRuntime = 1 << 8,         // preserve the runtime version
	kSecCodeSignerPreserveLaunchConstraints = 1 << 9, // preserve embedded launch constraints
    kSecCodeSignerPreserveLibraryConstraints = 1 << 10, // preserve embedded library constraints
};


/*!
	@function SecCodeSignerCreate
	Create a (new) SecCodeSigner object to be used for signing code.

	@param parameters An optional CFDictionary containing parameters that influence
		signing operations with the newly created SecCodeSigner. If NULL, defaults
		are applied to all parameters; note however that some parameters do not have
		useful defaults, and will need to be set before signing is attempted.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
		The kSecCSRemoveSignature flag requests that any existing signature be stripped
		from the target code instead of signing. The kSecCSEditSignature flag
        requests editing of existing signatures, which only works with a very
        limited set of options.
	@param staticCode On successful return, a SecStaticCode object reference representing
	the file system origin of the given SecCode. On error, unchanged.
	@result Upon success, errSecSuccess. Upon error, an OSStatus value documented in
	CSCommon.h or certain other Security framework headers.
*/
enum {
	kSecCSRemoveSignature = 1 << 0,		// strip existing signature
	kSecCSSignPreserveSignature = 1 << 1, // do not (re)sign if an embedded signature is already present
	kSecCSSignNestedCode = 1 << 2,		// recursive (deep) signing
	kSecCSSignOpaque = 1 << 3,			// treat all files as resources (no nest scan, no flexibility)
	kSecCSSignV1 = 1 << 4,				// sign ONLY in V1 form
	kSecCSSignNoV1 = 1 << 5,			// do not include V1 form
	kSecCSSignBundleRoot = 1 << 6,		// include files in bundle root
	kSecCSSignStrictPreflight = 1 << 7, // fail signing operation if signature would fail strict validation
	kSecCSSignGeneratePEH = 1 << 8,		// generate pre-encryption hashes
    kSecCSSignGenerateEntitlementDER = 1 << 9, // generate entitlement DER
    kSecCSEditSignature = 1 << 10,      // edit existing signature
	kSecCSSingleThreadedSigning = 1 << 11, // disable concurrency when building the resource seal
};

#ifdef BRIDGED_SECCODESIGNER
OSStatus SecCodeSignerCreate(CFDictionaryRef parameters, SecCSFlags flags,
	SecCodeSignerRef * __nonnull CF_RETURNS_RETAINED signer)
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#else
OSStatus SecCodeSignerCreate(CFDictionaryRef parameters, SecCSFlags flags,
	SecCodeSignerRef *signer)
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
#endif

/*!
	@function SecCodeSignerAddSignature
	Create a code signature and add it to the StaticCode object being signed.

	@param signer A SecCodeSigner object containing all the information required
	to sign code.
	@param code A valid SecStaticCode object reference representing code files
	on disk. This code will be signed, and will ordinarily be modified to contain
	the resulting signature data.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
	@param errors An optional pointer to a CFErrorRef variable. If the call fails
	(and something other than errSecSuccess is returned), and this argument is non-NULL,
	a CFErrorRef is stored there further describing the nature and circumstances
	of the failure. The caller must CFRelease() this error object when done with it.
	@result Upon success, errSecSuccess. Upon error, an OSStatus value documented in
	CSCommon.h or certain other Security framework headers.
*/
OSStatus SecCodeSignerAddSignature(SecCodeSignerRef signer,
	SecStaticCodeRef code, SecCSFlags flags)
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));
	
OSStatus SecCodeSignerAddSignatureWithErrors(SecCodeSignerRef signer,
	SecStaticCodeRef code, SecCSFlags flags, CFErrorRef *errors)
SPI_AVAILABLE(macos(10.5), ios(15.0), macCatalyst(13.0));


#ifdef __cplusplus
}
#endif

#endif //_H_SECCODESIGNER
