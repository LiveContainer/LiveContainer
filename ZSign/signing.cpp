#include "common.h"
#include "json.h"
#include "mach-o.h"
#include "openssl.h"
#include "signing.h"

void ZSign::_DERLength(string& strBlob, uint64_t uLength)
{
	if (uLength < 128) {
		strBlob.append(1, (char)uLength);
	} else {
		uint32_t sLength = (64 - ZUtil::builtin_clzll(uLength) + 7) / 8;
		strBlob.append(1, (char)(0x80 | sLength));
		sLength *= 8;
		do {
			strBlob.append(1, (char)(uLength >> (sLength -= 8)));
		} while (sLength != 0);
	}
}

string ZSign::_DER(const jvalue& data)
{
	string strOutput;
	if (data.is_bool()) {
		strOutput.append(1, 0x01);
		strOutput.append(1, 1);
		strOutput.append(1, data.as_bool() ? 1 : 0);
	} else if (data.is_int()) {
		uint64_t uVal = data.as_int64();
		strOutput.append(1, 0x02);
		_DERLength(strOutput, uVal);

		uint32_t sLength = (64 - ZUtil::builtin_clzll(uVal) + 7) / 8;
		sLength *= 8;
		do {
			strOutput.append(1, (char)(uVal >> (sLength -= 8)));
		} while (sLength != 0);
	} else if (data.is_string()) {
		string strVal = data.as_cstr();
		strOutput.append(1, 0x0c);
		_DERLength(strOutput, strVal.size());
		strOutput += strVal;
	} else if (data.is_array()) {
		string strArray;
		size_t size = data.size();
		for (size_t i = 0; i < size; i++) {
			strArray += _DER(data[i]);
		}
		strOutput.append(1, 0x30);
		_DERLength(strOutput, strArray.size());
		strOutput += strArray;
	} else if (data.is_object()) {
		string strDict;
		vector<string> arrKeys;
		data.get_keys(arrKeys);
		for (size_t i = 0; i < arrKeys.size(); i++) {
			string& strKey = arrKeys[i];
			string strVal = _DER(data[strKey]);

			strDict.append(1, 0x30);
			_DERLength(strDict, (2 + strKey.size() + strVal.size()));

			strDict.append(1, 0x0c);
			_DERLength(strDict, strKey.size());
			strDict += strKey;

			strDict += strVal;
		}

		strOutput.append(1, 0x31);
		_DERLength(strOutput, strDict.size());
		strOutput += strDict;
	} else if (data.is_double()) {
		assert(false);
	} else if (data.is_date()) {
		assert(false);
	} else if (data.is_data()) {
		assert(false);
	} else {
		assert(false && "Unsupported Entitlements DER Type");
	}

	return strOutput;
}

uint32_t ZSign::SlotParseGeneralHeader(const char* szSlotName, uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = LE(*(((uint32_t*)pSlotBase) + 1));
	ZLog::PrintV("\n  > %s: \n", szSlotName);
	ZLog::PrintV("\ttype: \t\t0x%x\n", LE(pbi->type));
	ZLog::PrintV("\toffset: \t%u\n", LE(pbi->offset));
	ZLog::PrintV("\tmagic: \t\t0x%x\n", LE(*((uint32_t*)pSlotBase)));
	ZLog::PrintV("\tlength: \t%u\n", uSlotLength);
	return uSlotLength;
}

void ZSign::SlotParseGeneralTailer(uint8_t* pSlotBase, uint32_t uSlotLength)
{
	ZSHA::PrintData1("\tSHA-1:  \t", pSlotBase, uSlotLength);
	ZSHA::PrintData256("\tSHA-256:\t", pSlotBase, uSlotLength);
}

bool ZSign::SlotParseRequirements(uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = SlotParseGeneralHeader("CSSLOT_REQUIREMENTS", pSlotBase, pbi);
	if (uSlotLength < 8) {
		return false;
	}

#ifndef _WIN32
	if (ZFile::IsFileExists("/usr/bin/csreq")) {
		string strTempFile;
		ZUtil::StringFormatV(strTempFile, "/tmp/Requirements_%llu.blob", ZUtil::GetMicroSecond());
		ZFile::WriteFile(strTempFile.c_str(), (const char*)pSlotBase, uSlotLength);

		string strCommand;
		ZUtil::StringFormatV(strCommand, "/usr/bin/csreq -r '%s' -t ", strTempFile.c_str());
		char result[1024] = { 0 };
		FILE* cmd = popen(strCommand.c_str(), "r");
		while (NULL != fgets(result, sizeof(result), cmd)) {
			printf("\treqtext: \t%s", result);
		}
		pclose(cmd);
		ZFile::RemoveFile(strTempFile.c_str());
	}
#endif

	SlotParseGeneralTailer(pSlotBase, uSlotLength);

	if (ZLog::IsDebug()) {
		ZFile::WriteFile("./.zsign_debug/Requirements.slot", (const char*)pSlotBase, uSlotLength);
	}
	return true;
}

