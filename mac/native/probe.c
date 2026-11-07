// MPFever macOS probe, step 1: does the game load a module of ours, and where is it in memory?
// Freestanding (no libc, no SDK): it is cross-built on Linux with clang + lld for arm64-apple-macos.
// It writes ~/mpfever-probe.log (path from $HOME) and changes nothing in the game.
typedef unsigned long u64;
typedef unsigned int u32;
typedef long i64;

static i64 sys3(i64 n, i64 a, i64 b, i64 c)
{
    register i64 x16 __asm__("x16") = n;
    register i64 x0 __asm__("x0") = a;
    register i64 x1 __asm__("x1") = b;
    register i64 x2 __asm__("x2") = c;
    __asm__ volatile("svc #0x80" : "+r"(x0) : "r"(x16), "r"(x1), "r"(x2) : "memory", "cc");
    return x0;
}
enum { SYS_exit = 1, SYS_write = 4, SYS_open = 5, SYS_getpid = 20 };

extern char** environ;   // from dyld (dylib) via libSystem
extern const void* _dyld_get_image_header(u32 i);
extern u32 _dyld_image_count(void);
extern const char* _dyld_get_image_name(u32 i);
extern long _dyld_get_image_vmaddr_slide(u32 i);

static int len(const char* s) { int n = 0; while (s[n]) n++; return n; }

static char buf[4096]; static int bn;
static void put(const char* s) { while (*s && bn < 4000) buf[bn++] = *s++; }
static void hex(u64 v) { char t[17]; int k = 0; do { int d = (int)(v & 15); t[k++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v >>= 4; } while (v); put("0x"); while (k) buf[bn++] = t[--k]; }
static void dec(u64 v) { char t[21]; int k = 0; do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v); while (k) buf[bn++] = t[--k]; }

static const char* getenv_(const char* name)
{
    int n = len(name);
    for (char** e = environ; e && *e; e++) {
        int i = 0; while (i < n && (*e)[i] == name[i]) i++;
        if (i == n && (*e)[n] == '=') return *e + n + 1;
    }
    return 0;
}

__attribute__((constructor)) static void probe_init(void)
{
    const char* home = getenv_("HOME");
    if (!home) home = "/tmp";
    char path[512]; int pn = 0;
    while (*home && pn < 450) path[pn++] = *home++;
    const char* tail = "/mpfever-probe.log"; for (int i = 0; tail[i]; i++) path[pn++] = tail[i];
    path[pn] = 0;
    put("MPFever probe loaded, pid "); dec((u64)sys3(SYS_getpid, 0, 0, 0)); put("\n");
    u32 n = _dyld_image_count();
    put("images: "); dec(n); put("\n");
    for (u32 i = 0; i < n && i < 400; i++) {
        const char* nm = _dyld_get_image_name(i);
        int L = len(nm);
        // the game's executable and our own module (the first image is the executable)
        if (i == 0 || (L >= 11 && nm[L-11] == 'p' && nm[L-10] == 'r' && nm[L-9] == 'o' && nm[L-8] == 'b' && nm[L-7] == 'e')) {
            put("  #"); dec(i); put(" "); put(nm); put("  header "); hex((u64)_dyld_get_image_header(i)); put("  slide "); hex((u64)_dyld_get_image_vmaddr_slide(i)); put("\n");
        }
    }
    const char* d = getenv_("DYLD_INSERT_LIBRARIES");
    put("DYLD_INSERT_LIBRARIES="); put(d ? d : "(not set)"); put("\n");
    // a read of the game's own code: the first bytes of __text (the file has them at 0x100006500 before the slide)
    long slide = _dyld_get_image_vmaddr_slide(0);
    const unsigned char* t = (const unsigned char*)(0x100006500UL + (u64)slide);
    put("game code at 0x100006500+slide: ");
    for (int i = 0; i < 16; i++) { static const char* H = "0123456789abcdef"; buf[bn++] = H[t[i] >> 4]; buf[bn++] = H[t[i] & 15]; }
    put("\n");
    i64 fd = sys3(SYS_open, (i64)path, 0x0001 | 0x0200 | 0x0008, 0644);   // O_WRONLY | O_CREAT | O_APPEND
    if (fd >= 0) sys3(SYS_write, fd, (i64)buf, bn);
}
