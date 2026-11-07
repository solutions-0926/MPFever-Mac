
static int patch(u64 addr, const u32* words, int count)
{
    u64 page = addr & ~0x3FFFUL;
    int r = mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 2 | 0x10);   // read | write | copy
    if (r) return r;
    for (int i = 0; i < count; i++) ((volatile u32*)addr)[i] = words[i];
    sys_icache_invalidate((void*)addr, (u64)count * 4);
    return mach_vm_protect(mach_task_self_, page, 0x4000, 0, 1 | 4);          // read | execute
}

static void* heartbeat(void* unused)
{
    (void)unused;
    u32 last[NHOOKS]; for (int i = 0; i < NHOOKS; i++) last[i] = 0;
    for (u32 tick = 1; tick < 4000; tick++) {
        usleep(500000);
        int changed = 0; for (int i = 0; i < NHOOKS; i++) if (hook_calls[i] != last[i]) changed = 1;
        if (!changed && tick % 20) continue;
        struct Line l; l.n = 0;
        put(&l, "t+"); dec(&l, tick / 2); put(&l, "s");
        for (int i = 0; i < NHOOKS; i++) {
            last[i] = hook_calls[i];
            put(&l, "  "); put(&l, HNAME[i]); put(&l, "="); dec(&l, last[i]);
            if (last[i]) { put(&l, "("); hex(&l, hook_arg[i][0]); put(&l, ","); hex(&l, hook_arg[i][1]); put(&l, ")"); }
        }
        flush(&l);
    }
    return 0;
}

__attribute__((constructor)) static void probe3_init(void)
{
    struct Line l; l.n = 0;
    const char* home = getenv_("HOME"); if (!home) home = "/tmp";
    char path[512]; int pn = 0;
    while (*home && pn < 450) path[pn++] = *home++;
    const char* tail = "/mpfever-probe3.log"; for (int i = 0; tail[i]; i++) path[pn++] = tail[i];
    path[pn] = 0;
    g_fd = sys3(SYS_open, (i64)path, 0x0001 | 0x0200 | 0x0008, 0644);
    put(&l, "MPFever probe 3 loaded, pid "); dec(&l, (u64)sys3(SYS_getpid, 0, 0, 0)); flush(&l);

    long slide = 0; int found = 0;
    u32 n = _dyld_image_count();
    for (u32 i = 0; i < n; i++) {
        const char* nm = _dyld_get_image_name(i);
        int L = len(nm); const char* want = "/TransportFever3"; int W = len(want);
        if (L >= W) { int k = 0; while (k < W && nm[L - W + k] == want[k]) k++; if (k == W) { slide = _dyld_get_image_vmaddr_slide(i); found = 1; break; } }
    }
    if (!found) { put(&l, "game image not found: nothing patched"); flush(&l); return; }
    put(&l, "game slide "); hex(&l, (u64)slide); flush(&l);

    volatile u32* seed = (volatile u32*)(SEED_ADDR + (u64)slide);
    if (seed[-1] == SEED_PRE && seed[0] == SEED_BL && seed[1] == SEED_POST) {
        u32 w = 0x5288ca00u;   // movz w0,#0x4650
        int r = patch((u64)seed, &w, 1);
        put(&l, "seed patch: result "); dec(&l, (u64)(unsigned)r); flush(&l);
    } else { put(&l, "seed place does not match"); flush(&l); }

    for (int i = 0; i < NHOOKS; i++) {
        volatile u32* fn = (volatile u32*)(HADDR[i] + (u64)slide);
        int same = 1; for (int k = 0; k < 4; k++) if (fn[k] != HWORDS[i][k]) same = 0;
        put(&l, "hook "); put(&l, HNAME[i]); put(&l, ": ");
        if (!same) { put(&l, "place does not match this build"); flush(&l); continue; }
        hook_resume[i] = HADDR[i] + (u64)slide + 16;
        u64 th = (u64)THUNK[i];
        u32 w[4] = { 0x58000050u, 0xd61f0200u, (u32)(th & 0xffffffffu), (u32)(th >> 32) };
        int r = patch((u64)fn, w, 4);
        put(&l, "result "); dec(&l, (u64)(unsigned)r); flush(&l);
    }
    u64 tid; pthread_create(&tid, 0, heartbeat, 0);
}