bool ZSign::SlotBuildRequirements(const string& strBundleID, const string& strSubjectCN, string& strOutput)
{
	strOutput.clear();
	if (strBundleID.empty() || strSubjectCN.empty()) { //ldid
		uint8_t ldid[] = { 0xfa, 0xde, 0x0c, 0x01, 0x00, 0x00, 0x00, 0x0c, 0x00, 0x00, 0x00, 0x00 };
		strOutput.append((const char*)ldid, sizeof(ldid));
		return true;
	}

	string strPaddedBundleID = strBundleID;
	strPaddedBundleID.append(((strBundleID.size() % 4) ? (4 - (strBundleID.size() % 4)) : 0), 0);

	string strPaddedSubjectID = strSubjectCN;
	strPaddedSubjectID.append(((strSubjectCN.size() % 4) ? (4 - (strSubjectCN.size() % 4)) : 0), 0);

	uint8_t magic1[] = { 0xfa, 0xde, 0x0c, 0x01 };
	uint32_t uLength1 = 0;
	uint8_t pack1[] = { 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x14 };
	uint8_t magic2[] = { 0xfa, 0xde, 0x0c, 0x00 };
	uint32_t uLength2 = 0;
	uint8_t pack2[] = { 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x02 };
	uint32_t uBundldIDLength = (uint32_t)strBundleID.size();
	//string strPaddedBundleID
	uint8_t pack3[] = { 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x00, 0x06, 0x00, 0x00, 0x00, 0x0b,
						0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0a, 0x73, 0x75, 0x62, 0x6a, 0x65, 0x63, 0x74, 0x2e,
						0x43, 0x4e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01 };
	uint32_t uSubjectCNLength = (uint32_t)strSubjectCN.size();
	//string strPaddedSubjectID
	uint8_t pack4[] = { 0x00, 0x00, 0x00, 0x0e, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x0a, 0x2a, 0x86, 0x48, 0x86,
						0xf7, 0x63, 0x64, 0x06, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };

	uLength2 += sizeof(magic2) + sizeof(uLength2) + sizeof(pack2);
	uLength2 += sizeof(uBundldIDLength) + (uint32_t)strPaddedBundleID.size();
	uLength2 += sizeof(pack3);
	uLength2 += sizeof(uSubjectCNLength) + (uint32_t)strPaddedSubjectID.size();
	uLength2 += sizeof(pack4);

	uLength1 += sizeof(magic1) + sizeof(uLength1) + sizeof(pack1);
	uLength1 += uLength2;

	uLength1 = BE(uLength1);
	uLength2 = BE(uLength2);
	uBundldIDLength = BE(uBundldIDLength);
	uSubjectCNLength = BE(uSubjectCNLength);

	strOutput.append((const char*)magic1, sizeof(magic1));
	strOutput.append((const char*)&uLength1, sizeof(uLength1));
	strOutput.append((const char*)pack1, sizeof(pack1));
	strOutput.append((const char*)magic2, sizeof(magic2));
	strOutput.append((const char*)&uLength2, sizeof(uLength2));
	strOutput.append((const char*)pack2, sizeof(pack2));
	strOutput.append((const char*)&uBundldIDLength, sizeof(uBundldIDLength));
	strOutput.append(strPaddedBundleID.data(), strPaddedBundleID.size());
	strOutput.append((const char*)pack3, sizeof(pack3));
	strOutput.append((const char*)&uSubjectCNLength, sizeof(uSubjectCNLength));
	strOutput.append(strPaddedSubjectID.data(), strPaddedSubjectID.size());
	strOutput.append((const char*)pack4, sizeof(pack4));

	return true;
}

