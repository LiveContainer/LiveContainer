#include "json.h"
#include "base64.h"
#include <time.h>
#include <math.h>
#include <assert.h>
#include <stdarg.h>
#include <limits>
using namespace std;

#ifdef _WIN32

#define _fopen64(fp, path, mode)	{ fopen_s(&fp, path, mode); }
#define PRId64						"lld"

#else

#ifdef __APPLE__
#define PRId64						"lld"
#else
#define PRId64						"ld"
#endif

#define _fseeki64					fseeko
#define _ftelli64					ftello
#define _atoi64(val)				strtoll(val, NULL, 10)
#define sscanf_s 					sscanf
#define _fopen64(fp, path, mode)	{fp = fopen(path, mode); }

#endif


const jvalue jvalue::null;
const string jvalue::null_data;

jvalue::jvalue(jtype type)
{
	m_type = type;
	m_value.v_double = 0;
}

jvalue::jvalue(int val)
{
	m_type = E_INT;
	m_value.v_int64 = val;
}

jvalue::jvalue(int64_t val)
{
	m_type = E_INT;
	m_value.v_int64 = val;
}

jvalue::jvalue(bool val)
{
	m_type = E_BOOL;
	m_value.v_bool = val;
}

jvalue::jvalue(double val)
{
	m_type = E_FLOAT;
	m_value.v_double = val;
}

jvalue::jvalue(const char* val)
{
	m_type = E_STRING;
	m_value.p_string = _new_string(val);
}

jvalue::jvalue(const string& val)
{
	m_type = E_STRING;
	m_value.p_string = _new_string(val.c_str());
}

jvalue::jvalue(const jvalue& other)
{
	_copy_value(other);
}

jvalue::jvalue(const char* val, size_t len)
{
	m_type = E_DATA;
	m_value.p_data = new string();
	m_value.p_data->append(val, len);
}

jvalue::~jvalue()
{
	_free();
}

void jvalue::clear()
{
	_free();
}

bool jvalue::is_int() const
{
	return (E_INT == m_type);
}

bool jvalue::is_null() const
{
	return (E_NULL == m_type);
}

bool jvalue::is_bool() const
{
	return (E_BOOL == m_type);
}

bool jvalue::is_double() const
{
	return (E_FLOAT == m_type);
}

bool jvalue::is_string() const
{
	return (E_STRING == m_type);
}

bool jvalue::is_array() const
{
	return (E_ARRAY == m_type);
}

bool jvalue::is_object() const
{
	return (E_OBJECT == m_type);
}

bool jvalue::is_empty() const
{
	switch (m_type) {
	case E_NULL:
		return true;
		break;
	case E_INT:
		return (0 == m_value.v_int64);
		break;
	case E_BOOL:
		return (false == m_value.v_bool);
		break;
	case E_FLOAT:
		return (0 == m_value.v_double);
		break;
	case E_ARRAY:
	case E_OBJECT:
		return (0 == size());
		break;
	case E_STRING:
		return (0 == strlen(as_cstr()));
	case E_DATE:
		return (0 == m_value.v_date);
		break;
	case E_DATA:
		return (NULL == m_value.p_data) ? true : m_value.p_data->empty();
		break;
	}
	return true;
}

jvalue::operator const char* () const
{
	return as_cstr();
}

jvalue::operator int() const
{
	return as_int();
}

jvalue::operator int64_t() const
{
	return as_int64();
}

jvalue::operator double() const
{
	return as_double();
}

jvalue::operator string() const
{
	return as_cstr();
}

jvalue::operator bool() const
{
	return as_bool();
}

char* jvalue::_new_string(const char* cstr)
{
	char* str = NULL;
	if (NULL != cstr) {
		size_t len = (strlen(cstr) + 1) * sizeof(char);
		str = (char*)::malloc(len);
		if (NULL != str) {
			::memcpy(str, cstr, len);
		}
	}
	return str;
}

void jvalue::_copy_value(const jvalue& src)
{
	m_type = src.m_type;
	switch (m_type) {
	case E_ARRAY:
		m_value.p_array = (NULL == src.m_value.p_array) ? NULL : new array(*(src.m_value.p_array));
		break;
	case E_OBJECT:
	{
		m_value.p_object = (NULL == src.m_value.p_object) ? NULL : new object();
		if (NULL != m_value.p_object) {
			*m_value.p_object = *src.m_value.p_object;
		}
	}
	break;
	case E_STRING:
		m_value.p_string = (NULL == src.m_value.p_string) ? NULL : _new_string(src.m_value.p_string);
		break;
	case E_DATA:
	{
		if (NULL != src.m_value.p_data) {
			m_value.p_data = new string();
			*m_value.p_data = *src.m_value.p_data;
		} else {
			m_value.p_data = NULL;
		}
	}
	break;
	default:
		m_value = src.m_value;
		break;
	}
}

void jvalue::_free()
{
	switch (m_type) {
	case E_INT:
	{
		m_value.v_int64 = 0;
	}
	break;
	case E_BOOL:
	{
		m_value.v_bool = false;
	}
	break;
	case E_FLOAT:
	{
		m_value.v_double = 0.0;
	}
	break;
	case E_STRING:
	{
		if (NULL != m_value.p_string) {
			::free(m_value.p_string);
			m_value.p_string = NULL;
		}
	}
	break;
	case E_ARRAY:
	{
		if (NULL != m_value.p_array) {
			delete m_value.p_array;
			m_value.p_array = NULL;
		}
	}
	break;
	case E_OBJECT:
	{
		if (NULL != m_value.p_object) {
			delete m_value.p_object;
			m_value.p_object = NULL;
		}

	}
	break;
	case E_DATE:
	{
		m_value.v_date = 0;
	}
	break;
	case E_DATA:
	{
		if (NULL != m_value.p_data) {
			delete m_value.p_data;
			m_value.p_data = NULL;
		}
	}
	break;
	default:
		break;
	}
	m_type = E_NULL;
}

jvalue::jtype jvalue::type() const
{
	return m_type;
}

int jvalue::as_int() const
{
	return (int)as_int64();
}

int64_t	jvalue::as_int64() const
{
	switch (m_type) {
	case E_INT:
		return m_value.v_int64;
		break;
	case E_BOOL:
		return m_value.v_bool ? 1 : 0;
		break;
	case E_FLOAT:
		return int(m_value.v_double);
		break;
	case E_STRING:
		return _atoi64(as_cstr());
		break;
	default:
		break;
	}
	return 0;
}

double jvalue::as_double() const
{
	switch (m_type) {
	case E_INT:
		return double(m_value.v_int64);
		break;
	case E_BOOL:
		return m_value.v_bool ? 1.0 : 0.0;
		break;
	case E_FLOAT:
		return m_value.v_double;
		break;
	case E_STRING:
		return atof(as_cstr());
		break;
	default:
		break;
	}
	return 0.0;
}

bool jvalue::as_bool() const
{
	switch (m_type) {
	case E_BOOL:
		return m_value.v_bool;
		break;
	case E_INT:
		return (0 != m_value.v_int64);
		break;
	case E_FLOAT:
		return (0.0 != m_value.v_double);
		break;
	case E_ARRAY:
		return (NULL == m_value.p_array) ? false : (m_value.p_array->size() > 0);
		break;
	case E_OBJECT:
		return (NULL == m_value.p_object) ? false : (m_value.p_object->size() > 0);
		break;
	case E_STRING:
		return (NULL == m_value.p_string) ? false : (strlen(m_value.p_string) > 0);
		break;
	case E_DATE:
		return (m_value.v_date > 0);
		break;
	case E_DATA:
		return (NULL == m_value.p_data) ? false : (m_value.p_data->size() > 0);
		break;
	default:
		break;
	}
	return false;
}

string jvalue::as_string() const
{
	switch (m_type) {
	case E_BOOL:
		return m_value.v_bool ? "true" : "false";
		break;
	case E_INT:
	{
		char buf[32];
		::snprintf(buf, 32, "%" PRId64, m_value.v_int64);
		return buf;
	}
	break;
	case E_FLOAT:
	{
		char buf[256];
		::snprintf(buf, 256, "%lf", m_value.v_double);
		return buf;
	}
	break;
	case E_ARRAY:
		return "array";
		break;
	case E_OBJECT:
		return "object";
		break;
	case E_STRING:
		return (NULL == m_value.p_string) ? "" : m_value.p_string;
		break;
	case E_DATE:
	{
		char buf[256];
#ifdef _WIN32
		::snprintf(buf, 256, "%lld", m_value.v_date);
#else
		::snprintf(buf, 256, "%ld", m_value.v_date);	
#endif
		return buf;
	}
	break;
	case E_DATA:
		return as_data();
		break;
	default:
		break;
	}
	return "";
}

const char* jvalue::as_cstr() const
{
	if (E_STRING == m_type && NULL != m_value.p_string) {
		return m_value.p_string;
	}
	return "";
}

size_t jvalue::size() const
{
	switch (m_type) {
	case E_ARRAY:
		return (NULL == m_value.p_array) ? 0 : m_value.p_array->size();
		break;
	case E_OBJECT:
		return (NULL == m_value.p_object) ? 0 : m_value.p_object->size();
		break;
	case E_DATA:
		return (NULL == m_value.p_data) ? 0 : m_value.p_data->size();
		break;
	default:
		break;
	}
	return 0;
}

jvalue& jvalue::operator=(const jvalue& other)
{
	if (this != &other) {
		_free();
		_copy_value(other);
	}
	return (*this);
}

jvalue& jvalue::operator[](int index)
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

const jvalue& jvalue::operator[](int index) const
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

jvalue& jvalue::operator[](int64_t index)
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

const jvalue& jvalue::operator[](int64_t index) const
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

jvalue& jvalue::operator[](size_t index)
{
	if (E_ARRAY != m_type || NULL == m_value.p_array) {
		_free();
		m_type = E_ARRAY;
		m_value.p_array = new array();
	}

	size_t sum = m_value.p_array->size();
	if (sum <= index) {
		size_t fill = index - sum;
		for (size_t i = 0; i <= fill; i++) {
			m_value.p_array->push_back(null);
		}
	}

	return m_value.p_array->at(index);
}

const jvalue& jvalue::operator[](size_t index) const
{
	if (E_ARRAY == m_type && NULL != m_value.p_array) {
		if (index < m_value.p_array->size()) {
			return m_value.p_array->at(index);
		}
	}
	return null;
}

jvalue& jvalue::operator[](const string& key)
{
	return (*this)[key.c_str()];
}

const jvalue& jvalue::operator[](const string& key) const
{
	return (*this)[key.c_str()];
}

jvalue& jvalue::operator[](const char* key)
{
	if (E_OBJECT != m_type || NULL == m_value.p_object) {
		_free();
		m_type = E_OBJECT;
		m_value.p_object = new object();
	} else {
		auto it = m_value.p_object->find(key);
		if (it != m_value.p_object->end()) {
			return it->second;
		}
	}
	auto it = m_value.p_object->insert(m_value.p_object->end(), make_pair(key, null));
	return it->second;
}

