// MPFever macOS probe, step 2 (game build 26129055 of Transport Fever 3 for Mac, arm64): can a module of ours change the game's
// code, and can it hook a function of the game? Two small things, both checked byte by byte first:
//   1. the Lua string-hash seed (lua_newstate's makeseed, the main cause of desyncs on Windows) becomes a constant;
//   2. the function that applies the queued commands ("Simulation Thread: Apply Command") is hooked: every call is counted.
// Nothing else changes. Log: $HOME/mpfever-probe2.log. Freestanding (no libc, no SDK), cross-built by build-probe.sh.
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

struct Line { char s[512]; int n; };
static void put(struct Line* l, const char* s) { while (*s && l->n < 500) l->s[l->n++] = *s++; }
static void hex(struct Line* l, u64 v) { char t[17]; int k = 0; do { int d = (int)(v & 15); t[k++] = (char)(d < 10 ? '0' + d : 'a' + d - 10); v >>= 4; } while (v); put(l, "0x"); while (k && l->n < 500) l->s[l->n++] = t[--k]; }
static void dec(struct Line* l, u64 v) { char t[21]; int k = 0; do { t[k++] = (char)('0' + v % 10); v /= 10; } while (v); while (k && l->n < 500) l->s[l->n++] = t[--k]; }

static i64 g_fd = -1;
static void flush(struct Line* l) { l->s[l->n++] = '\n'; if (g_fd >= 0) sys3(SYS_write, g_fd, (i64)l->s, l->n); l->n = 0; }

// ------------------------------------------------------------ what we know about this build (file addresses, before the slide)
#define A_APPLY       0x100a6fa34UL   // the command-applying function of the simulation thread (4 position-independent instructions at its start)
#define A_SEED_BL     0x103f833fcUL   // lua_newstate: bl luaS_hash(buff, 32, time) = the string-hash seed
#define W_SEED_BL     0x94000112u
#define W_SEED_PRE    0x52800401u     // mov w1,#0x20 just before it
#define W_SEED_POST   0xb9012260u     // str w0,[x19,#0x120] just after it
#define SEED_CONST    0x5288ca00u     // movz w0,#0x4650: the seed, the same in every game
static const u32 APPLY_WORDS[4] = { 0xa9ba6ffc, 0xa90167fa, 0xa9025ff8, 0xa90357f6 };

u64 apply_resume;            // the original function, after the 4 instructions the thunk runs itself
volatile u32 apply_calls;

void on_apply(u64 self, u64 cmds)
{
    u32 n = __atomic_add_fetch(&apply_calls, 1, __ATOMIC_RELAXED);
    if (n <= 10 || n % 2000 == 0) {
        struct Line l; l.n = 0;
        put(&l, "apply call #"); dec(&l, n); put(&l, " self "); hex(&l, self); put(&l, " cmds "); hex(&l, cmds);
        flush(&l);
    }
}

// the hooked function's start jumps here: save the arguments, count, put them back, run the 4 instructions that were overwritten
__asm__(
    ".text\n.p2align 2\n.globl _apply_thunk\n_apply_thunk:\n"
    "  sub sp, sp, #0xb0\n"
    "  stp x0, x1, [sp, #0]\n  stp x2, x3, [sp, #16]\n  stp x4, x5, [sp, #32]\n  stp x6, x7, [sp, #48]\n  stp x8, x30, [sp, #64]\n"
    "  stp q0, q1, [sp, #80]\n  stp q2, q3, [sp, #112]\n"
    "  bl _on_apply\n"
    "  ldp q2, q3, [sp, #112]\n  ldp q0, q1, [sp, #80]\n"
    "  ldp x8, x30, [sp, #64]\n  ldp x6, x7, [sp, #48]\n  ldp x4, x5, [sp, #32]\n  ldp x2, x3, [sp, #16]\n  ldp x0, x1, [sp, #0]\n"
    "  add sp, sp, #0xb0\n"
    "  stp x28, x27, [sp, #-0x60]!\n  stp x26, x25, [sp, #0x10]\n  stp x24, x23, [sp, #0x20]\n  stp x22, x21, [sp, #0x30]\n"
    "  adrp x16, _apply_resume@PAGE\n  ldr x16, [x16, _apply_resume@PAGEOFF]\n  br x16\n"
);
extern void apply_thunk(void);

