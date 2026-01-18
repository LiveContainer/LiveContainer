/*
 * Copyright (c) 2006-2007,2011,2013 Apple Inc. All Rights Reserved.
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
	@header SecCodePriv
	SecCodePriv is the private counter-part to SecCode. Its contents are not
	official API, and are subject to change without notice.
*/
#ifndef _H_SECCODEPRIV
#define _H_SECCODEPRIV

#include "SecCode.h"

#ifdef __cplusplus
extern "C" {
#endif


/*
 *  Private flags for SecCodeCopySigningInformation.
 *  @constant kSecCSSkipCodeDirectoryValidation Force the information creation to skip any
 *      code directory validation (including signature CMS) as part of loading the information.
 *      Generally the copied information is not validated, but some information currently
 *      triggers validation. Since this behavior is relied on by some callers, this flag
 *      opts into new behavior to completely skip the validation.
 */
CF_ENUM(uint32_t) {
    kSecCSSkipCodeDirectoryValidation = 1 << 7,
};
/*
 *	Private constants for SecCodeCopySigningInformation.
 */
extern const CFStringRef kSecCodeInfoCdHashesFull;          /* Internal */
extern const CFStringRef kSecCodeInfoCodeDirectory;         /* Internal */
extern const CFStringRef kSecCodeInfoCodeOffset;            /* Internal */
extern const CFStringRef kSecCodeInfoDiskRepInfo;           /* Internal */
extern const CFStringRef kSecCodeInfoEntitlementsDER;       /* Internal */
extern const CFStringRef kSecCodeInfoResourceDirectory;     /* Internal */
extern const CFStringRef kSecCodeInfoNotarizationDate;      /* Internal */
extern const CFStringRef kSecCodeInfoCMSDigestHashType;     /* Internal */
extern const CFStringRef kSecCodeInfoCMSDigest;             /* Internal */
extern const CFStringRef kSecCodeInfoSignatureVersion;      /* Internal */
extern const CFStringRef kSecCodeInfoLaunchConstraintsSelf;	/* Internal */
extern const CFStringRef kSecCodeInfoLaunchConstraintsParent;/* Internal */
extern const CFStringRef kSecCodeInfoLaunchConstraintsResponsible; /* Internal */
extern const CFStringRef kSecCodeInfoLibraryConstraints;    /* Internal */
extern const CFStringRef kSecCodeInfoValidationCategory; /* Number */

extern const CFStringRef kSecCodeInfoDiskRepVersionPlatform;     /* Number */
extern const CFStringRef kSecCodeInfoDiskRepVersionMin;          /* Number */
extern const CFStringRef kSecCodeInfoDiskRepVersionSDK;          /* Number */
extern const CFStringRef kSecCodeInfoDiskRepNoLibraryValidation; /* String */


/*!
	@function SecCodeGetStatus
	Retrieves the dynamic status for a SecCodeRef.
	
	The dynamic status of a code can change at any time; the value returned is a snapshot
	in time that is inherently stale by the time it is received by the caller. However,
	since the status bits can only change in certain ways, some information is indefinitely
	valid. For example, an indication of invalidity (kSecCodeStatusValid bit off) is permanent
	since the valid bit cannot be set once clear, while an indication of validity (bit set)
	may already be out of date.
	Use this call with caution; it is usually wiser to call the validation API functions
	and let then consider the status as part of their holistic computation. However,
	SecCodeGetStatus is useful at times to capture persistent (sticky) status configurations.

	@param code A valid SecCode object reference representing code running
	on the system.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
	@param status Upon successful return, contains the dynamic status of code as
	determined by its host.
	
	@result Upon success, errSecSuccess. Upon error, an OSStatus value documented in
	CSCommon.h or certain other Security framework headers.
 */
OSStatus SecCodeGetStatus(SecCodeRef code, SecCSFlags flags, SecCodeStatus *status);

typedef uint32_t SecCodeStatusOperation;
enum {
    kSecCodeOperationNull = 0,
    kSecCodeOperationInvalidate = 1,
    kSecCodeOperationSetHard = 2,
    kSecCodeOperationSetKill = 3,
};

/*!
	@function SecCodeSetStatus
	Change the dynamic status of a SecCodeRef.
	
	@param code A valid SecCode object reference representing code running
	on the system.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
	
	@result Upon success, errSecSuccess. Upon error, an OSStatus value documented in
	CSCommon.h or certain other Security framework headers.
 */
OSStatus SecCodeSetStatus(SecCodeRef code, SecCodeStatusOperation operation,
	CFDictionaryRef arguments, SecCSFlags flags);


/*!
	@function SecCodeCopyInternalRequirement
	For a given Code or StaticCode object, retrieves a particular kind of internal
	requirement that was sealed during signing.

	This function will always fail for unsigned code. Requesting a type of internal
	requirement that was not given during signing is not an error.
	
	Specifying a type of kSecDesignatedRequirementType is not the same as calling
	SecCodeCopyDesignatedRequirement. This function will only return an explicit
	Designated Requirement if one was specified during signing. SecCodeCopyDesignatedRequirement
	will synthesize a suitable Designated Requirement if one was not given explicitly.
	
	@param code The Code or StaticCode object to be interrogated. For a Code
		argument, its StaticCode is processed as per SecCodeCopyStaticCode.
	@param type A SecRequirementType specifying which internal requirement is being
		requested.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
	@param requirement On successful return, contains a copy of the internal requirement
		of the given type included in the given code. If the code has no such internal
		requirement, this argument is set to NULL (with no error).
	@result On success, errSecSuccess. On error, an OSStatus value
		documented in CSCommon.h or certain other Security framework headers.
*/
OSStatus SecCodeCopyInternalRequirement(SecStaticCodeRef code, SecRequirementType type,
	SecCSFlags flags, SecRequirementRef *requirement);


#if TARGET_OS_OSX
/*!
	@function SecCodeCreateWithAuditToken
	Asks the kernel to return a SecCode object for a process identified
	by a UNIX audit token. This is a shorthand for asking SecGetRootCode()
	for a guest whose "audit" attribute has the given audit token.
	
	@param audit A process audit token for an existing UNIX process on the system.
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
	@param process On successful return, a SecCode object reference identifying
	the requesteed process.
	@result Upon success, errSecSuccess. Upon error, an OSStatus value documented in
	CSCommon.h or certain other Security framework headers.
*/
OSStatus SecCodeCreateWithAuditToken(const audit_token_t *audit,
                                     SecCSFlags flags, SecCodeRef *process)
    AVAILABLE_MAC_OS_X_VERSION_10_15_AND_LATER;
    
/* Deprecated and unsafe, DO NOT USE. */
OSStatus SecCodeCreateWithPID(pid_t pid, SecCSFlags flags, SecCodeRef *process)
	AVAILABLE_MAC_OS_X_VERSION_10_5_AND_LATER_BUT_DEPRECATED_IN_MAC_OS_X_VERSION_10_6;
#endif


/*
	@function SecCodeSetDetachedSignature
	For a given Code or StaticCode object, explicitly specify the detached signature
	data used to verify it.
	This call unconditionally overrides any signature embedded in the Code and any
	previously specified detached signature; only the signature data specified here
	will be used from now on for this Code object. If NULL data is specified, the
	code object is returned to its natural signing state (before a detached
	signature was first attached to it).
	Any call to this function voids all cached validations for the Code object.
	Validations will be performed again as needed in the future. This call does not,
	by itself, perform or trigger any validations.
	Please note that it is possible to have multiple Code objects for the same static
	or dynamic code entity in the system. This function only attaches signature data
	to the particular SecStaticCodeRef involved. It is your responsibility to understand
	the object graph and pick the right one(s).
	
	@param code A Code or StaticCode object whose signature information is to be changed.
	@param signature A CFDataRef containing the signature data to be used for validating
		the given Code. This must be exactly the data previously generated as a detached
		signature by the SecCodeSignerAddSignature API or the codesign(1) command with
		the -D/--detached option.
		If signature is NULL, discards any previously set signature data and reverts
		to using the embedded signature, if any. If not NULL, the data is retained and used
		for future validation operations.
		The data may be retained or copied. Behavior is undefined if this object
		is modified after this call before it is replaced through another call to this
		function).
	@param flags Optional flags. Pass kSecCSDefaultFlags for standard behavior.
 */
OSStatus SecCodeSetDetachedSignature(SecStaticCodeRef code, CFDataRef signature,
	SecCSFlags flags);


	
/*
	@function SecCodeCopyComponent
 	For a SecStaticCodeRef, directly retrieve the binary blob for a special slot,
 	optionally checking that its native hash is the one given.
 
 	@param code A code or StaticCode object.
 	@param slot The (positive) special slot number requested.
 	@param hash A CFDataRef containing the native slot hash for the slot requested.
 	@result NULL if anything went wrong (including a missing slot), or a CFDataRef
 		containing the slot data.
 */
CFDataRef SecCodeCopyComponent(SecCodeRef code, int slot, CFDataRef hash);

/*
     @function SecCodeSpecialSlotIsPresent
     For a SecStaticCodeRef, checks if the slot is present in the code directory
     
     @param code A StaticCode object.
     @param slot The (positive) special slot number requested.
     @result false if anything went wrong (including a missing slot), true otherwise
 */
CFBooleanRef SecCodeSpecialSlotIsPresent(SecStaticCodeRef code, int slot);
    
/*
 @constant kSecCSStrictValidateStructure
 A subset of the work kSecCSStrictValidate performs, omitting work that
 is unnecessary on some platforms. Since the definition of what can be
 omitted is in flux, and since we would like to remove that notion
 entirely eventually, we makes this a private flag.

 @constant kSecCSSkipRootVolumeExceptions
 Resource validations are skipped for items on the root filesystem and therefore protected
 by the authenticated root volume policy. Passing this flag to a validation causes full resource
 validation even for items on the root volume to enable diagnosting issues with signatures
 on the root volume.

 @constant kSecCSSkipXattrFiles
 NOTE: this flag is no longer used and has become the default behavior.
 Indicates the validation should allow additional files caused on filesystems
 that do not support native xattrs. Only changes validation results if the item lies
 on a filesystem that uses xattr files and the file appears to be an actual xattr.
 */
CF_ENUM(uint32_t) {
	// NOTE: These values needs to align with the public definitions for static code validity too.
	kSecCSStrictValidateStructure = 1 << 13,
	kSecCSSkipRootVolumeExceptions = 1 << 14,
    kSecCSSkipXattrFiles = 1 << 15,
};

#if TARGET_OS_OSX
/* Here just to make TAPI happy. */
extern int GKBIS_DS_Store_Present;
extern int GKBIS_Dot_underbar_Present;
extern int GKBIS_Num_localizations;
extern int GKBIS_Num_files;
extern int GKBIS_Num_dirs;
extern int GKBIS_Num_symlinks;
#endif /* TARGET_OS_OSX */

#ifdef __cplusplus
}
#endif

#endif //_H_SECCODE
