#pragma once

#ifdef __cplusplus
extern "C" {
#endif

int addko_python_probe(void);
int addko_python_configure(const char* home);
int addko_python_initialize(void);
int addko_python_is_initialized(void);
int addko_python_exec(const char* code);
int addko_python_shutdown(void);
const char* addko_python_version(void);
const char* addko_python_home(void);
const char* addko_python_last_error(void);

#ifdef __cplusplus
}
#endif