bool ZSign::SlotParseEntitlements(uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = SlotParseGeneralHeader("CSSLOT_ENTITLEMENTS", pSlotBase, pbi);
	if (uSlotLength < 8) {
		return false;
	}

	string strEntitlements = "\t\t\t";
	strEntitlements.append((const char*)pSlotBase + 8, uSlotLength - 8);
	ZUtil::StringReplace(strEntitlements, "\n", "\n\t\t\t");
	ZLog::PrintV("\tentitlements: \n%s\n", strEntitlements.c_str());

	SlotParseGeneralTailer(pSlotBase, uSlotLength);

	if (ZLog::IsDebug()) {
		ZFile::WriteFile("./.zsign_debug/Entitlements.slot", (const char*)pSlotBase, uSlotLength);
		ZFile::WriteFile("./.zsign_debug/Entitlements.plist", (const char*)pSlotBase + 8, uSlotLength - 8);
	}
	return true;
}

bool ZSign::SlotParseDerEntitlements(uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = SlotParseGeneralHeader("CSSLOT_DER_ENTITLEMENTS", pSlotBase, pbi);
	if (uSlotLength < 8) {
		return false;
	}

	SlotParseGeneralTailer(pSlotBase, uSlotLength);

	if (ZLog::IsDebug()) {
		ZFile::WriteFile("./.zsign_debug/Entitlements.der.slot", (const char*)pSlotBase, uSlotLength);
	}
	return true;
}

bool ZSign::SlotBuildEntitlements(const string& strEntitlements, string& strOutput)
{
	strOutput.clear();
	if (strEntitlements.empty()) {
		return false;
	}

	uint32_t uMagic = BE((uint32_t)CSMAGIC_EMBEDDED_ENTITLEMENTS);
	uint32_t uLength = BE((uint32_t)strEntitlements.size() + 8);

	strOutput.append((const char*)&uMagic, sizeof(uMagic));
	strOutput.append((const char*)&uLength, sizeof(uLength));
	strOutput.append(strEntitlements.data(), strEntitlements.size());

	return true;
}

bool ZSign::SlotBuildDerEntitlements(const string& strEntitlements, string& strOutput)
{
	strOutput.clear();
	if (strEntitlements.empty()) {
		return false;
	}

	jvalue jvInfo;
	jvInfo.read_plist(strEntitlements);

	string strRawEntitlementsData = _DER(jvInfo);
	uint32_t uMagic = BE((uint32_t)CSMAGIC_EMBEDDED_DER_ENTITLEMENTS);
	uint32_t uLength = BE((uint32_t)strRawEntitlementsData.size() + 8);

	strOutput.append((const char*)&uMagic, sizeof(uMagic));
	strOutput.append((const char*)&uLength, sizeof(uLength));
	strOutput.append(strRawEntitlementsData.data(), strRawEntitlementsData.size());

	return true;
}

