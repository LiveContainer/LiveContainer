#ifndef BASE64_INCLUDED
#define BASE64_INCLUDED

#include <string>
#include <vector>

using namespace std;

class jbase64
{
public:
	jbase64();
	~jbase64();

public:
	const char* encode(const char* src, int src_len = 0);
	const char* encode(const string& input);
	const char* decode(const char* src, int src_len = 0, int* pdecode_len = NULL);
	const char* decode(const char* src, string& output);

private:
	inline int get_b64_index(char ch);
	inline char get_b64_char(int index);

private:
	vector<char*> m_array_decodes;
	vector<char*> m_array_encodes;
};

#endif // BASE64_INCLUDED