const jvalue& jvalue::operator[](const char* key) const
{
	if (E_OBJECT == m_type && NULL != m_value.p_object) {
		auto it = m_value.p_object->find(key);
		if (it != m_value.p_object->end()) {
			return it->second;
		}
	}
	return null;
}

bool jvalue::has(int index) const
{
	if (index >= 0) {
		return has((size_t)index);
	}
	return false;
}

bool jvalue::has(size_t index) const
{
	if (E_ARRAY == m_type && NULL != m_value.p_array) {
		if (index < size()) {
			return true;
		}
	}
	return false;
}

bool jvalue::has(const char* key) const
{
	if (E_OBJECT == m_type && NULL != m_value.p_object) {
		if (m_value.p_object->end() != m_value.p_object->find(key)) {
			return true;
		}
	}
	return false;
}

bool jvalue::has(const string& key) const
{
	return has(key.c_str());
}

const jvalue& jvalue::at(int index) const
{
	return (*this)[(size_t)(index < 0 ? 0 : index)];
}

const jvalue& jvalue::at(size_t index) const
{
	return (*this)[index];
}

const jvalue& jvalue::at(const char* key) const
{
	return (*this)[key];
}

bool jvalue::erase(int index)
{
	if (index >= 0) {
		return erase((size_t)index);
	}
	return false;
}

bool jvalue::erase(size_t index)
{
	if (E_ARRAY == m_type && NULL != m_value.p_array) {
		if (index < m_value.p_array->size()) {
			m_value.p_array->erase(m_value.p_array->begin() + index);
			return true;
		}
	}
	return false;
}

bool jvalue::erase(const char* key)
{
	if (E_OBJECT == m_type && NULL != m_value.p_object) {
		if (m_value.p_object->end() != m_value.p_object->find(key)) {
			m_value.p_object->erase(key);
			return !has(key);
		}
	}
	return false;
}

bool jvalue::get_keys(vector<string>& keys) const
{
	if (E_OBJECT == m_type && NULL != m_value.p_object) {
		return _map_keys(keys);
	}
	return false;
}

bool jvalue::_map_keys(vector<string>& keys) const
{
	if (E_OBJECT == m_type && NULL != m_value.p_object) {
		keys.reserve(m_value.p_object->size());
		auto itbeg = m_value.p_object->begin();
		auto itend = m_value.p_object->end();
		for (; itbeg != itend; itbeg++) {
			keys.push_back((itbeg->first).c_str());
		}
		return true;
	}
	return false;
}

int jvalue::index(const char* elem) const
{
	if (E_ARRAY == m_type && NULL != m_value.p_array) {
		for (size_t i = 0; i < m_value.p_array->size(); i++) {
			if (elem == (*m_value.p_array)[i].as_string()) {
				return (int)i;
			}
		}
	}
	return -1;
}

string jvalue::write() const
{
	string strdoc;
	return write(strdoc);
}

const char* jvalue::write(string& strdoc) const
{
	strdoc.clear();
	jwriter::write((*this), strdoc);
	return strdoc.c_str();
}

bool jvalue::read(const string& strdoc, string* pstrerr)
{
	return read(strdoc.c_str(), pstrerr);
}

bool jvalue::read(const char* pdoc, string* pstrerr)
{
	jreader reader;
	bool bret = reader.parse(pdoc, *this);
	if (!bret) {
		if (NULL != pstrerr) {
			reader.error(*pstrerr);
		}
	}
	return bret;
}

jvalue& jvalue::front()
{
	if (E_ARRAY == m_type) {
		if (size() > 0) {
			return *(m_value.p_array->begin());
		}
	} else if (E_OBJECT == m_type) {
		if (size() > 0) {
			return m_value.p_object->begin()->second;
		}
	}
	return (*this);
}

jvalue& jvalue::back()
{
	if (E_ARRAY == m_type) {
		if (size() > 0) {
			return *(m_value.p_array->rbegin());
		}
	} else if (E_OBJECT == m_type) {
		if (size() > 0) {
			return prev(m_value.p_object->end())->second;
		}
	}
	return (*this);
}

bool jvalue::append(jvalue& jv)
{
	if ((E_OBJECT == m_type || E_NULL == m_type) && E_OBJECT == jv.type()) {
		vector<string> keys;
		jv.get_keys(keys);
		for (size_t i = 0; i < keys.size(); i++) {
			(*this)[keys[i]] = jv[keys[i]];
		}
		return true;
	} else if ((E_ARRAY == m_type || E_NULL == m_type) && E_ARRAY == jv.type()) {
		size_t count = this->size();
		for (size_t i = 0; i < jv.size(); i++) {
			(*this)[count] = jv[i];
			count++;
		}
		return true;
	}

	return false;
}

bool jvalue::push_back(int val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(bool val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(double val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(int64_t val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(const char* val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(const string& val)
{
	return push_back(jvalue(val));
}

bool jvalue::push_back(const jvalue& jval)
{
	if (E_ARRAY == m_type || E_NULL == m_type) {
		(*this)[size()] = jval;
		return true;
	}
	return false;
}

bool jvalue::push_back(const char* val, size_t len)
{
	return push_back(jvalue(val, len));
}

string jvalue::style_write() const
{
	string strdoc;
	return style_write(strdoc);
}

const char* jvalue::style_write(string& strdoc) const
{
	strdoc.clear();
	jwriter jw;
	strdoc = jw.style_write(*this);
	return strdoc.c_str();
}

void jvalue::assign_date(time_t val)
{
	_free();
	m_type = E_DATE;
	m_value.v_date = val;
}

void jvalue::assign_data(const uint8_t* data, size_t size)
{
	_free();
	m_type = E_DATA;
	m_value.p_data = new string();
	m_value.p_data->append((const char*)data, size);
}

void jvalue::assign_data(const char* base64)
{
	jbase64 b64;
	string output;
	b64.decode(base64, output);
	assign_data(output);
}

void jvalue::assign_data(const string& data)
{
	return assign_data(data.data(), data.size());
}

void jvalue::assign_data(const char* data, size_t size)
{
	return assign_data((const uint8_t*)data, size);
}

void jvalue::assign_date_string(time_t val)
{
	_free();
	m_type = E_STRING;
	m_value.p_string = _new_string(jwriter::d2s(val).c_str());
}

time_t jvalue::as_date() const
{
	switch (m_type) {
	case E_DATE:
		return m_value.v_date;
		break;
	case E_STRING:
	{
		if (is_date_string()) {
			tm ft = { 0 };
			sscanf_s(m_value.p_string + 5, "%04d-%02d-%02dT%02d:%02d:%02dZ", &ft.tm_year, &ft.tm_mon, &ft.tm_mday, &ft.tm_hour, &ft.tm_min, &ft.tm_sec);
			ft.tm_mon -= 1;
			ft.tm_year -= 1900;
			return mktime(&ft);
		}
	}
	break;
	case E_NULL:
	case E_INT:
	case E_FLOAT:
	case E_BOOL:
	case E_ARRAY:
	case E_OBJECT:
	case E_DATA:
		break;
	}
	return 0;
}

string jvalue::as_data() const
{
	switch (m_type) {
	case E_DATA:
		return (NULL == m_value.p_data) ? null_data : *m_value.p_data;
		break;
	case E_STRING:
	{
		string data;
		as_data(data);
		return data;
	}
	break;
	case E_NULL:
	case E_INT:
	case E_FLOAT:
	case E_BOOL:
	case E_ARRAY:
	case E_OBJECT:
	case E_DATE:
		break;
	}
	return null_data;
}

bool jvalue::as_data(string& data) const
{
	switch (m_type) {
	case E_DATA:
	{
		data = (NULL == m_value.p_data) ? null_data : *m_value.p_data;
		return true;
	}
	break;
	case E_STRING:
	{
		if (is_data_string()) {
			jbase64 b64;
			int data_len = 0;
			const char* pdata = b64.decode(m_value.p_string + 5, 0, &data_len);
			data.append(pdata, data_len);
			return true;
		}
	}
	break;
	case E_NULL:
	case E_INT:
	case E_FLOAT:
	case E_BOOL:
	case E_ARRAY:
	case E_OBJECT:
	case E_DATE:
		break;
	}
	return false;
}

bool jvalue::is_data() const
{
	return (E_DATA == m_type);
}

bool jvalue::is_date() const
{
	return (E_DATE == m_type);
}

bool jvalue::is_data_string() const
{
	if (E_STRING == m_type) {
		if (NULL != m_value.p_string) {
			if (strlen(m_value.p_string) >= 5) {
				if (0 == memcmp(m_value.p_string, "data:", 5)) {
					return true;
				}
			}
		}
	}

	return false;
}

bool jvalue::is_date_string() const
{
	if (E_STRING == m_type) {
		if (NULL != m_value.p_string) {
			if (25 == strlen(m_value.p_string)) {
				if (0 == memcmp(m_value.p_string, "date:", 5)) {
					const char* pdate = m_value.p_string + 5;
					if ('T' == pdate[10] && 'Z' == pdate[19]) {
						return true;
					}
				}
			}
		}
	}

	return false;
}

bool jvalue::read_plist(const string& strdoc, string* pstrerr /*= NULL*/, bool* is_binary /*= NULL*/)
{
	return read_plist(strdoc.data(), strdoc.size(), pstrerr, is_binary);
}

bool jvalue::read_plist(const char* pdoc, size_t len /*= 0*/, string* pstrerr /*= NULL*/, bool* is_binary /*= NULL*/)
{
	if (NULL == pdoc) {
		return false;
	}

	if (0 == len) {
		len = strlen(pdoc);
	}

	jpreader reader;
	bool bret = reader.parse(pdoc, len, *this, is_binary);
	if (!bret) {
		if (NULL != pstrerr) {
			reader.error(*pstrerr);
		}
	}

	return bret;
}

bool jvalue::_read_data_from_file(const char* path, string& data)
{
	data.clear();
	FILE* fp = NULL;
	_fopen64(fp, path, "rb");
	if (NULL != fp) {
		_fseeki64(fp, 0, SEEK_END);
		int64_t to_read = _ftelli64(fp);
		_fseeki64(fp, 0, SEEK_SET);
		to_read = (to_read > 0 ? to_read : 0);
		data.resize(to_read);
		if (data.capacity() >= (size_t)to_read) {
			int64_t readed = 0;
			while (readed < to_read) {
				size_t ret = fread(&(data[readed]), 1, to_read - readed, fp);
				if (ret <= 0) {
					break;
				}
				readed += ret;
			}
		}
		fclose(fp);
		return (data.size() == to_read);
	}
	return false;
}

bool jvalue::read_from_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	if (_read_data_from_file(file, data)) {
		return read(data);
	}
	return false;
}

bool jvalue::read_plist_from_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	if (_read_data_from_file(file, data)) {
		return read_plist(data);
	}
	return false;
}

bool jvalue::_write_data_to_file(const char* path, string& data)
{
	FILE* fp = NULL;
	_fopen64(fp, path, "wb");
	if (NULL != fp) {
		size_t written = 0;
		size_t to_write = data.size();
		while (written < to_write) {
			size_t ret = fwrite(data.data() + written, 1, to_write - written, fp);
			if (ret <= 0) {
				break;
			}
			written += ret;
		}
		fclose(fp);
		return (written == to_write);
	}
	return false;
}

bool jvalue::write_to_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	write(data);
	return _write_data_to_file(file, data);
}

bool jvalue::write_plist_to_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	write_plist(data);
	return _write_data_to_file(file, data);
}

bool jvalue::write_bplist_to_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	write_bplist(data);
	return _write_data_to_file(file, data);
}

