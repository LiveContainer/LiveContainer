#pragma once

#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <limits.h>
#include <math.h>
#include <assert.h>
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _WIN32

#include "common_win32.h"

#else

#include <unistd.h>
#include <ftw.h>
#include <dirent.h>
#include <libgen.h>
#include <getopt.h>
#include <sys/mman.h>
#include <sys/time.h>

#define _fopen64(fp, path, mode) {fp = fopen(path, mode); }
#define _fseeki64	fseeko
#define _ftelli64	ftello

#endif

#include <set>
#include <map>
#include <mutex>
#include <vector>
#include <string>
#include <memory>
#include <iostream>
#include <algorithm>
#include <functional>
using namespace std;

#define FORMAT_V(x, format) char format[1024] = { 0 }; \
                        	va_list va_args; \
							va_start(va_args, x); \
							vsnprintf(format, 1024, x, va_args); \
							va_end(va_args);

#include "fs.h"
#include "sha.h"
#include "log.h"
#include "util.h"
