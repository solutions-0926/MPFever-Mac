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
enum { SYS_write = 4, SYS_open = 5, SYS_getpid = 20 };

extern char** environ;
extern u32 _dyld_image_count(void);
extern const char* _dyld_get_image_name(u32 i);
extern long _dyld_get_image_vmaddr_slide(u32 i);
extern u32 mach_task_self_;
extern int mach_vm_protect(u32 task, u64 addr, u64 size, int set_max, int prot);
extern void sys_icache_invalidate(void* start, u64 len);
extern int pthread_create(u64* t, const void* attr, void* (*fn)(void*), void* arg);
extern int usleep(u32 us);

static int len(const char* s) { int n = 0; while (s[n]) n++; return n; }
static const char* getenv_(const char* name)
{
    int n = len(name);
    for (char** e = environ; e && *e; e++) {
        int i = 0; while (i < n && (*e)[i] == name[i]) i++;
        if (i == n && (*e)[n] == '=') return *e + n + 1;
    }
    return 0;
}
struct Line { char s[640]; int n; };
static void put(struct Line* l, const char* s) { while (*s && l->n < 600) l->s[l->n++] = *s++; }
static void hex(struct Line* l, u64 v) { char t[17]; int k = 0; do { int d = (int)(v & 15); t[k++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v >>= 4; } while (v); put(l, "0x"); while (k && l->n < 600) l->s[l->n++] = t[--k]; }
static void dec(struct Line* l, u64 v) { char t[21]; int k = 0; do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v); while (k && l->n < 600) l->s[l->n++] = t[--k]; }
static i64 g_fd = -1;
static void flush(struct Line* l) { l->s[l->n++] = '\n'; if (g_fd >= 0) sys3(SYS_write, g_fd, (i64)l->s, l->n); l->n = 0; }