bool jvalue::style_write_to_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	style_write(data);
	return _write_data_to_file(file, data);
}

bool jvalue::style_write_plist_to_file(const char* path, ...)
{
	char file[1024] = { 0 };
	va_list args;
	va_start(args, path);
	vsnprintf(file, 1024, path, args);
	va_end(args);

	string data;
	style_write_plist(data);
	return _write_data_to_file(file, data);
}

string jvalue::write_plist() const
{
	string strdoc;
	return write_plist(strdoc);
}

const char* jvalue::write_plist(string& strdoc) const
{
	strdoc.clear();
	jpwriter pw;
	pw.write((*this), strdoc);
	return strdoc.c_str();
}

string jvalue::style_write_plist() const
{
	string strdoc;
	return style_write_plist(strdoc);
}

const char* jvalue::style_write_plist(string& strdoc) const
{
	strdoc.clear();
	jpwriter pw;
	strdoc = pw.style_write(*this);
	return strdoc.c_str();
}

bool jvalue::write_bplist(string& strdoc) const
{
	strdoc.clear();
	jpwriter pw;
	pw.write_to_binary((*this), strdoc);
	return !strdoc.empty();
}

string jvalue::write_to_html() const
{
	string strdoc;
	jwriter::write_to_html((*this), strdoc);
	return strdoc;
}


// Class Reader
// //////////////////////////////////////////////////////////////////
jreader::jreader()
{
	m_pbegin = NULL;
	m_pend = NULL;
	m_pcursor = NULL;
	m_perror = NULL;
}

bool jreader::parse(const char* pdoc, jvalue& root)
{
	if (NULL != pdoc) {
		m_pbegin = pdoc;
		m_pend = m_pbegin + strlen(pdoc);
		m_pcursor = m_pbegin;
		m_perror = m_pbegin;
		m_strerr = "null";

		root.clear();
		return _read_value(root);
	}
	return false;
}

bool jreader::_read_value(jvalue& jval)
{
	jtoken token;
	_read_token(token);
	switch (token.type) {
	case jtoken::E_JTOKEN_TRUE:
		jval = true;
		break;
	case jtoken::E_JTOKEN_FALSE:
		jval = false;
		break;
	case jtoken::E_JTOKEN_NULL:
		jval = jvalue();
		break;
	case jtoken::E_JTOKEN_NUMBER:
		return _decode_number(token, jval);
		break;
	case jtoken::E_JTOKEN_ARRAY_BEGIN:
		return _read_array(jval);
		break;
	case jtoken::E_JTOKEN_OBJECT_BEGIN:
		return _read_object(jval);
		break;
	case jtoken::E_JTOKEN_STRING:
	{
		string strval;
		bool bok = _decode_string(token, strval);
		if (bok) {
			jval = strval.c_str();
		}
		return bok;
	}
	break;
	default:
		return _add_error("Syntax error: value, object or array expected.", token.pbegin);
		break;
	}
	return true;
}

bool jreader::_read_token(jtoken& token)
{
	_skip_spaces();
	token.pbegin = m_pcursor;
	switch (_get_next_char()) {
	case '{':
		token.type = jtoken::E_JTOKEN_OBJECT_BEGIN;
		break;
	case '}':
		token.type = jtoken::E_JTOKEN_OBJECT_END;
		break;
	case '[':
		token.type = jtoken::E_JTOKEN_ARRAY_BEGIN;
		break;
	case ']':
		token.type = jtoken::E_JTOKEN_ARRAY_END;
		break;
	case ',':
		token.type = jtoken::E_JTOKEN_ARRAY_SEPARATOR;
		break;
	case ':':
		token.type = jtoken::E_JTOKEN_MEMBER_SEPARATOR;
		break;
	case 0:
		token.type = jtoken::E_JTOKEN_END;
		break;
	case '"':
		token.type = _read_string() ? jtoken::E_JTOKEN_STRING : jtoken::E_JTOKEN_ERROR;
		break;
	case '/':
	case '#':
	case ';':
	{
		_skip_comment();
		return _read_token(token);
	}
	break;
	case '0':
	case '1':
	case '2':
	case '3':
	case '4':
	case '5':
	case '6':
	case '7':
	case '8':
	case '9':
	case '-':
	{
		token.type = jtoken::E_JTOKEN_NUMBER;
		_read_number();
	}
	break;
	case 't':
		token.type = _match("rue", 3) ? jtoken::E_JTOKEN_TRUE : jtoken::E_JTOKEN_ERROR;
		break;
	case 'f':
		token.type = _match("alse", 4) ? jtoken::E_JTOKEN_FALSE : jtoken::E_JTOKEN_ERROR;
		break;
	case 'n':
		token.type = _match("ull", 3) ? jtoken::E_JTOKEN_NULL : jtoken::E_JTOKEN_ERROR;
		break;
	default:
		token.type = jtoken::E_JTOKEN_ERROR;
		break;
	}
	token.pend = m_pcursor;
	return true;
}

void jreader::_skip_spaces()
{
	while (m_pcursor != m_pend) {
		char c = *m_pcursor;
		if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
			m_pcursor++;
		} else {
			break;
		}
	}
}

bool jreader::_match(const char* pattern, int pattern_length)
{
	if (m_pend - m_pcursor < pattern_length) {
		return false;
	}
	int index = pattern_length;
	while (index--) {
		if (m_pcursor[index] != pattern[index]) {
			return false;
		}
	}
	m_pcursor += pattern_length;
	return true;
}

void jreader::_skip_comment()
{
	char c = _get_next_char();
	if (c == '*') {
		while (m_pcursor != m_pend) {
			char c = _get_next_char();
			if (c == '*' && *m_pcursor == '/') {
				break;
			}
		}
	} else if (c == '/') {
		while (m_pcursor != m_pend) {
			char c = _get_next_char();
			if (c == '\r' || c == '\n') {
				break;
			}
		}
	}
}