bool ZSign::SlotParseCodeDirectory(uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = SlotParseGeneralHeader("CSSLOT_CODEDIRECTORY", pSlotBase, pbi);
	if (uSlotLength < 8) {
		return false;
	}

	vector<uint8_t*> arrCodeSlots;
	vector<uint8_t*> arrSpecialSlots;
	CS_CodeDirectory cdHeader = *((CS_CodeDirectory*)pSlotBase);
	uint8_t* pHashes = pSlotBase + LE(cdHeader.hashOffset);
	for (uint32_t i = 0; i < LE(cdHeader.nCodeSlots); i++) {
		arrCodeSlots.push_back(pHashes + cdHeader.hashSize * i);
	}
	for (uint32_t i = 0; i < LE(cdHeader.nSpecialSlots); i++) {
		arrSpecialSlots.push_back(pHashes - cdHeader.hashSize * (i + 1));
	}

	ZLog::PrintV("\tversion: \t0x%x\n", LE(cdHeader.version));
	ZLog::PrintV("\tflags: \t\t%u\n", LE(cdHeader.flags));
	ZLog::PrintV("\thashOffset: \t%u\n", LE(cdHeader.hashOffset));
	ZLog::PrintV("\tidentOffset: \t%u\n", LE(cdHeader.identOffset));
	ZLog::PrintV("\tnSpecialSlots: \t%u\n", LE(cdHeader.nSpecialSlots));
	ZLog::PrintV("\tnCodeSlots: \t%u\n", LE(cdHeader.nCodeSlots));
	ZLog::PrintV("\tcodeLimit: \t%u\n", LE(cdHeader.codeLimit));
	ZLog::PrintV("\thashSize: \t%u\n", cdHeader.hashSize);
	ZLog::PrintV("\thashType: \t%u\n", cdHeader.hashType);
	ZLog::PrintV("\tspare1: \t%u\n", cdHeader.spare1);
	ZLog::PrintV("\tpageSize: \t%u\n", cdHeader.pageSize);
	ZLog::PrintV("\tspare2: \t%u\n", LE(cdHeader.spare2));

	uint32_t uVersion = LE(cdHeader.version);
	if (uVersion >= 0x20100) {
		ZLog::PrintV("\tscatterOffset: \t%u\n", LE(cdHeader.scatterOffset));
	}
	if (uVersion >= 0x20200) {
		ZLog::PrintV("\tteamOffset: \t%u\n", LE(cdHeader.teamOffset));
	}
	if (uVersion >= 0x20300) {
		ZLog::PrintV("\tspare3: \t%u\n", LE(cdHeader.spare3));
		ZLog::PrintV("\tcodeLimit64: \t%llu\n", LE(cdHeader.codeLimit64));
	}
	if (uVersion >= 0x20400) {
		ZLog::PrintV("\texecSegBase: \t%llu\n", LE(cdHeader.execSegBase));
		ZLog::PrintV("\texecSegLimit: \t%llu\n", LE(cdHeader.execSegLimit));
		ZLog::PrintV("\texecSegFlags: \t%llu\n", LE(cdHeader.execSegFlags));
	}

	ZLog::PrintV("\tidentifier: \t%s\n", pSlotBase + LE(cdHeader.identOffset));
	if (uVersion >= 0x20200) {
		ZLog::PrintV("\tteamid: \t%s\n", pSlotBase + LE(cdHeader.teamOffset));
	}

	ZLog::PrintV("\tSpecialSlots:\n");
	for (int i = LE(cdHeader.nSpecialSlots) - 1; i >= 0; i--) {
		const char* suffix = "\t\n";
		switch (i) {
		case 0:
			suffix = "\tInfo.plist\n";
			break;
		case 1:
			suffix = "\tRequirements Slot\n";
			break;
		case 2:
			suffix = "\tCodeResources\n";
			break;
		case 3:
			suffix = "\tApplication Specific\n";
			break;
		case 4:
			suffix = "\tEntitlements Slot\n";
			break;
		case 6:
			suffix = "\tEntitlements(DER) Slot\n";
			break;
		}
		ZSHA::Print("\t\t\t", arrSpecialSlots[i], cdHeader.hashSize, suffix);
	}

	if (ZLog::IsDebug()) {
		ZLog::Print("\tCodeSlots:\n");
		for (uint32_t i = 0; i < LE(cdHeader.nCodeSlots); i++) {
			ZSHA::Print("\t\t\t", arrCodeSlots[i], cdHeader.hashSize);
		}
	} else {
		ZLog::Print("\tCodeSlots: \tomitted. (use -d option for details)\n");
	}

	SlotParseGeneralTailer(pSlotBase, uSlotLength);

	if (ZLog::IsDebug()) {
		if (1 == cdHeader.hashType) {
			ZFile::WriteFile("./.zsign_debug/CodeDirectory_SHA1.slot", (const char*)pSlotBase, uSlotLength);
		} else if (2 == cdHeader.hashType) {
			ZFile::WriteFile("./.zsign_debug/CodeDirectory_SHA256.slot", (const char*)pSlotBase, uSlotLength);
		}
	}

	return true;
}

