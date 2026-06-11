// libghostty.a is prebuilt with Zig's vanilla libc++ headers, which emit a
// strong (non-weak) reference to std::__1::__libcpp_verbose_abort. The system
// libc++.1.dylib only exports that symbol since iOS 16.3 / macOS 13.3 /
// tvOS 16.3, so on older OS versions dyld kills the app at launch with
// "Symbol missing". Defining it here resolves the reference at link time
// instead of importing it from libc++.1.dylib.

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

__attribute__((visibility("hidden"), noreturn, format(printf, 1, 2)))
void sb_libcpp_verbose_abort(const char *format, ...) __asm__("__ZNSt3__122__libcpp_verbose_abortEPKcz");

void sb_libcpp_verbose_abort(const char *format, ...) {
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    abort();
}