void jreader::_read_number()
{
	while (m_pcursor != m_pend) {
		char c = *m_pcursor;
		if ((c >= '0' && c <= '9') || (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-')) {
			++m_pcursor;
		} else {
			break;
		}
	}
}

bool jreader::_read_string()
{
	char c = 0;
	while (m_pcursor != m_pend) {
		c = _get_next_char();
		if ('\\' == c) {
			_get_next_char();
		} else if ('"' == c) {
			break;
		}
	}
	return ('"' == c);
}

bool jreader::_read_object(jvalue& jval)
{
	string name;
	jtoken token_name;
	if (jvalue::E_OBJECT != jval.type()) {
		jval = jvalue(jvalue::E_OBJECT);
	}
	while (_read_token(token_name)) {
		if (jtoken::E_JTOKEN_OBJECT_END == token_name.type) {//empty
			return true;
		}

		if (jtoken::E_JTOKEN_STRING != token_name.type) {
			break;
		}

		if (!_decode_string(token_name, name)) {
			return false;
		}

		jtoken colon;
		_read_token(colon);
		if (jtoken::E_JTOKEN_MEMBER_SEPARATOR != colon.type) {
			return _add_error("missing ':' after object member name", colon.pbegin);
		}

		if (!_read_value(jval[name.c_str()])) {// error already set
			return false;
		}

		jtoken comma;
		_read_token(comma);
		if (jtoken::E_JTOKEN_OBJECT_END == comma.type) {
			return true;
		}

		if (jtoken::E_JTOKEN_ARRAY_SEPARATOR != comma.type) {
			return _add_error("missing ',' or '}' in object declaration", comma.pbegin);
		}
	}
	return _add_error("missing '}' or object member name", token_name.pbegin);
}


bool jreader::_read_array(jvalue& jval)
{
	jval = jvalue(jvalue::E_ARRAY);
	_skip_spaces();
	if (']' == *m_pcursor) // empty array
	{
		jtoken endArray;
		_read_token(endArray);
		return true;
	}

	size_t index = 0;
	while (true) {
		if (!_read_value(jval[index++])) {//error already set
			return false;
		}

		jtoken token;
		_read_token(token);
		if (jtoken::E_JTOKEN_ARRAY_END == token.type) {
			break;
		}
		if (jtoken::E_JTOKEN_ARRAY_SEPARATOR != token.type) {
			return _add_error("missing ',' or ']' in array declaration", token.pbegin);
		}
	}
	return true;
}

bool jreader::_decode_number(jtoken& token, jvalue& jval)
{
	int64_t val = 0;
	bool isNeg = false;
	const char* pcur = token.pbegin;
	if ('-' == *pcur) {
		pcur++;
		isNeg = true;
	}
	for (const char* p = pcur; p != token.pend; p++) {
		char c = *p;
		if ('.' == c || 'e' == c || 'E' == c) {
			return _decode_double(token, jval);
		} else if (c < '0' || c > '9') {
			return _add_error("'" + string(token.pbegin, token.pend) + "' is not a number.", token.pbegin);
		} else {
			val = val * 10 + (c - '0');
		}
	}
	jval = isNeg ? -val : val;
	return true;
}

bool jreader::_decode_double(jtoken& token, jvalue& jval)
{
	const size_t buf_len = 64;
	size_t len = size_t(token.pend - token.pbegin);
	if (len < buf_len) {
		char buf[buf_len] = { 0 };
		::memcpy(buf, token.pbegin, len);
		buf[len] = 0;
		double val = 0;
		if (1 == sscanf_s(buf, "%lf", &val)) {
			jval = val;
			return true;
		}
	}
	return _add_error("'" + string(token.pbegin, token.pend) + "' is too large or not a number.", token.pbegin);
}

bool jreader::_decode_string(jtoken& token, string& strdec)
{
	strdec = "";
	const char* pcur = token.pbegin + 1;
	const char* pend = token.pend - 1;
	strdec.reserve(size_t(token.pend - token.pbegin));
	while (pcur != pend) {
		char c = *pcur++;
		if ('\\' == c) {
			if (pcur != pend) {
				char escape = *pcur++;
				switch (escape) {
				case '"':
					strdec += '"';
					break;
				case '\\':
					strdec += '\\';
					break;
				case 'b':
					strdec += '\b';
					break;
				case 'f':
					strdec += '\f';
					break;
				case 'n':
					strdec += '\n';
					break;
				case 'r':
					strdec += '\r';
					break;
				case 't':
					strdec += '\t';
					break;
				case '/':
					strdec += '/';
					break;
				case 'u':
				{// based on description from http://en.wikipedia.org/wiki/UTF-8

					string strUnic;
					strUnic.append(pcur, 4);

					pcur += 4;

					unsigned int cp = 0;
					if (1 != sscanf_s(strUnic.c_str(), "%x", &cp)) {
						return _add_error("Bad escape sequence in string", pcur);
					}

					string strUTF8;

					if (cp <= 0x7f) {
						strUTF8.resize(1);
						strUTF8[0] = static_cast<char>(cp);
					} else if (cp <= 0x7FF) {
						strUTF8.resize(2);
						strUTF8[1] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[0] = static_cast<char>(0xC0 | (0x1f & (cp >> 6)));
					} else if (cp <= 0xFFFF) {
						strUTF8.resize(3);
						strUTF8[2] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[1] = 0x80 | static_cast<char>((0x3f & (cp >> 6)));
						strUTF8[0] = 0xE0 | static_cast<char>((0xf & (cp >> 12)));
					} else if (cp <= 0x10FFFF) {
						strUTF8.resize(4);
						strUTF8[3] = static_cast<char>(0x80 | (0x3f & cp));
						strUTF8[2] = static_cast<char>(0x80 | (0x3f & (cp >> 6)));
						strUTF8[1] = static_cast<char>(0x80 | (0x3f & (cp >> 12)));
						strUTF8[0] = static_cast<char>(0xF0 | (0x7 & (cp >> 18)));
					}

					strdec += strUTF8;
				}
				break;
				default:
					return _add_error("Bad escape sequence in string", pcur);
					break;
				}
			} else {
				return _add_error("Empty escape sequence in string", pcur);
			}
		} else if ('"' == c) {
			break;
		} else {
			strdec += c;
		}
	}
	return true;
}

bool jreader::_add_error(const string& message, const char* ploc)
{
	m_perror = ploc;
	m_strerr = message;
	return false;
}

char jreader::_get_next_char()
{
	return (m_pcursor == m_pend) ? 0 : *m_pcursor++;
}

void jreader::error(string& strmsg) const
{
	strmsg = "";
	int row = 1;
	const char* pcur = m_pbegin;
	const char* plast = m_pbegin;
	while (pcur < m_perror && pcur <= m_pend) {
		char c = *pcur++;
		if (c == '\r' || c == '\n') {
			if (c == '\r' && *pcur == '\n') {
				pcur++;
			}
			row++;
			plast = pcur;
		}
	}
	char msg[64] = { 0 };
	::snprintf(msg, 64, "error: line %d, column %d, ", row, int(m_perror - plast) + 1);
	strmsg += msg + m_strerr + "\n";
}

jwriter::jwriter()
{
	m_tab = "\t";
	m_add_child = false;
}

// Class Writer
// //////////////////////////////////////////////////////////////////
void jwriter::write(const jvalue& jval, string& strdoc)
{
	strdoc = "";
	_write_value(jval, strdoc);
}

void jwriter::_write_value(const jvalue& jval, string& strdoc)
{
	switch (jval.type()) {
	case jvalue::E_NULL:
		strdoc += "null";
		break;
	case jvalue::E_INT:
		strdoc += v2s(jval.as_int64());
		break;
	case jvalue::E_BOOL:
		strdoc += jval.as_bool() ? "true" : "false";
		break;
	case jvalue::E_FLOAT:
		strdoc += v2s(jval.as_double());
		break;
	case jvalue::E_STRING:
		strdoc += v2s(jval.as_cstr());
		break;
	case jvalue::E_ARRAY:
	{
		strdoc += "[";
		size_t usize = jval.size();
		for (size_t i = 0; i < usize; i++) {
			strdoc += (i > 0) ? "," : "";
			_write_value(jval[i], strdoc);
		}
		strdoc += "]";
	}
	break;
	case jvalue::E_OBJECT:
	{
		strdoc += "{";
		vector<string> keys;
		jval.get_keys(keys);
		size_t num_key = keys.size();
		for (size_t i = 0; i < num_key; i++) {
			const string& key_name = keys[i];
			strdoc += (i > 0) ? "," : "";
			strdoc += v2s(key_name.c_str()) + ":";
			_write_value(jval[key_name.c_str()], strdoc);
		}
		strdoc += "}";
	}
	break;
	case jvalue::E_DATE:
	{
		strdoc += "\"date:";
		strdoc += d2s(jval.as_date());
		strdoc += "\"";
	}
	break;
	case jvalue::E_DATA:
	{
		strdoc += "\"data:";
		const string& data = jval.as_data();
		jbase64 b64;
		strdoc += b64.encode(data.data(), (int)data.size());
		strdoc += "\"";
	}
	break;
	}
}

const string& jwriter::style_write(const jvalue& jval)
{
	m_strdoc = "";
	m_indent = "";
	m_add_child = false;
	_style_write_value(jval);
	m_strdoc += "\n";
	return m_strdoc;
}

void jwriter::_style_write_value(const jvalue& jval)
{
	switch (jval.type()) {
	case jvalue::E_NULL:
		_push_value("null");
		break;
	case jvalue::E_INT:
		_push_value(v2s(jval.as_int64()));
		break;
	case jvalue::E_BOOL:
		_push_value(jval.as_bool() ? "true" : "false");
		break;
	case jvalue::E_FLOAT:
		_push_value(v2s(jval.as_double()));
		break;
	case jvalue::E_STRING:
		_push_value(v2s(jval.as_cstr()));
		break;
	case jvalue::E_ARRAY:
		_style_write_array_value(jval);
		break;
	case jvalue::E_OBJECT:
	{
		vector<string> keys;
		jval.get_keys(keys);
		if (!keys.empty()) {
			m_strdoc += "{";
			m_indent += m_tab;
			size_t num_key = keys.size();
			for (size_t i = 0; i < num_key; i++) {
				const string& key_name = keys[i];
				m_strdoc += (i > 0) ? "," : "";
				m_strdoc += '\n' + m_indent + v2s(key_name.c_str()) + ": ";
				_style_write_value(jval[key_name]);
			}
			m_indent.resize(m_indent.size() - 1);
			m_strdoc += '\n' + m_indent + "}";
		} else {
			_push_value("{}");
		}
	}
	break;
	case jvalue::E_DATE:
	{
		string strdoc;
		strdoc += "\"date:";
		strdoc += d2s(jval.as_date());
		strdoc += "\"";
		_push_value(strdoc);
	}
	break;
	case jvalue::E_DATA:
	{
		string strdoc;
		strdoc += "\"data:";
		const string& data = jval.as_data();
		jbase64 b64;
		strdoc += b64.encode(data.data(), (int)data.size());
		strdoc += "\"";
		_push_value(strdoc);
	}
	break;
	}
}

void jwriter::_style_write_array_value(const jvalue& jval)
{
	size_t usize = jval.size();
	if (usize > 0) {
		bool isArrayMultiLine = _is_multiline_array(jval);
		if (isArrayMultiLine) {
			m_strdoc += "[";
			m_indent += m_tab;
			bool hasChildValue = !m_child_values.empty();
			for (size_t i = 0; i < usize; i++) {
				m_strdoc += (i > 0) ? "," : "";
				if (hasChildValue) {
					m_strdoc += '\n' + m_indent + m_child_values[i];
				} else {
					m_strdoc += '\n' + m_indent;
					_style_write_value(jval[i]);
				}
			}
			m_indent.resize(m_indent.size() - 1);
			m_strdoc += '\n' + m_indent + "]";
		} else {
			m_strdoc += "[ ";
			for (size_t i = 0; i < usize; ++i) {
				m_strdoc += (i > 0) ? ", " : "";
				m_strdoc += m_child_values[i];
			}
			m_strdoc += " ]";
		}
	} else {
		_push_value("[]");
	}
}

bool jwriter::_is_multiline_array(const jvalue& jval)
{
	m_child_values.clear();
	size_t usize = jval.size();
	bool is_multiline = (usize >= 25);
	if (!is_multiline) {
		for (size_t i = 0; i < usize; i++) {
			if (jval[i].size() > 0) {
				is_multiline = true;
				break;
			}
		}
	}
	if (!is_multiline) {
		m_add_child = true;
		m_child_values.reserve(usize);
		size_t lineLength = 4 + (usize - 1) * 2; // '[ ' + ', '*n + ' ]'
		for (size_t i = 0; i < usize; i++) {
			_style_write_value(jval[i]);
			lineLength += m_child_values[i].length();
		}
		m_add_child = false;
		is_multiline = lineLength >= 75;
	}
	return is_multiline;
}

void jwriter::_push_value(const string& strval)
{
	if (!m_add_child) {
		m_strdoc += strval;
	} else {
		m_child_values.push_back(strval);
	}
}

string jwriter::v2s(int64_t val)
{
	char buf[32] = { 0 };
	snprintf(buf, 32, "%" PRId64, val);
	return buf;
}

string jwriter::v2s(double val)
{
	char buf[128] = { 0 };
	snprintf(buf, 128, "%g", val);
	return buf;
}

string jwriter::d2s(time_t t)
{
	t = (t > 0x7933F8EFF) ? (0x7933F8EFF - 1) : t;

	tm ft = { 0 };

#ifdef _WIN32
	localtime_s(&ft, &t);
#else
	localtime_r(&t, &ft);
#endif

	ft.tm_year = (ft.tm_year < 0) ? 0 : ft.tm_year;
	ft.tm_mon = (ft.tm_mon < 0) ? 0 : ft.tm_mon;
	ft.tm_mday = (ft.tm_mday < 0) ? 0 : ft.tm_mday;
	ft.tm_hour = (ft.tm_hour < 0) ? 0 : ft.tm_hour;
	ft.tm_min = (ft.tm_min < 0) ? 0 : ft.tm_min;
	ft.tm_sec = (ft.tm_sec < 0) ? 0 : ft.tm_sec;

	char date[64] = { 0 };
	snprintf(date, 64, "%04d-%02d-%02dT%02d:%02d:%02dZ", ft.tm_year + 1900, ft.tm_mon + 1, ft.tm_mday, ft.tm_hour, ft.tm_min, ft.tm_sec);
	return date;
}

string jwriter::v2s(const char* pstr)
{
	if (NULL != strpbrk(pstr, "\"\\\b\f\n\r\t")) {
		string ret;
		ret.reserve(strlen(pstr) * 2 + 3);
		ret += "\"";
		for (const char* c = pstr; 0 != *c; c++) {
			switch (*c) {
			case '\\':
			{
				c++;
				bool is_unicode = false;
				if ('u' == *c) {
					bool bFlag = true;
					for (int i = 1; i <= 4; i++) {
						if (!isdigit(*(c + i))) {
							bFlag = false;
							break;
						}
					}
					is_unicode = bFlag;
				}

				if (true == is_unicode) {
					ret += "\\u";
				} else {
					ret += "\\\\";
					c--;
				}
			}
			break;
			case '\"':
				ret += "\\\"";
				break;
			case '\b':
				ret += "\\b";
				break;
			case '\f':
				ret += "\\f";
				break;
			case '\n':
				ret += "\\n";
				break;
			case '\r':
				ret += "\\r";
				break;
			case '\t':
				ret += "\\t";
				break;
			default:
				ret += *c;
				break;
			}
		}
		ret += "\"";
		return ret;
	} else {
		return string("\"") + pstr + "\"";
	}
}

void jwriter::write_to_html(const jvalue& jval, string& strdoc)
{
	strdoc = "";
	_write_value_to_html(jval, strdoc);
	strdoc += "\n";
}

void jwriter::_write_value_to_html(const jvalue& jval, string& strdoc)
{

	switch (jval.type()) {
	case jvalue::E_NULL:
		strdoc += "null";
		break;
	case jvalue::E_INT:
		strdoc += v2s(jval.as_int64());
		break;
	case jvalue::E_BOOL:
		strdoc += jval.as_bool() ? "true" : "false";
		break;
	case jvalue::E_FLOAT:
		strdoc += v2s(jval.as_double());
		break;
	case jvalue::E_STRING:
		strdoc += vstring2s(jval.as_cstr()); //don't escape here, escape before
		break;
	case jvalue::E_ARRAY:
	{
		strdoc += "[";
		size_t usize = jval.size();
		for (size_t i = 0; i < usize; i++) {
			strdoc += (i > 0) ? "," : "";
			_write_value_to_html(jval[i], strdoc);
		}
		strdoc += "]";
	}
	break;
	case jvalue::E_OBJECT:
	{
		strdoc += "{";
		vector<string> keys;
		jval.get_keys(keys);
		size_t num_key = keys.size();
		for (size_t i = 0; i < num_key; i++) {
			const string& key_name = keys[i];
			strdoc += (i > 0) ? "," : "";
			strdoc += vstring2s(key_name.c_str()) + ":";
			_write_value_to_html(jval[key_name.c_str()], strdoc);
		}
		strdoc += "}";
	}
	break;
	case jvalue::E_DATE:
	{
		strdoc += "\\\"date:";
		strdoc += d2s(jval.as_date());
		strdoc += "\\\"";
	}
	break;
	case jvalue::E_DATA:
	{
		strdoc += "\\\"data:";
		const string& data = jval.as_data();
		jbase64 b64;
		strdoc += b64.encode(data.data(), (int)data.size());
		strdoc += "\\\"";
	}
	break;
	}
}

string jwriter::vstring2s(const char* pstr)
{
	return string("\\\"") + pstr + "\\\"";

}

string jwriter::vstring2html(const char* pstr)
{

	if (NULL != strpbrk(pstr, "<>\"")) {
		string ret;
		ret.reserve(strlen(pstr) * 2 + 3);
		ret += "\\\"";
		for (const char* c = pstr; 0 != *c; c++) {
			switch (*c) {
			case '<':
				ret += "&lt;";
				break;
			case '>':
				ret += "&gt;";
				break;
			case '\"':
				ret += "&quot;";
				break;
				//	case '&':	ret += "&amp;";	break;
			default:
				ret += *c;
				break;
			}
		}
		ret += "\\\"";
		return ret;
	} else {
		return string("\\\"") + pstr + "\\\"";
	}

}

//////////////////////////////////////////////////////////////////////////
jpreader::jpreader()
{
	//xml
	m_pbegin = NULL;
	m_pend = NULL;
	m_pcursor = NULL;
	m_perror = NULL;

	//binary
	m_ptrailer = NULL;
	m_num_objects = 0;
	m_offset_table_offset_size = 0;
	m_poffset_table = 0;
	m_object_ref_size = 0;
	m_top_object_offset = 0;
}

bool jpreader::parse(const char* pdoc, size_t len, jvalue& root, bool* is_binary)
{
	root.clear();
	if (NULL == pdoc) {
		return false;
	}

	if (len < 30) {
		return false;
	}

	if (0 == ::memcmp(pdoc, "bplist00", 8)) {
		if (NULL != is_binary) {
			*is_binary = true;
		}
		return parse_binary(pdoc, len, root);
	} else {
		if (NULL != is_binary) {
			*is_binary = false;
		}
		m_pbegin = pdoc;
		m_pend = m_pbegin + len;
		m_pcursor = m_pbegin;
		m_perror = m_pbegin;
		m_strerr = "null";

		ptoken token;
		_read_token(token);
		return _read_value(root, token);
	}
}

bool jpreader::_read_value(jvalue& pval, ptoken& token)
{
	switch (token.type) {
	case ptoken::E_PTOKEN_TRUE:
		pval = true;
		break;
	case ptoken::E_PTOKEN_FALSE:
		pval = false;
		break;
	case ptoken::E_PTOKEN_NULL:
		pval = jvalue();
		break;
	case ptoken::E_PTOKEN_STRING_NULL:
		pval = jvalue(jvalue::E_STRING);
		break;
	case ptoken::E_PTOKEN_DICTIONARY_NULL:
		pval = jvalue(jvalue::E_OBJECT);
		break;
	case ptoken::E_PTOKEN_ARRAY_NULL:
		pval = jvalue(jvalue::E_ARRAY);
		break;
	case ptoken::E_PTOKEN_DATA_NULL:
		pval = jvalue(jvalue::E_DATA);
		break;
	case ptoken::E_PTOKEN_DATE_NULL:
		pval = jvalue(jvalue::E_DATE);
		break;
	case ptoken::E_PTOKEN_INTEGER_NULL:
		pval = jvalue(jvalue::E_INT);
		break;
	case ptoken::E_PTOKEN_REAL_NULL:
		pval = jvalue(jvalue::E_FLOAT);
		break;
	case ptoken::E_PTOKEN_NUMBER:
		return _decode_number(token, pval);
		break;
	case ptoken::E_PTOKEN_ARRAY_BEGIN:
		return _read_array(pval);
		break;
	case ptoken::E_PTOKEN_DICTIONARY_BEGIN:
		return _read_dictionary(pval);
		break;
	case ptoken::E_PTOKEN_DATE:
	{
		string strval;
		_decode_string(token, strval);

		tm ft = { 0 };
		::sscanf_s(strval.c_str(), "%04d-%02d-%02dT%02d:%02d:%02dZ", &ft.tm_year, &ft.tm_mon, &ft.tm_mday, &ft.tm_hour, &ft.tm_min, &ft.tm_sec);
		ft.tm_mon -= 1;
		ft.tm_year -= 1900;
		pval.assign_date(mktime(&ft));
	}
	break;
	case ptoken::E_PTOKEN_DATA:
	{
		string strval;
		_decode_string(token, strval);
		pval.assign_data(strval.c_str());
	}
	break;
	case ptoken::E_PTOKEN_STRING:
	{
		string strval;
		_decode_string(token, strval);
		pval = strval.c_str();
	}
	break;
	default:
		return _add_error("Syntax error: value, dictionary or array expected.", token.pbegin);
		break;
	}
	return true;
}

bool jpreader::_read_label(string& label)
{
	_skip_spaces();

	char c = *m_pcursor++;
	if ('<' != c) {
		return false;
	}

	label.clear();
	label.reserve(10);
	label += c;

	bool bEnd = false;
	while (m_pcursor != m_pend) {
		c = *m_pcursor++;
		if ('>' == c) {
			if ('/' == *(m_pcursor - 1) || '?' == *(m_pcursor - 1)) {
				label += *(m_pcursor - 1);
			}

			label += c;
			break;
		} else if (' ' == c) {
			bEnd = true;
		} else if (!bEnd) {
			label += c;
		}
	}

	if ('>' != c) {
		label.clear();
		return false;
	}

	return (!label.empty());
}

void jpreader::_end_label(ptoken& token, const char* end_label)
{
	string label;
	_read_label(label);
	if (end_label != label) {
		token.type = ptoken::E_PTOKEN_ERROR;
	}
}

bool jpreader::_read_token(ptoken& token)
{
	string label;
	if (!_read_label(label)) {
		token.type = ptoken::E_PTOKEN_ERROR;
		return false;
	}

	if ('?' == label.at(1) || '!' == label.at(1)) {
		return _read_token(token);
	}

	if ("<dict>" == label) {
		token.type = ptoken::E_PTOKEN_DICTIONARY_BEGIN;
	} else if ("</dict>" == label) {
		token.type = ptoken::E_PTOKEN_DICTIONARY_END;
	} else if ("<array>" == label) {
		token.type = ptoken::E_PTOKEN_ARRAY_BEGIN;
	} else if ("</array>" == label) {
		token.type = ptoken::E_PTOKEN_ARRAY_END;
	} else if ("<key>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_string() ? ptoken::E_PTOKEN_KEY : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</key>");
	} else if ("<string>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_string() ? ptoken::E_PTOKEN_STRING : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</string>");
	} else if ("<date>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_string() ? ptoken::E_PTOKEN_DATE : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</date>");
	} else if ("<data>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_string() ? ptoken::E_PTOKEN_DATA : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</data>");
	} else if ("<integer>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_number() ? ptoken::E_PTOKEN_NUMBER : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</integer>");
	} else if ("<real>" == label) {
		token.pbegin = m_pcursor;
		token.type = _read_number() ? ptoken::E_PTOKEN_NUMBER : ptoken::E_PTOKEN_ERROR;
		token.pend = m_pcursor;
		_end_label(token, "</real>");
	} else if ("<true/>" == label) {
		token.type = ptoken::E_PTOKEN_TRUE;
	} else if ("<false/>" == label) {
		token.type = ptoken::E_PTOKEN_FALSE;
	} else if ("<dict/>" == label) {
		token.type = ptoken::E_PTOKEN_DICTIONARY_NULL;
	} else if ("<array/>" == label) {
		token.type = ptoken::E_PTOKEN_ARRAY_NULL;
	} else if ("<data/>" == label) {
		token.type = ptoken::E_PTOKEN_DATA_NULL;
	} else if ("<date/>" == label) {
		token.type = ptoken::E_PTOKEN_DATE_NULL;
	} else if ("<integer/>" == label) {
		token.type = ptoken::E_PTOKEN_INTEGER_NULL;
	} else if ("<real/>" == label) {
		token.type = ptoken::E_PTOKEN_REAL_NULL;
	} else if ("<string/>" == label) {
		token.type = ptoken::E_PTOKEN_STRING_NULL;
	} else if ("<plist>" == label) {
		return _read_token(token);
	} else if ("</plist>" == label || "<plist/>" == label) {
		token.type = ptoken::E_PTOKEN_END;
	} else {
		token.type = ptoken::E_PTOKEN_ERROR;
	}

	return true;
}