bool ZSign::SlotBuildCodeDirectory(bool bAlternate,
	uint8_t* pCodeBase,
	uint32_t uCodeLength,
	uint8_t* pCodeSlotsData,
	uint32_t uCodeSlotsDataLength,
	uint64_t execSegLimit,
	uint64_t execSegFlags,
	const string& strBundleId,
	const string& strTeamId,
	const string& strInfoPlistSHA,
	const string& strRequirementsSlotSHA,
	const string& strCodeResourcesSHA,
	const string& strEntitlementsSlotSHA,
	const string& strDerEntitlementsSlotSHA,
	bool isExecuteArch,
	bool isAdhoc,
	string& strOutput)
{
	strOutput.clear();
	if (NULL == pCodeBase || uCodeLength <= 0 || strBundleId.empty() || (strTeamId.empty() && !isAdhoc)) {
		return false;
	}

	uint32_t uVersion = 0x20400;

	CS_CodeDirectory cdHeader;
	memset(&cdHeader, 0, sizeof(cdHeader));
	cdHeader.magic = BE((uint32_t)CSMAGIC_CODEDIRECTORY);
	cdHeader.length = 0;
	cdHeader.version = BE(uVersion);
	cdHeader.flags = isAdhoc ? BE(static_cast<uint32_t>(CS_SEC_CODESIGNATURE_ADHOC)) : 0U;
	cdHeader.hashOffset = 0;
	cdHeader.identOffset = 0;
	cdHeader.nSpecialSlots = 0;
	cdHeader.nCodeSlots = 0;
	cdHeader.codeLimit = BE(uCodeLength);
	cdHeader.hashSize = bAlternate ? 32 : 20;
	cdHeader.hashType = bAlternate ? 2 : 1;
	cdHeader.spare1 = 0;
	cdHeader.pageSize = 12;
	cdHeader.spare2 = 0;
	cdHeader.scatterOffset = 0;
	cdHeader.teamOffset = 0;
	cdHeader.execSegBase = 0;
	cdHeader.execSegLimit = BE(execSegLimit);
	cdHeader.execSegFlags = BE(execSegFlags);

	string strEmptySHA;
	strEmptySHA.append(cdHeader.hashSize, 0);
	vector<string> arrSpecialSlots;

	if (isExecuteArch) {
		arrSpecialSlots.push_back(strDerEntitlementsSlotSHA.empty() ? strEmptySHA : strDerEntitlementsSlotSHA);
		arrSpecialSlots.push_back(strEmptySHA);
	}
	arrSpecialSlots.push_back(strEntitlementsSlotSHA.empty() ? strEmptySHA : strEntitlementsSlotSHA);
	arrSpecialSlots.push_back(strEmptySHA);
	arrSpecialSlots.push_back(strCodeResourcesSHA.empty() ? strEmptySHA : strCodeResourcesSHA);
	arrSpecialSlots.push_back(strRequirementsSlotSHA.empty() ? strEmptySHA : strRequirementsSlotSHA);
	arrSpecialSlots.push_back(strInfoPlistSHA.empty() ? strEmptySHA : strInfoPlistSHA);

	// Trailing entries whose hash == strEmptySHA in `arrSpecialSlots` can be omitted; erase them.
	// Special slots have negative indexes and come before code slots, i.e. index -1 is the 'Info.plist'
	// slot, and -2 is 'Requirements slot'.
	// Note that in `arrSpecialSlots` is reversed and trailing elements appear at front.
	auto itLastUsedSpecialSlot = std::find_if(arrSpecialSlots.begin(), arrSpecialSlots.end(),
		[&](const string& strSHA) { return strSHA != strEmptySHA; });
	if (itLastUsedSpecialSlot != arrSpecialSlots.begin()) {
		arrSpecialSlots.erase(arrSpecialSlots.begin(), itLastUsedSpecialSlot);
	}

	uint32_t uPageSize = (uint32_t)pow(2, cdHeader.pageSize);
	uint32_t uPages = uCodeLength / uPageSize;
	uint32_t uRemain = uCodeLength % uPageSize;
	uint32_t uCodeSlots = uPages + (uRemain > 0 ? 1 : 0);

	uint32_t uHeaderLength = 44;
	if (uVersion >= 0x20100) {
		uHeaderLength += sizeof(cdHeader.scatterOffset);
	}
	if (uVersion >= 0x20200) {
		uHeaderLength += sizeof(cdHeader.teamOffset);
	}
	if (uVersion >= 0x20300) {
		uHeaderLength += sizeof(cdHeader.spare3);
		uHeaderLength += sizeof(cdHeader.codeLimit64);
	}
	if (uVersion >= 0x20400) {
		uHeaderLength += sizeof(cdHeader.execSegBase);
		uHeaderLength += sizeof(cdHeader.execSegLimit);
		uHeaderLength += sizeof(cdHeader.execSegFlags);
	}

	uint32_t uBundleIDLength = (uint32_t)strBundleId.size() + 1;
	uint32_t uTeamIDLength = (uint32_t)strTeamId.size() + 1;
	uint32_t uSpecialSlotsLength = (uint32_t)arrSpecialSlots.size() * cdHeader.hashSize;
	uint32_t uCodeSlotsLength = uCodeSlots * cdHeader.hashSize;

	uint32_t uSlotLength = uHeaderLength + uBundleIDLength + uSpecialSlotsLength + uCodeSlotsLength;
	if (uVersion >= 0x20100) {
		//todo
	}
	if (uVersion >= 0x20200 && !strTeamId.empty()) {
		uSlotLength += uTeamIDLength;
	}

	cdHeader.length = BE(uSlotLength);
	cdHeader.identOffset = BE(uHeaderLength);
	cdHeader.nSpecialSlots = BE((uint32_t)arrSpecialSlots.size());
	cdHeader.nCodeSlots = BE(uCodeSlots);

	uint32_t uHashOffset = uHeaderLength + uBundleIDLength + uSpecialSlotsLength;
	if (uVersion >= 0x20100) {
		//todo
	}
	// `strTeamId` may be empty for ad-hoc signature; in that case, `cdHeader.teamOffset == 0` and string
	// data is not serialized below.
	if (uVersion >= 0x20200 && !strTeamId.empty()) {
		uHashOffset += uTeamIDLength;
		cdHeader.teamOffset = BE(uHeaderLength + uBundleIDLength);
	}
	cdHeader.hashOffset = BE(uHashOffset);

	strOutput.append((const char*)&cdHeader, uHeaderLength);
	strOutput.append(strBundleId.data(), strBundleId.size() + 1);
	if (uVersion >= 0x20100) {
		//todo
	}
	if (uVersion >= 0x20200 && !strTeamId.empty()) {
		strOutput.append(strTeamId.data(), strTeamId.size() + 1);
	}

	for (uint32_t i = 0; i < LE(cdHeader.nSpecialSlots); i++) {
		strOutput.append(arrSpecialSlots[i].data(), arrSpecialSlots[i].size());
	}

	if (NULL != pCodeSlotsData && (uCodeSlotsDataLength == uCodeSlots * cdHeader.hashSize)) { //use exists
		strOutput.append((const char*)pCodeSlotsData, uCodeSlotsDataLength);
	} else {
		for (uint32_t i = 0; i < uPages; i++) {
			string strSHASum;
			if (1 == cdHeader.hashType) {
				ZSHA::SHA1(pCodeBase + uPageSize * i, uPageSize, strSHASum);
			} else  {
				ZSHA::SHA256(pCodeBase + uPageSize * i, uPageSize, strSHASum);
			} 
			strOutput.append(strSHASum.data(), strSHASum.size());
		}
		if (uRemain > 0) {
			string strSHASum;
			if (1 == cdHeader.hashType) {
				ZSHA::SHA1(pCodeBase + uPageSize * uPages, uRemain, strSHASum);
			} else {
				ZSHA::SHA256(pCodeBase + uPageSize * uPages, uRemain, strSHASum);
			}
			strOutput.append(strSHASum.data(), strSHASum.size());
		}
	}

	return true;
}