static int patch(u64 addr, const u32* words, int count)
{
    u64 page = addr & ~0x3FFFUL;
    int r = mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 2 | 0x10);   // read | write | copy
    if (r) return r;
    for (int i = 0; i < count; i++) ((volatile u32*)addr)[i] = words[i];
    sys_icache_invalidate((void*)addr, (u64)count * 4);
    return mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 4);          // read | execute
}

__attribute__((constructor)) static void probe2_init(void)
{
    struct Line l; l.n = 0;
    const char* home = getenv_("HOME"); if (!home) home = "/tmp";
    char path[512]; int pn = 0;
    while (*home && pn < 450) path[pn++] = *home++;
    const char* tail = "/mpfever-probe2.log"; for (int i = 0; tail[i]; i++) path[pn++] = tail[i];
    path[pn] = 0;
    g_fd = sys3(SYS_open, (i64)path, 0x0001 | 0x0200 | 0x0008, 0644);
    put(&l, "MPFever probe 2 loaded, pid "); dec(&l, (u64)sys3(SYS_getpid, 0, 0, 0)); flush(&l);

    // the game's own image and its slide
    long slide = 0; int found = 0;
    u32 n = _dyld_image_count();
    for (u32 i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        int L = len(nm);
        const char* want = "/TransportFever3";
        int W = len(want);
        if (L >= W) { int k = 0; while (k < W && nm[L - W + k] == want[k]) k++; if (k == W) { slide = _dyld_get_image_vmaddr_slide(i); found = 1; break; } }
    }
    if (!found) { put(&l, "game image not found: nothing patched"); flush(&l); return; }
    put(&l, "game slide "); hex(&l, (u64)slide); flush(&l);
    const char* skip = getenv_("MPFEVER_PROBE2_SKIP");
    if (skip && skip[0] == '1') { put(&l, "MPFEVER_PROBE2_SKIP=1: nothing patched"); flush(&l); return; }

    // 1. the Lua seed
    volatile u32* seed = (volatile u32*)(A_SEED_BL + (u64)slide);
    if (seed[-1] == W_SEED_PRE && seed[0] == W_SEED_BL && seed[1] == W_SEED_POST) {
        u32 w = SEED_CONST;
        int r = patch((u64)seed, &w, 1);
        put(&l, "seed patch: result "); dec(&l, (u64)(unsigned)r); put(&l, " now "); hex(&l, seed[0]); flush(&l);
    } else {
        put(&l, "seed place does not match this game build: "); hex(&l, seed[-1]); put(&l, " "); hex(&l, seed[0]); put(&l, " "); hex(&l, seed[1]); flush(&l);
    }

    // 2. the apply-command hook
    volatile u32* fn = (volatile u32*)(A_APPLY + (u64)slide);
    int same = 1; for (int i = 0; i < 4; i++) if (fn[i] != APPLY_WORDS[i]) same = 0;
    if (same) {
        apply_resume = A_APPLY + (u64)slide + 16;
        u64 th = (u64)&apply_thunk;
        u32 w[4] = { 0x58000050u, 0xd61f0200u, (u32)(th & 0xffffffffu), (u32)(th >> 32) };   // ldr x16,#8 ; br x16 ; .quad thunk
        int r = patch((u64)fn, w, 4);
        put(&l, "apply hook: result "); dec(&l, (u64)(unsigned)r); put(&l, " at "); hex(&l, (u64)fn); flush(&l);
    } else {
        put(&l, "apply place does not match this game build: "); hex(&l, fn[0]); put(&l, " "); hex(&l, fn[1]); flush(&l);
    }
}
