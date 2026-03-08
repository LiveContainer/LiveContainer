#pragma once
#include "json.h"

class ZSignAsset
{
public:
	ZSignAsset();

public:
	bool Init(const string& strCertFile, 
				const string& strPKeyFile,
				const string& strProvFile,
				const string& strEntitleFile,
				const string& strPassword,
				bool bAdhoc,
				bool bSHA256Only,
				bool bSingleBinary);
    bool InitSimple(const void* strSignerPKeyData, int strSignerPKeyDataSize, const void* strProvisionData, int strProvisionDataSize, const string &strPassword);
    bool InitAdhoc(const void* strEntitlementData, int strEntitlementDataSize);
    bool GetCMSContent2(const void* strCMSDataInput, int size, string &strContentOutput);
	bool GenerateCMS(const string& strCDHashData, 
						const string& strCDHashesPlist, 
						const string& strCodeDirectorySlotSHA1, 
						const string& strAltnateCodeDirectorySlot256, 
						string& strCMSOutput);

private:
	bool GenerateCMS(void* pscert, 
						void* pspkey, 
						const string& strCDHashData, 
						const string& strCDHashesPlist, 
						const string& strCodeDirectorySlotSHA1, 
						const string& strAltnateCodeDirectorySlot256, 
						string& strCMSOutput);

	bool GetCertSubjectCN(void* cert, string& strSubjectCN);
	bool GetCertSubjectCN(const string& strCertData, string& strSubjectCN);

public:
	static bool		CMSError();
	static void*	GenerateASN1Type(const string& value);
	static bool		GetCertInfo(void* pcert, jvalue& jvCertInfo);
	static bool		GetCMSInfo(uint8_t* pCMSData, uint32_t uCMSLength, jvalue& jvOutput);
	static bool		GetCMSContent(const string& strCMSDataInput, string& strContentOutput);
	static void		ParseCertSubject(const string& strSubject, jvalue& jvSubject);
	static string	ASN1_TIMEtoString(const void* time);

public:
	bool	m_bAdhoc;
	bool	m_bSHA256Only;
	bool	m_bSingleBinary;
	string	m_strTeamId;
	string	m_strSubjectCN;
	string	m_strProvData;
	string	m_strEntitleData;
    time_t expirationDate;


	void*	m_evpPKey;
	void*	m_x509Cert;


	static const char* s_szAppleDevCACert;
	static const char* s_szAppleRootCACert;
	static const char* s_szAppleDevCACertG3;

public:
	class OpenSSLInit
	{
	public:
		OpenSSLInit();
	};
	static OpenSSLInit s_OpenSSLInit;
};