bool ZSign::SlotParseCMSSignature(uint8_t* pSlotBase, CS_BlobIndex* pbi)
{
	uint32_t uSlotLength = SlotParseGeneralHeader("CSSLOT_SIGNATURESLOT", pSlotBase, pbi);
	if (uSlotLength < 8) {
		return false;
	}

	jvalue jvInfo;
	ZSignAsset::GetCMSInfo(pSlotBase + 8, uSlotLength - 8, jvInfo);
	//ZLog::PrintV("%s\n", jvInfo.styleWrite().c_str());

	ZLog::Print("\tCertificates: \n");
	for (size_t i = 0; i < jvInfo["certs"].size(); i++) {
		ZLog::PrintV("\t\t\t%s\t<=\t%s\n", jvInfo["certs"][i]["Subject"]["CN"].as_cstr(), jvInfo["certs"][i]["Issuer"]["CN"].as_cstr());
	}

	ZLog::Print("\tSignedAttrs: \n");
	if (jvInfo["attrs"].has("ContentType")) {
		ZLog::PrintV("\t  ContentType: \t%s => %s\n", jvInfo["attrs"]["ContentType"]["obj"].as_cstr(), jvInfo["attrs"]["ContentType"]["data"].as_cstr());
	}

	if (jvInfo["attrs"].has("SigningTime")) {
		ZLog::PrintV("\t  SigningTime: \t%s => %s\n", jvInfo["attrs"]["SigningTime"]["obj"].as_cstr(), jvInfo["attrs"]["SigningTime"]["data"].as_cstr());
	}

	if (jvInfo["attrs"].has("MessageDigest")) {
		ZLog::PrintV("\t  MsgDigest: \t%s => %s\n", jvInfo["attrs"]["MessageDigest"]["obj"].as_cstr(), jvInfo["attrs"]["MessageDigest"]["data"].as_cstr());
	}

	if (jvInfo["attrs"].has("CDHashes")) {
		string strData = jvInfo["attrs"]["CDHashes"]["data"].as_cstr();
		ZUtil::StringReplace(strData, "\n", "\n\t\t\t\t");
		ZLog::PrintV("\t  CDHashes: \t%s => \n\t\t\t\t%s\n", jvInfo["attrs"]["CDHashes"]["obj"].as_cstr(), strData.c_str());
	}

	if (jvInfo["attrs"].has("CDHashes2")) {
		ZLog::PrintV("\t  CDHashes2: \t%s => \n", jvInfo["attrs"]["CDHashes2"]["obj"].as_cstr());
		for (size_t i = 0; i < jvInfo["attrs"]["CDHashes2"]["data"].size(); i++) {
			ZLog::PrintV("\t\t\t\t%s\n", jvInfo["attrs"]["CDHashes2"]["data"][i].as_cstr());
		}
	}

	for (size_t i = 0; i < jvInfo["attrs"]["unknown"].size(); i++) {
		jvalue& jvAttr = jvInfo["attrs"]["unknown"][i];
		ZLog::PrintV("\t  UnknownAttr: \t%s => %s, type: %d, count: %d\n", jvAttr["obj"].as_cstr(), jvAttr["name"].as_cstr(), jvAttr["type"].as_int(), jvAttr["count"].as_int());
	}
	ZLog::Print("\n");

	SlotParseGeneralTailer(pSlotBase, uSlotLength);

	if (ZLog::IsDebug()) {
		ZFile::WriteFile("./.zsign_debug/CMSSignature.slot", (const char*)pSlotBase, uSlotLength);
		ZFile::WriteFile("./.zsign_debug/CMSSignature.der", (const char*)pSlotBase + 8, uSlotLength - 8);
	}
	return true;
}

