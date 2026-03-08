#pragma once
#include "archo.h"

class ZMachO
{
public:
	ZMachO();
	~ZMachO();

public:
	bool Init(const char* szFile);
	bool InitV(const char* szPath, ...);
	bool Free();
	void PrintInfo();
	bool Sign(ZSignAsset* pSignAsset,
				bool bForce, 
				string strBundleId, 
				string strInfoSHA1, 
				string strInfoSHA256, 
				const string& strCodeResourcesData);
	bool InjectDylib(bool bWeakInject, const char* szDylibFile);

private:
	bool OpenFile(const char* szPath);
	bool CloseFile();

	bool NewArchO(uint8_t* pBase, uint32_t uLength);
	void FreeArchOes();
	bool ReallocCodeSignSpace();

private:
	size_t			m_sSize;
	string			m_strFile;
	uint8_t*		m_pBase;
	bool			m_bCSRealloced;
	vector<ZArchO*> m_arrArchOes;
};

bool is_64bit_macho(const char *filepath);
