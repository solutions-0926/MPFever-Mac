
static u64 g_slide;
static char g_mark[512];

static int patch(u64 addr, const u32* words, int count)
{
    u64 page = addr & ~0x3FFFUL;
    int r = mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 2 | 0x10);   // read | write | copy
    if (r) return r;
    for (int i = 0; i < count; i++) ((volatile u32*)addr)[i] = words[i];
    sys_icache_invalidate((void*)addr, (u64)count * 4);
    return mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 4);          // read | execute
}

static u32 snap_calls[NHOOKS], snap_main[NHOOKS];

static void* heartbeat(void* unused)
{
    (void)unused;
    u32 marks = 0;
    for (u32 tick = 1; tick < 20000; tick++) {
        usleep(250000);
        if (access(g_mark, 0) != 0) continue;
        unlink(g_mark);
        marks++;
        struct Line l; l.n = 0;
        put(&l, "MARK "); dec(&l, marks); put(&l, ": functions called since the last mark (file address, calls, from the main thread, caller)");
        flush(&l);
        for (int i = 0; i < NHOOKS; i++) {
            u32 c = hook_calls[i], m = hook_main[i];
            if (c != snap_calls[i]) {
                put(&l, "  "); hex(&l, HADDR[i]); put(&l, " calls "); dec(&l, c - snap_calls[i]); put(&l, " main "); dec(&l, m - snap_main[i]);
                put(&l, " lr "); hex(&l, hook_lr[i] - g_slide);
                flush(&l);
            }
            snap_calls[i] = c; snap_main[i] = m;
        }
        put(&l, "END MARK "); dec(&l, marks); flush(&l);
    }
    return 0;
}

__attribute__((constructor)) static void probe4_init(void)
{
    struct Line l; l.n = 0;
    const char* home = getenv_("HOME"); if (!home) home = "/tmp";
    char path[512]; int pn = 0;
    while (*home && pn < 450) path[pn++] = *home++;
    const char* tail = "/mpfever-probe4.log"; for (int i = 0; tail[i]; i++) path[pn++] = tail[i];
    path[pn] = 0;
    { int k = 0; const char* h = home; (void)h; const char* hh = getenv_("HOME"); if (!hh) hh = "/tmp"; while (*hh && k < 450) g_mark[k++] = *hh++; const char* m = "/mpf-mark"; for (int i = 0; m[i]; i++) g_mark[k++] = m[i]; g_mark[k] = 0; }
    g_fd = sys3(SYS_open, (i64)path, 0x0001 | 0x0200 | 0x0008, 0644);
    put(&l, "MPFever probe 4 loaded, pid "); dec(&l, (u64)sys3(SYS_getpid, 0, 0, 0)); flush(&l);
    u64 tls; __asm__ volatile("mrs %0, tpidrro_el0" : "=r"(tls)); main_tls = tls;

    long slide = 0; int found = 0;
    u32 n = _dyld_image_count();
    for (u32 i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        int L = len(nm); const char* want = "/TransportFever3"; int W = len(want);
        if (L >= W) { int k = 0; while (k < W && nm[L - W + k] == want[k]) k++; if (k == W) { slide = _dyld_get_image_vmaddr_slide(i); found = 1; break; } }
    }
    if (!found) { put(&l, "game image not found: nothing patched"); flush(&l); return; }
    g_slide = (u64)slide;
    put(&l, "game slide "); hex(&l, (u64)slide); flush(&l);

    int okn = 0, bad = 0;
    for (int i = 0; i < NHOOKS; i++) {
        volatile u32* fn = (volatile u32*)(HADDR[i] + (u64)slide);
        int same = 1; for (int k = 0; k < 4; k++) if (fn[k] != HWORDS[i][k]) same = 0;
        if (!same) { bad++; continue; }
        hook_resume[i] = HADDR[i] + (u64)slide + 16;
        u64 th = (u64)THUNK[i];
        u32 w[4] = { 0x58000050u, 0xd61f0200u, (u32)(th & 0xffffffffu), (u32)(th >> 32) };
        if (patch((u64)fn, w, 4) == 0) okn++; else bad++;
    }
    put(&l, "hooks installed "); dec(&l, (u64)okn); put(&l, ", failed "); dec(&l, (u64)bad); flush(&l);
    u64 tid; pthread_create(&tid, 0, heartbeat, 0);
}