bool ZSign::SlotBuildCMSSignature(ZSignAsset* pSignAsset,
	const string& strCodeDirectorySlot,
	const string& strAltnateCodeDirectorySlot,
	string& strOutput)
{
	strOutput.clear();
	if (pSignAsset->m_bAdhoc) { // The empty CSSLOT_SIGNATURESLOT
		uint8_t ldid[] = { 0xfa, 0xde, 0x0b, 0x01, 0x00, 0x00, 0x00, 0x08 };
		strOutput.append((const char*)ldid, sizeof(ldid));
		return true;
	}

	jvalue jvHashes;
	string strCDHashesPlist;
	string strCodeDirectorySlotSHA1;
	string strAltnateCodeDirectorySlot256;
	ZSHA::SHA1(strCodeDirectorySlot, strCodeDirectorySlotSHA1);
	ZSHA::SHA256(strAltnateCodeDirectorySlot, strAltnateCodeDirectorySlot256);

	size_t cdHashSize = strCodeDirectorySlotSHA1.size();
	jvHashes["cdhashes"][0].assign_data(strCodeDirectorySlotSHA1.data(), cdHashSize);
	jvHashes["cdhashes"][1].assign_data(strAltnateCodeDirectorySlot256.data(), cdHashSize);
	jvHashes.style_write_plist(strCDHashesPlist);

	string strCMSData;
	if (!pSignAsset->GenerateCMS(strCodeDirectorySlot, strCDHashesPlist, strCodeDirectorySlotSHA1, strAltnateCodeDirectorySlot256, strCMSData)) {
		return false;
	}

	uint32_t uMagic = BE((uint32_t)CSMAGIC_BLOBWRAPPER);
	uint32_t uLength = BE((uint32_t)strCMSData.size() + 8);

	strOutput.append((const char*)&uMagic, sizeof(uMagic));
	strOutput.append((const char*)&uLength, sizeof(uLength));
	strOutput.append(strCMSData.data(), strCMSData.size());
	return true;
}

uint32_t ZSign::GetCodeSignatureLength(uint8_t* pCSBase)
{
	CS_SuperBlob* psb = (CS_SuperBlob*)pCSBase;
	if (NULL != psb && CSMAGIC_EMBEDDED_SIGNATURE == LE(psb->magic)) {
		return LE(psb->length);
	}
	return 0;
}

