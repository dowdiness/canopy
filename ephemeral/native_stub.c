#include <moonbit.h>

#ifdef _WIN32

#include <windows.h>

MOONBIT_FFI_EXPORT uint64_t now_ms_ffi() {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
  /* FILETIME is 100-ns intervals since 1601-01-01; convert to ms since epoch */
  return (t - 116444736000000000ULL) / 10000ULL;
}

#else

#include <time.h>

MOONBIT_FFI_EXPORT uint64_t now_ms_ffi() {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  return (uint64_t)ts.tv_sec * 1000 + (uint64_t)ts.tv_nsec / 1000000;
}

#endif
