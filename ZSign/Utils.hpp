//
//  Utils.hpp
//  feather
//
//  Created by samara on 30.09.2024.
//

#ifndef Utils_hpp
#define Utils_hpp

#include <stdio.h>


#ifdef __cplusplus
extern "C" {
#endif

const char* getDocumentsDirectory();
void writeToNSLog(const char* msg);
void refreshFile(const char* path);

#ifdef __cplusplus
}
#endif

#endif /* zsign_hpp */