bool ZSign::ParseCodeSignature(uint8_t* pCSBase)
{
	CS_SuperBlob* psb = (CS_SuperBlob*)pCSBase;
	if (NULL == psb || CSMAGIC_EMBEDDED_SIGNATURE != LE(psb->magic)) {
		return false;
	}

	ZLog::PrintV("\n>>> CodeSignature Segment: \n");
	ZLog::PrintV("\tmagic: \t\t0x%x\n", LE(psb->magic));
	ZLog::PrintV("\tlength: \t%d\n", LE(psb->length));
	ZLog::PrintV("\tslots: \t\t%d\n", LE(psb->count));

	CS_BlobIndex* pbi = (CS_BlobIndex*)(pCSBase + sizeof(CS_SuperBlob));
	for (uint32_t i = 0; i < LE(psb->count); i++, pbi++) {
		uint8_t* pSlotBase = pCSBase + LE(pbi->offset);
		switch (LE(pbi->type)) {
		case CSSLOT_CODEDIRECTORY:
			SlotParseCodeDirectory(pSlotBase, pbi);
			break;
		case CSSLOT_REQUIREMENTS:
			SlotParseRequirements(pSlotBase, pbi);
			break;
		case CSSLOT_ENTITLEMENTS:
			SlotParseEntitlements(pSlotBase, pbi);
			break;
		case CSSLOT_DER_ENTITLEMENTS:
			SlotParseDerEntitlements(pSlotBase, pbi);
			break;
		case CSSLOT_ALTERNATE_CODEDIRECTORIES:
			SlotParseCodeDirectory(pSlotBase, pbi);
			break;
		case CSSLOT_SIGNATURESLOT:
			SlotParseCMSSignature(pSlotBase, pbi);
			break;
		case CSSLOT_IDENTIFICATIONSLOT:
			SlotParseGeneralHeader("CSSLOT_IDENTIFICATIONSLOT", pSlotBase, pbi);
			break;
		case CSSLOT_TICKETSLOT:
			SlotParseGeneralHeader("CSSLOT_TICKETSLOT", pSlotBase, pbi);
			break;
		default:
			SlotParseGeneralTailer(pSlotBase, SlotParseGeneralHeader("CSSLOT_UNKNOWN", pSlotBase, pbi));
			break;
		}
	}

	if (ZLog::IsDebug()) {
		ZFile::WriteFile("./.zsign_debug/CodeSignature.blob", (const char*)pCSBase, LE(psb->length));
	}
	return true;
}

bool ZSign::SlotGetCodeSlotsData(uint8_t* pSlotBase, uint8_t*& pCodeSlots, uint32_t& uCodeSlotsLength)
{
	uint32_t uSlotLength = LE(*(((uint32_t*)pSlotBase) + 1));
	if (uSlotLength < 8) {
		return false;
	}
	CS_CodeDirectory cdHeader = *((CS_CodeDirectory*)pSlotBase);
	pCodeSlots = pSlotBase + LE(cdHeader.hashOffset);
	uCodeSlotsLength = LE(cdHeader.nCodeSlots) * cdHeader.hashSize;
	return true;
}

bool ZSign::GetCodeSignatureExistsCodeSlotsData(uint8_t* pCSBase,
	uint8_t*& pCodeSlots1Data,
	uint32_t& uCodeSlots1DataLength,
	uint8_t*& pCodeSlots256Data,
	uint32_t& uCodeSlots256DataLength)
{
	pCodeSlots1Data = NULL;
	pCodeSlots256Data = NULL;
	uCodeSlots1DataLength = 0;
	uCodeSlots256DataLength = 0;
	CS_SuperBlob* psb = (CS_SuperBlob*)pCSBase;
	if (NULL == psb || CSMAGIC_EMBEDDED_SIGNATURE != LE(psb->magic)) {
		return false;
	}

	CS_BlobIndex* pbi = (CS_BlobIndex*)(pCSBase + sizeof(CS_SuperBlob));
	for (uint32_t i = 0; i < LE(psb->count); i++, pbi++) {
		uint8_t* pSlotBase = pCSBase + LE(pbi->offset);
		switch (LE(pbi->type)) {
		case CSSLOT_CODEDIRECTORY:
		{
			CS_CodeDirectory cdHeader = *((CS_CodeDirectory*)pSlotBase);
			if (LE(cdHeader.length) > 8) {
				pCodeSlots1Data = pSlotBase + LE(cdHeader.hashOffset);
				uCodeSlots1DataLength = LE(cdHeader.nCodeSlots) * cdHeader.hashSize;
			}
		}
		break;
		case CSSLOT_ALTERNATE_CODEDIRECTORIES:
		{
			CS_CodeDirectory cdHeader = *((CS_CodeDirectory*)pSlotBase);
			if (LE(cdHeader.length) > 8) {
				pCodeSlots256Data = pSlotBase + LE(cdHeader.hashOffset);
				uCodeSlots256DataLength = LE(cdHeader.nCodeSlots) * cdHeader.hashSize;
			}
		}
		break;
		default:
			break;
		}
	}

	return ((NULL != pCodeSlots1Data) && (NULL != pCodeSlots256Data) && uCodeSlots1DataLength > 0 && uCodeSlots256DataLength > 0);
}