void jpreader::_skip_spaces()
{
	while (m_pcursor != m_pend) {
		char c = *m_pcursor;
		if (c == ' ' || c == '\t' || c == '\r' || c == '\n') {
			m_pcursor++;
		} else {
			break;
		}
	}
}

bool jpreader::_read_number()
{
	while (m_pcursor != m_pend) {
		char c = *m_pcursor;
		if ((c >= '0' && c <= '9') || (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-')) {
			++m_pcursor;
		} else {
			break;
		}
	}
	return true;
}

bool jpreader::_read_string()
{
	while (m_pcursor != m_pend) {
		if ('<' == *m_pcursor) {
			break;
		}
		m_pcursor++;
	}
	return ('<' == *m_pcursor);
}

bool jpreader::_read_dictionary(jvalue& pval)
{
	ptoken key;
	string strkey;
	if (jvalue::E_OBJECT != pval.type()) {
		pval = jvalue(jvalue::E_OBJECT);
	}
	while (_read_token(key)) {
		if (ptoken::E_PTOKEN_DICTIONARY_END == key.type) {//empty
			return true;
		}

		if (ptoken::E_PTOKEN_KEY != key.type) {
			break;
		}

		strkey = "";
		if (!_decode_string(key, strkey)) {
			return false;
		}

		ptoken val;
		_read_token(val);
		if (!_read_value(pval[strkey.c_str()], val)) {
			return false;
		}
	}
	return _add_error("missing '</dict>' or dictionary member name", key.pbegin);
}

bool jpreader::_read_array(jvalue& pval)
{
	pval = jvalue(jvalue::E_ARRAY);

	size_t index = 0;
	while (true) {
		ptoken elem;
		_read_token(elem);
		if (ptoken::E_PTOKEN_ARRAY_END == elem.type) {
			return true;
		} else if (ptoken::E_PTOKEN_KEY == elem.type) { //dictionary, found in ipod nano 1
			string strkey = "";
			if (!_decode_string(elem, strkey)) {
				return false;
			}
			ptoken tval;
			_read_token(tval);
			if (!_read_value(pval[index++][strkey.c_str()], tval)) {
				return false;
			}
		} else {
			if (!_read_value(pval[index++], elem)) {
				return false;
			}
		}
	}

	return true;
}

bool jpreader::_decode_number(ptoken& token, jvalue& pval)
{
	int64_t val = 0;
	bool is_negative = false;
	const char* pcursor = token.pbegin;
	if ('-' == *pcursor) {
		pcursor++;
		is_negative = true;
	}
	for (const char* p = pcursor; p != token.pend; p++) {
		char c = *p;
		if ('.' == c || 'e' == c || 'E' == c) {
			return _decode_double(token, pval);
		} else if (c < '0' || c > '9') {
			return _add_error("'" + string(token.pbegin, token.pend) + "' is not a number.", token.pbegin);
		} else {
			val = val * 10 + (c - '0');
		}
	}
	pval = is_negative ? -val : val;
	return true;
}

bool jpreader::_decode_double(ptoken& token, jvalue& pval)
{
	const size_t buf_len = 64;
	size_t len = size_t(token.pend - token.pbegin);
	if (len < buf_len) {
		char buf[buf_len] = { 0 };
		::memcpy(buf, token.pbegin, len);
		buf[len] = 0;
		double val = 0;
		if (1 == sscanf_s(buf, "%lf", &val)) {
			pval = val;
			return true;
		}
	}
	return _add_error("'" + string(token.pbegin, token.pend) + "' is too large or not a number.", token.pbegin);
}

bool jpreader::_decode_string(ptoken& token, string& strdec)
{
	const char* pcursor = token.pbegin;
	const char* pend = token.pend;
	strdec.reserve(size_t(token.pend - token.pbegin) + 6);
	while (pcursor != pend) {
		char c = *pcursor++;
		if ('\n' != c && '\r' != c && '\t' != c) {
			strdec += c;
		}
	}
	return true;
}

bool jpreader::_add_error(const string& message, const char* ploc)
{
	m_perror = ploc;
	m_strerr = message;
	return false;
}

void jpreader::error(string& strmsg) const
{
	strmsg = "";
	int row = 1;
	const char* pcursor = m_pbegin;
	const char* plast = m_pbegin;
	while (pcursor < m_perror && pcursor <= m_pend) {
		char c = *pcursor++;
		if (c == '\r' || c == '\n') {
			if (c == '\r' && *pcursor == '\n') {
				pcursor++;
			}
			row++;
			plast = pcursor;
		}
	}
	char msg[64] = { 0 };
	::snprintf(msg, 64, "error: line %d, column %d, ", row, int(m_perror - plast) + 1);
	strmsg += msg + m_strerr + "\n";
}

//////////////////////////////////////////////////////////////////////////
uint32_t jpreader::_get_uint24_from_be(const char* v)
{
	uint32_t ret = 0;
	::memcpy(&ret, v, 3);
	jpwriter::_byte_convert((uint8_t*)&ret, sizeof(ret));
	return ret;
}

uint64_t jpreader::_get_uint_val(const char* v, size_t size)
{
	if (8 == size)
		return jpwriter::_swap(*((uint64_t*)v));
	else if (4 == size)
		return jpwriter::_swap(*((uint32_t*)v));
	else if (3 == size)
		return _get_uint24_from_be(v);
	else if (2 == size)
		return jpwriter::_swap(*((uint16_t*)v));
	else
		return *((uint8_t*)v);
}

bool jpreader::_read_uint_size(const char*& pcur, size_t& size)
{
	jvalue temp;
	_read_binary_value(pcur, temp);
	if (temp.is_int()) {
		size = (size_t)temp.as_int64();
		return true;
	}
	assert(0);
	return false;
}

bool jpreader::_read_unicode(const char* pcursor, size_t size, jvalue& pv)
{
	if (0 == size) {
		pv = "";
		return false;
	}

	uint16_t* unistr = (uint16_t*)::malloc(2 * size);
	if (NULL == unistr) {
		return false;
	}

	::memcpy(unistr, pcursor, 2 * size);
	for (size_t i = 0; i < size; i++) {
		jpwriter::_byte_convert((uint8_t*)(unistr + i), 2);
	}

	char* outbuf = (char*)::malloc(3 * (size + 1));
	if (NULL == outbuf) {
		return false;
	}

	size_t p = 0;
	size_t i = 0;
	uint16_t wc = 0;
	while (i < size) {
		wc = unistr[i++];
		if (wc >= 0x800) {
			outbuf[p++] = (char)(0xE0 + ((wc >> 12) & 0xF));
			outbuf[p++] = (char)(0x80 + ((wc >> 6) & 0x3F));
			outbuf[p++] = (char)(0x80 + (wc & 0x3F));
		} else if (wc >= 0x80) {
			outbuf[p++] = (char)(0xC0 + ((wc >> 6) & 0x1F));
			outbuf[p++] = (char)(0x80 + (wc & 0x3F));
		} else {
			outbuf[p++] = (char)(wc & 0x7F);
		}
	}

	outbuf[p] = 0;
	pv = outbuf;
	::free(outbuf);
	outbuf = NULL;

	::free(unistr);
	unistr = NULL;
	return true;
}

bool jpreader::_read_binary_value(const char*& pcursor, jvalue& pv)
{
	uint8_t c = *pcursor++;
	uint8_t type = c & 0xF0;
	uint8_t	value = c & 0x0F;

	switch (type) {
	case BPLIST_NULL:
	{
		switch (value) {
		case BPLIST_NULL:
			pv = jvalue(jvalue::E_NULL);
			break;
		case NS_NUMBER_FALSE:
			pv = false;
			break;
		case NS_NUMBER_TRUE:
			pv = true;
			break;
		case NS_URL_BASE_STRING:
		case NS_URL_STRING:
		case NS_UUID:
			pv = jvalue(jvalue::E_NULL);
			break;
		default:
			pv = jvalue(jvalue::E_NULL);
			break;
		}
	}
	break;
	case NS_NUMBER_INT:
	{
		uint8_t size = 1 << value;
		switch (size) {
			case sizeof(uint8_t) :
				case sizeof(uint16_t) :
				case sizeof(uint32_t) :
				case sizeof(uint64_t) :
				pv = (int64_t)_get_uint_val(pcursor, size);
				break;
				default:
					pv = 0;
					break;
		};
		pcursor += size;
	}
	break;
	case NS_NUMBER_REAL:
	{
		if (2 == value) {
			float real = 0;
			::memcpy(&real, pcursor, sizeof(float));
			pv = (double)jpwriter::_swap(real);
		} else if (3 == value) {
			double real = 0;
			::memcpy(&real, pcursor, sizeof(double));
			pv = jpwriter::_swap(real);
		} else {
			return false;
		}
	}
	break;
	case NS_DATE:
	{
		if (3 == value) {
			double date = 0;
			::memcpy(&date, pcursor, sizeof(double));
			date = jpwriter::_swap(date);
			pv.assign_date(((time_t)date) + 978278400);
		}
	}
	break;
	case NS_DATA:
	{
		size_t size = value;
		if (0x0F == value) {
			if (!_read_uint_size(pcursor, size)) {
				return false;
			}
		}
		pv.assign_data((const uint8_t*)pcursor, size);
	}
	break;
	case NS_STRING_ASCII:
	case NS_STRING_UTF8:
	{
		size_t size = value;
		if (0x0F == value) {
			if (!_read_uint_size(pcursor, size)) {
				return false;
			}
		}

		string strval;
		strval.append(pcursor, size);
		strval.append(1, 0);
		pv = strval.c_str();
	}
	break;
	case NS_STRING_UNICODE:
	{
		size_t size = value;
		if (0x0F == value) {
			if (!_read_uint_size(pcursor, size)) {
				return false;
			}
		}

		_read_unicode(pcursor, size, pv);
	}
	break;
	case NS_ARRAY:
	case NS_SET:
	{
		size_t size = value;
		if (0x0F == value) {
			if (!_read_uint_size(pcursor, size)) {
				return false;
			}
		}

		pv = jvalue(jvalue::E_ARRAY);
		for (size_t i = 0; i < size; i++) {
			uint64_t index = _get_uint_val((const char*)pcursor + i * m_object_ref_size, m_object_ref_size);
			if (index < m_num_objects) {
				const char* paddr = (m_pbegin + _get_uint_val(m_poffset_table + index * m_offset_table_offset_size, m_offset_table_offset_size));
				_read_binary_value(paddr, pv[i]);
			} else {
				assert(0);
				return false;
			}
		}
	}
	break;
	case NS_DICTIONARY:
	{
		size_t size = value;
		if (0x0F == value) {
			if (!_read_uint_size(pcursor, size)) {
				return false;
			}
		}

		if (jvalue::E_OBJECT != pv.type()) {
			pv = jvalue(jvalue::E_OBJECT);
		}

		for (size_t i = 0; i < size; i++) {
			jvalue jkey;
			jvalue jval;

			uint64_t key_index = _get_uint_val((const char*)pcursor + i * m_object_ref_size, m_object_ref_size);
			uint64_t value_index = _get_uint_val((const char*)pcursor + (i + size) * m_object_ref_size, m_object_ref_size);

			if (key_index < m_num_objects) {
				const char* paddr = (m_pbegin + _get_uint_val(m_poffset_table + key_index * m_offset_table_offset_size, m_offset_table_offset_size));
				_read_binary_value(paddr, jkey);
			}

			if (value_index < m_num_objects) {
				const char* paddr = (m_pbegin + _get_uint_val(m_poffset_table + value_index * m_offset_table_offset_size, m_offset_table_offset_size));
				_read_binary_value(paddr, jval);
			}

			if (jkey.is_string() && !jval.is_null()) {
				pv[jkey.as_cstr()] = jval;
			}
		}
	}
	break;
	case BPLIST_UID:
	{
		uint8_t size = value + 1;
		switch (size) {
			case sizeof(uint8_t) :
				case sizeof(uint16_t) :
				case sizeof(uint32_t) :
				case sizeof(uint64_t) :
				pv = (int64_t)_get_uint_val(pcursor, size);
				break;
				default:
					pv = 0;
					break;
		};
		pcursor += size;
	}
	break;
	case BPLIST_FILL:
	{

	}
	break;
	default:
	{
		assert(0);
		return false;
	}
	break;
	}

	return true;
}

bool jpreader::parse_binary(const char* pbdoc, size_t len, jvalue& pv)
{
	m_pbegin = pbdoc;

	m_ptrailer = m_pbegin + len - 26;

	m_offset_table_offset_size = m_ptrailer[0];
	m_object_ref_size = m_ptrailer[1];
	m_num_objects = _get_uint_val(m_ptrailer + 2, 8);
	m_top_object_offset = _get_uint_val(m_ptrailer + 10, 8);

	if (0 == m_num_objects) {
		return false;
	}

	m_poffset_table = m_pbegin + _get_uint_val(m_ptrailer + 18, 8);
	const char* pval = (m_pbegin + _get_uint_val(m_poffset_table + m_offset_table_offset_size * m_top_object_offset, m_offset_table_offset_size));
	return _read_binary_value(pval, pv);
}

jpwriter::jpwriter()
{
	m_tab = "\t";
	m_line = "\n";
}

//////////////////////////////////////////////////////////////////////////
void jpwriter::write(const jvalue& pval, string& strdoc)
{
	m_tab = "";
	m_line = "";
	strdoc = _style_write(pval);
}

uint8_t jpwriter::_get_integer_length(int64_t value)
{
	if (value > 0 && value < (1 << 8)) {
		return 0;
	} else if (value > 0 && value < (1 << 16)) {
		return 1;
	} else if (value > 0 && value < ((int64_t)1 << 32)) {
		return 2;
	} else {
		return 3;
	}
}

void jpwriter::_byte_convert(uint8_t* v, size_t size)
{
	uint8_t tmp = 0;
	for (size_t i = 0, j = 0; i < (size / 2); i++) {
		tmp = v[i];
		j = (size - 1) - i;
		v[i] = v[j];
		v[j] = tmp;
	}
}

uint16_t jpwriter::_swap(uint16_t value)
{
	return ((((value) & 0xFF00) >> 8) | (((value) & 0x00FF) << 8));
}

uint32_t jpwriter::_swap(uint32_t value)
{
	return ((((value) & 0xFF000000) >> 24) |
		(((value) & 0x00FF0000) >> 8) |
		(((value) & 0x0000FF00) << 8) |
		(((value) & 0x000000FF) << 24));
}

uint64_t jpwriter::_swap(uint64_t value)
{
	return  ((((value) & 0xFF00000000000000ull) >> 56) |
		(((value) & 0x00FF000000000000ull) >> 40) |
		(((value) & 0x0000FF0000000000ull) >> 24) |
		(((value) & 0x000000FF00000000ull) >> 8) |
		(((value) & 0x00000000FF000000ull) << 8) |
		(((value) & 0x0000000000FF0000ull) << 24) |
		(((value) & 0x000000000000FF00ull) << 40) |
		(((value) & 0x00000000000000FFull) << 56));
}

float jpwriter::_swap(float value)
{
	_byte_convert((uint8_t*)&value, sizeof(value));
	return value;
}

double jpwriter::_swap(double value)
{
	_byte_convert((uint8_t*)&value, sizeof(value));
	return value;
}

uint8_t jpwriter::_get_integer_bytes(int64_t value)
{
	if (value > 0 && value < (1 << 8)) {
		return 1;
	} else if (value > 0 && value < (1 << 16)) {
		return 2;
	} else if (value > 0 && value < ((int64_t)1 << 32)) {
		return 4;
	} else {
		return 8;
	}
}

int jpwriter::_get_serialize_integer(uint8_t* data, uint8_t length, int64_t value)
{
	switch (length) {
	case 1:
		data[0] = (uint8_t)value;
		break;
	case 2:
		data[0] = (uint8_t)(value >> 8);
		data[1] = (uint8_t)value;
		break;
	case 4:
		data[0] = (uint8_t)(value >> 24);
		data[1] = (uint8_t)(value >> 16);
		data[2] = (uint8_t)(value >> 8);
		data[3] = (uint8_t)value;
		break;
	case 8:
		data[0] = (uint8_t)(value >> 56);
		data[1] = (uint8_t)(value >> 48);
		data[2] = (uint8_t)(value >> 40);
		data[3] = (uint8_t)(value >> 32);
		data[4] = (uint8_t)(value >> 24);
		data[5] = (uint8_t)(value >> 16);
		data[6] = (uint8_t)(value >> 8);
		data[7] = (uint8_t)value;
		break;
	default:
		return -1;
	}
	return length;
}

void jpwriter::write_to_binary(const jvalue& pval, string& strdoc)
{
	strdoc.clear();

	vector<bplist_object> array_objects;
	vector<uint64_t> array_offset_indexes;
	_write_value_to_binary(pval, array_objects, array_offset_indexes);

	//check object ref size
	uint8_t object_ref_size = 1;
	uint64_t offset_table_size = array_offset_indexes.size();
	if (offset_table_size < (1 << 8)) {
		object_ref_size = 1;
	} else  if (offset_table_size < (1 << 16)) {
		object_ref_size = 2;
	} else if (offset_table_size < ((int64_t)1 << 32)) {
		object_ref_size = 4;
	} else {
		object_ref_size = 8;
	}

	//rebuild dictionary and array object data ad build address
	uint64_t start_address = 0x08;
	vector<uint64_t> array_offset_addresses;
	for (size_t i = 0; i < array_objects.size(); i++) {

		//rebuild dictionary and array object data
		bplist_object& object = array_objects[i];
		if (jpreader::NS_DICTIONARY == object.type || jpreader::NS_ARRAY == object.type) {

			object.data.clear();
			if (jpreader::NS_ARRAY == object.type) {
				_serialize_object_size(object.data, jpreader::NS_ARRAY, object.indexes.size());
			} else if (jpreader::NS_DICTIONARY == object.type) {
				_serialize_object_size(object.data, jpreader::NS_DICTIONARY, (object.indexes.size() / 2));
			}
			for (size_t j = 0; j < object.indexes.size(); j++) {
				if (1 == object_ref_size) {
					uint8_t index = (uint8_t)object.indexes[j];
					object.data.append((const char*)&index, sizeof(index));
				} else if (2 == object_ref_size) {
					uint16_t index = _swap((uint16_t)object.indexes[j]);
					object.data.append((const char*)&index, sizeof(index));
				} else if (4 == object_ref_size) {
					uint32_t index = _swap((uint32_t)object.indexes[j]);
					object.data.append((const char*)&index, sizeof(index));
				} else {
					uint64_t index = _swap((uint64_t)object.indexes[j]);
					object.data.append((const char*)&index, sizeof(index));
				}
			}

		}

		//build offset table address
		array_offset_addresses.push_back(start_address);
		start_address += object.data.size();
	}

	//header
	strdoc.append("bplist00", 8);

	//objects
	for (size_t i = 0; i < array_objects.size(); i++) {
		strdoc.append(array_objects[i].data);
	}

	uint64_t offset_table_start = strdoc.size();

	//offset table
	uint8_t offset_table_offset_size = 1;
	if (start_address < (1 << 8)) {
		offset_table_offset_size = 1;

		uint8_t root = (uint8_t)array_offset_addresses[(size_t)array_offset_indexes.back()];
		strdoc.append((const char*)&root, sizeof(root));

		for (size_t i = 0; i < array_offset_indexes.size() - 1; i++) {
			uint8_t index = (uint8_t)array_offset_addresses[(size_t)array_offset_indexes[i]];
			strdoc.append((const char*)&index, sizeof(index));
		}

	} else if (start_address < (1 << 16)) {
		offset_table_offset_size = 2;

		uint16_t root = _swap((uint16_t)array_offset_addresses[(size_t)array_offset_indexes.back()]);
		strdoc.append((const char*)&root, sizeof(root));

		for (size_t i = 0; i < array_offset_indexes.size() - 1; i++) {
			uint16_t index = _swap((uint16_t)array_offset_addresses[(size_t)array_offset_indexes[i]]);
			strdoc.append((const char*)&index, sizeof(index));
		}

	} else if (start_address < ((int64_t)1 << 32)) {
		offset_table_offset_size = 4;

		uint32_t root = _swap((uint32_t)array_offset_addresses[(size_t)array_offset_indexes.back()]);
		strdoc.append((const char*)&root, sizeof(root));

		for (size_t i = 0; i < array_offset_indexes.size() - 1; i++) {
			uint32_t index = _swap((uint32_t)array_offset_addresses[(size_t)array_offset_indexes[i]]);
			strdoc.append((const char*)&index, sizeof(index));
		}
	} else {
		offset_table_offset_size = 8;

		uint64_t root = _swap((uint64_t)array_offset_addresses[(size_t)array_offset_indexes.back()]);
		strdoc.append((const char*)&root, sizeof(root));

		for (size_t i = 0; i < array_offset_indexes.size() - 1; i++) {
			uint64_t index = _swap((uint64_t)array_offset_addresses[(size_t)array_offset_indexes[i]]);
			strdoc.append((const char*)&index, sizeof(index));
		}
	}

	//tailer
	strdoc.append(6, '\0');

	uint8_t val[2] = { 0 };
	val[0] = offset_table_offset_size;
	val[1] = object_ref_size;

	strdoc.append((const char*)val, 2);

	uint64_t num_objects = array_objects.size();
	num_objects = _swap(num_objects);
	strdoc.append((const char*)&num_objects, sizeof(uint64_t));

	uint64_t top_object_offset = 0;
	top_object_offset = _swap(top_object_offset);
	strdoc.append((const char*)&top_object_offset, sizeof(uint64_t));

	offset_table_start = _swap(offset_table_start);
	strdoc.append((const char*)&offset_table_start, sizeof(uint64_t));
}

void jpwriter::_serialize_object_size(string& data, jpreader::bplist_object_type object_type, int64_t object_size)
{
	if (jpreader::NS_NUMBER_INT != object_type) {
		if (object_size < 15) {
			uint8_t type = (uint8_t)(object_type | object_size);
			data.append((const char*)&type, sizeof(type));
			return;
		} else {
			uint8_t type = object_type | 0x0F;
			data.append((const char*)&type, sizeof(type));
		}
	}

	uint8_t value[9] = { 0 };
	value[0] = jpreader::NS_NUMBER_INT | _get_integer_length(object_size);

	uint8_t length = _get_integer_bytes(object_size);
	_get_serialize_integer(value + 1, length, object_size);
	data.append((const char*)value, length + 1);
}

bool jpwriter::_contains_unicode_char(const char* str, size_t len)
{
	for (size_t i = 0; i < len; i++) {
		uint8_t c = (uint8_t)str[i];
		if (c & 0x80) {
			return true;
		}
	}
	return false;
}

bool jpwriter::_utf8_to_utf16(const char* utf8, size_t len, string& utf16)
{
	size_t i = 0;
	while (i < len) {
		uint32_t codepoint = 0;
		size_t extra_bytes = 0;
		uint8_t first = (uint8_t)utf8[i];
		if (first <= 0x7F) {
			codepoint = first;
			extra_bytes = 0;
		} else if ((first & 0xE0) == 0xC0) {
			codepoint = first & 0x1F;
			extra_bytes = 1;
		} else if ((first & 0xF0) == 0xE0) {
			codepoint = first & 0x0F;
			extra_bytes = 2;
		} else if ((first & 0xF8) == 0xF0) {
			codepoint = first & 0x07;
			extra_bytes = 3;
		} else {
			return false;
		}

		if (i + extra_bytes >= len) {
			return false;
		}

		for (size_t j = 1; j <= extra_bytes; ++j) {
			codepoint = (codepoint << 6) | (((uint8_t)utf8[i + j]) & 0x3F);
		}

		uint16_t uc = 0;
		if (codepoint <= 0xFFFF) {
			uc = _swap(static_cast<uint16_t>(codepoint));
			utf16.append((const char*)&uc, sizeof(uc));
		} else {
			codepoint -= 0x10000;
			uc = _swap(static_cast<uint16_t>(0xD800 + (codepoint >> 10)));
			utf16.append((const char*)&uc, sizeof(uc));
			uc = _swap(static_cast<uint16_t>(0xDC00 + (codepoint & 0x3FF)));
			utf16.append((const char*)&uc, sizeof(uc));
		}

		i += extra_bytes + 1;
	}

	return true;
}

int64_t jpwriter::_write_value_to_binary(const jvalue& pval, vector<bplist_object>& array_objects, vector<uint64_t>& array_offset_indexes)
{
	bplist_object object;
	if (pval.is_object()) {
		object.type = jpreader::NS_DICTIONARY;
		vector<string> keys;
		pval.get_keys(keys);
		size_t obj_size = keys.size();
		_serialize_object_size(object.data, jpreader::NS_DICTIONARY, obj_size);

		vector<int64_t> key_indexes;
		vector<int64_t> val_indexes;
		for (size_t i = 0; i < obj_size; i++) {
			int64_t key_index = _write_value_to_binary(keys[i].c_str(), array_objects, array_offset_indexes);
			int64_t val_index = _write_value_to_binary(pval[keys[i].c_str()], array_objects, array_offset_indexes);
			key_indexes.push_back(key_index);
			val_indexes.push_back(val_index);
		}

		for (size_t i = 0; i < key_indexes.size(); i++) {
			int64_t& index = key_indexes[i];
			object.indexes.push_back(index);
			object.data.append((const char*)&index, sizeof(index));
		}
		for (size_t i = 0; i < val_indexes.size(); i++) {
			int64_t& index = val_indexes[i];
			object.indexes.push_back(index);
			object.data.append((const char*)&index, sizeof(index));
		}

	} else if (pval.is_array()) {
		object.type = jpreader::NS_ARRAY;
		size_t obj_size = pval.size();
		_serialize_object_size(object.data, jpreader::NS_ARRAY, obj_size);
		for (size_t i = 0; i < obj_size; i++) {
			int64_t index = _write_value_to_binary(pval[i], array_objects, array_offset_indexes);
			object.indexes.push_back(index);
			object.data.append((const char*)&index, sizeof(index));
		}
	} else if (pval.is_date()) {
		object.type = jpreader::NS_DATE;
		double dval = _swap((double)(pval.as_date() - 978278400));
		uint8_t type = jpreader::NS_DATE | 3;
		object.data.append((const char*)&type, 1);
		object.data.append((const char*)&dval, sizeof(double));
	} else if (pval.is_data()) {
		object.type = jpreader::NS_DATA;
		string strData = pval.as_data();
		size_t obj_size = strData.size();
		_serialize_object_size(object.data, jpreader::NS_DATA, obj_size);
		object.data.append(strData.data(), obj_size);
	} else if (pval.is_string()) { //must behind date and data
		const char* szVal = pval.as_cstr();
		size_t obj_size = strlen(szVal);
		bool unicode = false;
		if (_contains_unicode_char(szVal, obj_size)) {
			string utf16;
			if (_utf8_to_utf16(szVal, obj_size, utf16)) {
				unicode = true;
				object.type = jpreader::NS_STRING_UNICODE;
				obj_size = utf16.size() / 2;
				_serialize_object_size(object.data, jpreader::NS_STRING_UNICODE, obj_size);
				object.data.append(utf16);
			}
		}
		if (!unicode) {
			object.type = jpreader::NS_STRING_ASCII;
			_serialize_object_size(object.data, jpreader::NS_STRING_ASCII, obj_size);
			object.data.append((const char*)szVal, obj_size);
		}
	} else if (pval.is_bool()) {
		object.type = jpreader::BPLIST_NULL;
		uint8_t type = jpreader::BPLIST_NULL | (pval.as_bool() ? jpreader::NS_NUMBER_TRUE : jpreader::NS_NUMBER_FALSE);
		object.data.append((const char*)&type, 1);
	} else if (pval.is_int()) {
		object.type = jpreader::NS_NUMBER_INT;
		_serialize_object_size(object.data, jpreader::NS_NUMBER_INT, pval.as_int64());
	} else if (pval.is_double()) {
		object.type = jpreader::NS_NUMBER_REAL;
		double dval = _swap(pval.as_double());
		uint8_t type = jpreader::NS_NUMBER_REAL | 3;
		object.data.append((const char*)&type, 1);
		object.data.append((const char*)&dval, sizeof(double));
	} else if (pval.is_null()) {
		object.type = jpreader::BPLIST_NULL;
		object.data.append(1, '\0');
	} else {
		assert(0);
		object.type = jpreader::BPLIST_NULL;
		object.data.append(1, '\0');
	}

	int64_t offset_index = -1;
	size_t object_size = object.data.size();
	for (size_t i = 0; i < array_objects.size(); i++) {
		if (array_objects[i].type == object.type) {
			if (array_objects[i].data.size() == object_size) {
				if (0 == ::memcmp(array_objects[i].data.data(), object.data.data(), object_size)) {
					offset_index = i;
				}
			}
		}
	}

	if (offset_index < 0) {
		array_objects.push_back(object);
		offset_index = array_objects.size() - 1;
		array_offset_indexes.push_back(offset_index);
	}

	return offset_index + 1;
}

const string& jpwriter::style_write(const jvalue& pval)
{
	m_tab = "\t";
	m_line = "\n";
	return _style_write(pval);
}

const string& jpwriter::_style_write(const jvalue& pval)
{
	m_indent = "";
	m_strdoc = "";
	m_strdoc += "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + m_line;
	m_strdoc += "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">" + m_line;
	m_strdoc += "<plist version=\"1.0\">" + m_line;
	_style_write_value(pval);
	m_strdoc += "</plist>" + m_line;
	return m_strdoc;
}

void jpwriter::_style_write_value(const jvalue& pval)
{
	if (pval.is_object()) {
		vector<string> keys;
		pval.get_keys(keys);
		if (!keys.empty()) {
			m_strdoc += m_indent + "<dict>" + m_line;
			m_indent += m_tab;
			for (size_t i = 0; i < keys.size(); i++) {
				string strkey = keys[i];
				_xml_escape(strkey);
				m_strdoc += m_indent + "<key>";
				m_strdoc += strkey;
				m_strdoc += "</key>" + m_line;
				_style_write_value(pval[keys[i].c_str()]);
			}
			if (!m_indent.empty()) {
				m_indent.resize(m_indent.size() - 1);
			}
			m_strdoc += m_indent + "</dict>" + m_line;
		} else {
			m_strdoc += m_indent + "<dict/>" + m_line;
		}
	} else if (pval.is_array()) {
		if (pval.size() > 0) {
			m_strdoc += m_indent + "<array>" + m_line;
			m_indent += m_tab;
			for (size_t i = 0; i < pval.size(); i++) {
				_style_write_value(pval[i]);
			}
			if (!m_indent.empty()) {
				m_indent.resize(m_indent.size() - 1);
			}
			m_strdoc += m_indent + "</array>" + m_line;
		} else {
			m_strdoc += m_indent + "<array/>" + m_line;
		}
	} else if (pval.is_date()) {
		m_strdoc += m_indent + "<date>";
		m_strdoc += jwriter::d2s(pval.as_date());
		m_strdoc += "</date>" + m_line;
	} else if (pval.is_data()) {
		m_strdoc += m_indent + "<data>" + m_line;
		m_strdoc += m_indent;
		jbase64 b64;
		string strdata = pval.as_data();
		m_strdoc += b64.encode(strdata.data(), (int32_t)strdata.size());
		m_strdoc += m_line;
		m_strdoc += m_indent + "</data>" + m_line;
	} else if (pval.is_string()) {
		if (pval.is_date_string()) {
			m_strdoc += m_indent + "<date>";
			m_strdoc += pval.as_string().c_str() + 5;
			m_strdoc += "</date>" + m_line;
		} else if (pval.is_data_string()) {
			m_strdoc += m_indent + "<data>" + m_line;
			m_strdoc += m_indent;
			m_strdoc += pval.as_string().c_str() + 5;
			m_strdoc += m_line;
			m_strdoc += m_indent + "</data>" + m_line;
		} else {
			string strval = pval.as_cstr();
			_xml_escape(strval);
			m_strdoc += m_indent + "<string>";
			m_strdoc += strval;
			m_strdoc += "</string>" + m_line;
		}
	} else if (pval.is_bool()) {
		m_strdoc += m_indent + (pval.as_bool() ? "<true/>" : "<false/>") + m_line;
	} else if (pval.is_int()) {
		m_strdoc += m_indent + "<integer>";
		char temp[32];
		snprintf(temp, 32, "%" PRId64, pval.as_int64());
		m_strdoc += temp;
		m_strdoc += "</integer>" + m_line;
	} else if (pval.is_double()) {
		m_strdoc += m_indent + "<real>";
		double v = pval.as_double();
		if (numeric_limits<double>::infinity() == v) {
			m_strdoc += "+infinity";
		} else {
			char temp[32];
			if (floor(v) == v) {
				snprintf(temp, sizeof(temp), "%" PRId64, (int64_t)v);
			} else {
				snprintf(temp, sizeof(temp), "%.15lf", v);
			}
			m_strdoc += temp;
		}
		m_strdoc += "</real>" + m_line;
	} else {
		m_strdoc += m_indent + "<integer>0</integer>" + m_line;
	}
}

void jpwriter::_xml_escape(string& str)
{
	_string_replace(str, "&", "&amp;");
	_string_replace(str, "<", "&lt;");
	//_string_replace(str, ">", "&gt;");	//optional
	//_string_replace(str, "'", "&apos;");	//optional
	//_string_replace(str, "\"", "&quot;");	//optional
}

string& jpwriter::_string_replace(string& context, const string& from, const string& to)
{
	size_t query = 0;
	size_t found = 0;
	while ((found = context.find(from, query)) != string::npos) {
		context.replace(found, from.size(), to);
		query = found + to.size();
	}
	return context;
}