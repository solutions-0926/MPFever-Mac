# MPFever native for macOS: what is known (game build 26129055, Transport Fever 3 for Mac, arm64)

Status 2026-11-07: **injection, patching and hooking work on the real game** (probe 3 on macOS 26.3.1, Apple Silicon). The native
module itself (what `native/mpfever_native.cpp` does on Windows) is not ported yet.

## How the module gets into the game
- `TransportFever3` is a thin Mach-O arm64 executable, **ad hoc signed (linker-signed), no hardened runtime, no entitlements**.
  So `DYLD_INSERT_LIBRARIES` works when the game is started directly (the launcher must also set `SteamAppId=3493540` and
  `SteamGameId=3493540`, or the game stops with "User Profile Creation Failed").
- Steam's launch options do not work for this: macOS strips `DYLD_*` through `/usr/bin/env`, and Steam does not run the line
  through a shell ("OS Error 260").
- What works whatever starts the game (Steam included): a **stand-in for `libalut.0.dylib`** in the game folder (like
  `winhttp.dll` on Windows). `proxy-install.sh` keeps the original as `libalut.0.real.dylib` (its install name changed) and the
  stand-in re-exports it (`LC_REEXPORT_DYLIB`). `build-proxy.sh` builds it from the game's own library (needs it only to read its
  symbols). Everything is built **on Linux** with `clang --target=arm64-apple-macos13` and `ld.lld -flavor darwin`, freestanding.
- Patching code: `mach_vm_protect(..., READ|WRITE|COPY)`, write, `sys_icache_invalidate`, `mach_vm_protect(READ|EXEC)`: works.
- A hook = 16 bytes over the first four instructions of a function (`ldr x16,#8 ; br x16 ; .quad thunk`), the four instructions
  being position independent (`stp`, `sub sp`, `add x29`), the thunk runs them itself and jumps to function+16. `gen_hooks.py`
  generates the thunks from the game's file (so a thunk belongs to one build; the bytes at the place are compared first).

## Places found (file addresses, before the slide; the slide changes at each start)
| What | Address | Evidence |
|---|---|---|
| Lua string-hash seed (`lua_newstate`: `bl luaS_hash` before `str w0,[x19,#0x120]`) | 0x103f833fc | replaced by `movz w0,#0x4650`; patched in probe 2/3 without harm |
| Function applying the commands of the simulation thread ("Simulation Thread: Apply Command") | 0x100a6fa34 | called ~2x per `replicate`, x0 alternates between the two game states |
| `GameState::Replicate` (marker "Replicate") | 0x100113524 | x0/x1 swap between two game-state objects each call |
| Simulation thread entry (name "Simulation Thread") | 0x1000cbb50 | called once, at the map's load |
| `makeWorldBuildProposalCmd` (Lua binding) | 0x100f28020 | rises when the player builds |
| Function naming "WorldBuildProposal" (b) | 0x10170912c | rises when the player builds and at load |
| Function naming "WorldBuildProposal" (a) | 0x100a77b2c | several calls per second, role unknown |
| CommandList double buffer swap (`eor w9,w9,#1` on a flag at +0x18) | around 0x100a6a5b4 | CommandList.cpp assertions refer to it |
| CommandList entry stride 0x38 | 0x100a6e868.. | same stride as Windows (`add rbx,38h`) |

Structure matches Windows closely: the local-player word at +0x20C is read by **61 `ldr w,[x,#0x20c]` + 1 `ldrsw`** (59 sites on
Windows); command entries are 0x38 bytes; two game-state objects replicated each iteration. Not found the same way: the command
kind byte at +0x9b8 (0 plain `ldrb` hits: the layout or the addressing differs).

## To do (stages)
1. Command hold gate: find `CommandList::Add` (called by the UI tools right after make_cmd), hold the command, release it from
   the control file (`native_ctl.txt`: `enable 1`, `release <n>`; events in `native_events.log`: `deferred <id>`) exactly as the
   Windows module does, so the Lua mod (`mod/mpfever_1`, `mpfever_bridge.script.lua`) works unchanged.
2. Sources of randomness and pacing (srand/rand callers: 0x100013ecc, 0x103f7cc14; rand: 0x100a74d2c, 0x1012dad60, 0x103f7cad4),
   fresh entity ids (ecs engine add/remove), serial thread pool.
3. Company separation: the 61 readings of the local-player word.
4. A launcher for macOS (the Windows one is WinForms, .NET Framework): start the game with the module, copy the mod, relay actions.
5. Two games on one Mac for testing (the Windows tests run two games on one PC).
Cross-play with Windows players is not certain: arm64 and x86-64 builds may not compute bit-identically.
