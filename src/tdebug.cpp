#include "llvmheaders.h"
#include "tllvmutil.h"
#include "terrastate.h"
#include "tcompilerstate.h"

#if !defined(__arm__) && !defined(__PPC__)

#ifndef _WIN32
#include <execinfo.h>
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif
#include <ucontext.h>
#include <unistd.h>
#else
#include "twindows.h"
#include <imagehlp.h>
#endif

using namespace llvm;

// Runs from a signal handler, so it must not allocate.
static bool stacktrace_findline(const TerraFunctionInfo *fi, uintptr_t ip,
                                bool isNextInstr, StringRef *file, size_t *lineno) {
    if (!fi->debug) return false;
    const std::vector<TerraLineInfo> &lines = fi->debug->lines;
    // A return address points at the instruction after the call, which can
    // already belong to the next statement. Look up the call itself.
    uint64_t addr = isNextInstr ? ip - 1 : ip;
    size_t lo = 0, hi = lines.size();
    while (lo < hi) {  // the last row at or before addr
        size_t mid = lo + (hi - lo) / 2;
        if (lines[mid].addr <= addr)
            lo = mid + 1;
        else
            hi = mid;
    }
    if (lo == 0) return false;
    const TerraLineInfo &li = lines[lo - 1];
    if (li.line == 0) return false;
    if (lineno) *lineno = li.line;
    if (file) *file = fi->debug->filenames[li.fileid];
    return true;
}

static bool stacktrace_findsymbol(terra_CompilerState *C, uintptr_t ip,
                                  const TerraFunctionInfo **rfi) {
    for (llvm::DenseMap<const void *, TerraFunctionInfo>::iterator
                 it = C->functioninfo.begin(),
                 end = C->functioninfo.end();
         it != end; ++it) {
        const TerraFunctionInfo &fi = it->second;
        uintptr_t fstart = (uintptr_t)fi.addr;
        uintptr_t fend = fstart + fi.size;
        if (fstart <= ip && ip < fend) {
            *rfi = &fi;
            return true;
        }
    }
    return false;
}

struct Frame {
    Frame *next;
    void *addr;
};
#ifndef _WIN32
__attribute__((noinline))
#else
__declspec(noinline)
#endif
static int terra_backtrace(void **frames, int maxN, void *rip, void *rbp) {
    if (maxN > 0) frames[0] = rip;
    Frame *frame = (Frame *)rbp;
    if (!frame) return 1;
    int i;
#ifndef _WIN32
    int fds[2];
    if (pipe(fds) != 0) return 1;
#endif
    // successful write to a pipe checks that we can read
    // Frame's memory. Otherwise we might segfault if rbp holds junk.
    for (i = 1; i < maxN &&
#ifndef _WIN32
                write(fds[1], frame, sizeof(Frame)) != -1 &&
#else
                !IsBadReadPtr(frame, sizeof(Frame)) &&
#endif
                frame->addr && frame->next;
         i++) {
        frames[i] = frame->addr;
        frame = frame->next;
    }
#ifndef _WIN32
    close(fds[0]);
    close(fds[1]);
#endif
    return i;
}

#ifdef _WIN32
// Win64 keeps no frame pointer chain: rbp is an ordinary register there and
// native code is unwound from the RUNTIME_FUNCTION tables in .pdata. JIT'd code
// has no such tables, because the JIT emits an ELF container and ELF carries
// none, but under -g every Terra function keeps rbp, so a Terra frame can be
// stepped by hand instead. Walking both in one loop is what lets the stack
// cross between them in either direction: the hand written step also rebuilds
// the rsp and rbp that the table driven one needs to carry on above a Terra
// frame, and the table driven one restores whatever rbp the Terra frame below
// it was using.

// One table driven step, for a frame that is not Terra's. Returns false when
// there is nothing above that can be accounted for.
static bool unwindnative(CONTEXT *ctx, bool innermost) {
    DWORD64 imagebase;
    PRUNTIME_FUNCTION rf = RtlLookupFunctionEntry(ctx->Rip, &imagebase, NULL);
    if (!rf) {
        // No entry at all is how the ABI spells a leaf function: it saved
        // nothing, so the return address is still on top of the stack. Only the
        // innermost frame can be a leaf though. Anywhere else this is code the
        // walk cannot account for, another JIT's say, and reading the stack as
        // if it were a leaf would print noise.
        if (!innermost || IsBadReadPtr((void *)ctx->Rsp, sizeof(void *))) return false;
        ctx->Rip = *(DWORD64 *)ctx->Rsp;
        ctx->Rsp += sizeof(void *);
        return true;
    }
    PVOID handlerdata;
    DWORD64 establisher;
    RtlVirtualUnwind(UNW_FLAG_NHANDLER, imagebase, ctx->Rip, rf, ctx, &handlerdata,
                     &establisher, NULL);
    return true;
}

// Runs from an exception handler, so it must not allocate. The context is
// consumed.
static int terra_backtrace_context(terra_CompilerState *C, void **frames, int maxN,
                                   CONTEXT *ctx) {
    int i = 0;
    while (i < maxN && ctx->Rip) {
        bool innermost = i == 0;
        frames[i++] = (void *)ctx->Rip;
        DWORD64 rsp = ctx->Rsp;
        const TerraFunctionInfo *fi;
        if (stacktrace_findsymbol(C, (uintptr_t)ctx->Rip, &fi)) {
            // Without -g there is no frame record to read, and rbp holds
            // whatever the register allocator put there, so stop rather than
            // follow it. printstacktrace says so afterwards.
            if (!C->debug) break;
            // The prologue is push rbp; mov rbp, rsp, so the frame record is
            // the two words at rbp and the caller resumes just above them.
            Frame *frame = (Frame *)ctx->Rbp;
            if (!frame || IsBadReadPtr(frame, sizeof(Frame)) || !frame->addr) break;
            ctx->Rip = (DWORD64)frame->addr;
            ctx->Rsp = (DWORD64)(frame + 1);
            ctx->Rbp = (DWORD64)frame->next;
        } else if (!unwindnative(ctx, innermost)) {
            break;
        }
        if (ctx->Rsp <= rsp) break;  // a step has to shrink the stack, or it is junk
    }
    return i;
}
#endif

static void stacktrace_printsourceline(const char *filename, size_t lineno) {
    FILE *file = fopen(filename, "r");
    if (!file) return;
    int c = fgetc(file);
    for (size_t i = 1; i < lineno && c != EOF;) {
        if (c == '\n') i++;
        c = fgetc(file);
    }
    printf("    ");
    while (c != EOF && c != '\n') {
        fputc(c, stdout);
        c = fgetc(file);
    }
    fputc('\n', stdout);
    fclose(file);
}

static bool printfunctioninfo(terra_CompilerState *C, uintptr_t ip, bool isNextInst,
                              int i) {
    const TerraFunctionInfo *fi;
    if (stacktrace_findsymbol(C, ip, &fi)) {
        uintptr_t fstart = (uintptr_t)fi->addr;
        printf("%-3d %-35s 0x%016" PRIxPTR " %s + %d ", i, "terra (JIT)", ip,
               fi->name.c_str(), (int)(ip - fstart));
        StringRef filename;
        size_t lineno;
        if (stacktrace_findline(fi, ip, isNextInst, &filename, &lineno)) {
            printf("(%s:%d)\n", filename.data(), (int)lineno);
            stacktrace_printsourceline(filename.data(), lineno);
        } else {
            printf("\n");
        }
        return true;
    }
    return false;
}

static void printstacktrace(void *uap, void *data) {
    terra_CompilerState *C = (terra_CompilerState *)data;
    const int maxN = 128;
    void *frames[maxN];
    bool anyterra = false;

#ifndef _WIN32
    void *rip, *rbp;
    if (uap == NULL) {
        rip = __builtin_return_address(0);
        rbp = __builtin_frame_address(1);
    } else {
        ucontext_t *uc = (ucontext_t *)uap;
#ifdef __linux__
#if defined(__aarch64__)
        rip = (void *)uc->uc_mcontext.pc;
        rbp = (void *)uc->uc_mcontext.regs[29];
#else
        rip = (void *)uc->uc_mcontext.gregs[REG_RIP];
        rbp = (void *)uc->uc_mcontext.gregs[REG_RBP];
#endif
#else
#ifdef __FreeBSD__
#if defined(__aarch64__)
        rip = (void *)uc->uc_mcontext.mc_gpregs.gp_elr;
        rbp = (void *)uc->uc_mcontext.mc_gpregs.gp_x[29];
#else
        rip = (void *)uc->uc_mcontext.mc_rip;
        rbp = (void *)uc->uc_mcontext.mc_rbp;
#endif
#else
#if defined(__aarch64__)
        rip = (void *)uc->uc_mcontext->__ss.__pc;
        rbp = (void *)uc->uc_mcontext->__ss.__fp;
#else
        rip = (void *)uc->uc_mcontext->__ss.__rip;
        rbp = (void *)uc->uc_mcontext->__ss.__rbp;
#endif
#endif
#endif
    }
    int N = terra_backtrace(frames, maxN, rip, rbp);
#else
    CONTEXT context;
    if (uap == NULL) {
        RtlCaptureContext(&context);
        // Step out of this function first, so that the walk starts in the frame
        // that asked for the traceback, as it does on POSIX.
        if (!unwindnative(&context, true)) return;
    } else {
        context = *(CONTEXT *)uap;
    }
    int N = terra_backtrace_context(C, frames, maxN, &context);
#endif

#ifndef _WIN32
    char **symbols = backtrace_symbols(frames, N);
#else
    HANDLE process = GetCurrentProcess();
    SymInitialize(process, NULL, true);
#endif

    for (int i = 0; i < N; i++) {
        bool isNextInst =
                i > 0 ||
                uap == NULL;  // unless this is the first entry in suspended context then
                              // the address is really a pointer to the _next_ instruction
        uintptr_t ip = (uintptr_t)frames[i];
        if (printfunctioninfo(C, ip, isNextInst, i)) {
            anyterra = true;
        } else {
#ifndef _WIN32
            printf("%s\n", symbols[i]);
#else
            char buf[256 + sizeof(SYMBOL_INFO)];
            SYMBOL_INFO *symbol = (SYMBOL_INFO *)buf;
            symbol->MaxNameLen = 255;
            symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
            if (SymFromAddr(process, ip, 0, symbol))
                printf("%-3d %-35s 0x%016" PRIxPTR " %s + %d\n", i, "C", ip, symbol->Name,
                       (int)(ip - (uintptr_t)symbol->Address));
            else
                printf("%-3d %-35s 0x%016" PRIxPTR "\n", i, "unknown", ip);
#endif
        }
    }
#ifndef _WIN32
    free(symbols);
#endif
    // Without -g the JIT keeps no frame pointer, so the walk leaves the
    // innermost Terra function and lands in whatever called into Terra. Whether
    // it stepped over any Terra frames on the way is not knowable from here: a
    // single frame is also what a complete stack looks like.
    if (anyterra && !C->debug)
        printf("some Terra frames may be missing; run with -g to see the full stack\n");
}

struct SymbolInfo {
    const void *addr;
    size_t size;
    const char *name;
    size_t namelength;
};

static bool terra_lookupsymbol(void *ip, SymbolInfo *r, terra_CompilerState *C) {
    const TerraFunctionInfo *fi;
    if (!stacktrace_findsymbol(C, (uintptr_t)ip, &fi)) return false;
    r->addr = fi->addr;
    r->size = fi->size;
    r->name = fi->name.c_str();
    r->namelength = fi->name.length();
    return true;
}

struct LineInfo {
    const char *name;
    size_t namelength;
    size_t linenum;
};
static bool terra_lookupline(void *fnaddr, void *ip, LineInfo *r,
                             terra_CompilerState *C) {
    if (C->functioninfo.count(fnaddr) == 0) return false;
    const TerraFunctionInfo &fi = C->functioninfo[fnaddr];
    StringRef sr;
    if (!stacktrace_findline(&fi, (uintptr_t)ip, false, &sr, &r->linenum)) return false;
    r->name = sr.data();
    r->namelength = sr.size();
    return true;
}

/* AArch64 needs 20 bytes plus 16 per captured argument, of which there are 4 */
#define CLOSURE_MAX_SIZE 96

static void *createclosure(uint8_t *buf, void *fn, int nargs, void **env, int nenv) {
    assert(nargs <= 4);
    assert(*env);
    uint8_t *code = buf;
#if defined(__aarch64__)
    // A 64 bit immediate takes a movz and three movk on a fixed width encoding.
#define ENCODE_MOV(reg, imm)                                                     \
    do {                                                                         \
        uint64_t data = (uint64_t)(imm);                                         \
        for (int shift = 0; shift < 64; shift += 16) {                           \
            uint32_t inst = ((shift == 0) ? 0xd2800000 : 0xf2800000) |           \
                            ((uint32_t)(shift / 16) << 21) |                     \
                            ((uint32_t)((data >> shift) & 0xffff) << 5) | (reg); \
            memcpy(code, &inst, 4);                                              \
            code += 4;                                                           \
        }                                                                        \
    } while (0);
    const uint8_t regnums[] = {0, 1, 2, 3};
    ENCODE_MOV(16, fn); /* x16 is the scratch register reserved for veneers */
    for (int i = nargs - nenv; i < nargs; i++) ENCODE_MOV(regnums[i], *env++);
    uint32_t branch = 0xd61f0000 | (16 << 5); /* br x16 */
    memcpy(code, &branch, 4);
    code += 4;
#else
#define ENCODE_MOV(reg, imm)           \
    do {                               \
        *code++ = 0x48 | ((reg) >> 3); \
        *code++ = 0xb8 | ((reg) & 7);  \
        void *data = (imm);            \
        memcpy(code, &data, 8);        \
        code += 8;                     \
    } while (0);
#ifndef _WIN32
    const uint8_t regnums[] = {7, 6, 2, 1 /*,8,9*/};
#else
    const uint8_t regnums[] = {1, 2, 8, 9};
#endif
    ENCODE_MOV(0, fn); /* mov rax, fn */
    for (int i = nargs - nenv; i < nargs; i++) ENCODE_MOV(regnums[i], *env++);
    *code++ = 0xff; /* jmp rax */
    *code++ = 0xe0;
#endif
    assert(code - buf <= CLOSURE_MAX_SIZE);
    return (void *)buf;
#undef ENCODE_MOV
}

int terra_debuginit(struct terra_State *T) {
    std::error_code ec;
    T->C->MB = llvm::sys::Memory::allocateMappedMemory(
            CLOSURE_MAX_SIZE * 3, NULL,
            llvm::sys::Memory::MF_READ | llvm::sys::Memory::MF_WRITE, ec);
    if (ec || !T->C->MB.base()) return 0; /* no closures, so no debug interface */

    void *stacktracefn = createclosure((uint8_t *)T->C->MB.base(),
                                       (void *)printstacktrace, 2, (void **)&T->C, 1);
    void *lookupsymbol = createclosure((uint8_t *)T->C->MB.base() + CLOSURE_MAX_SIZE,
                                       (void *)terra_lookupsymbol, 3, (void **)&T->C, 1);
    void *lookupline = createclosure((uint8_t *)T->C->MB.base() + 2 * CLOSURE_MAX_SIZE,
                                     (void *)terra_lookupline, 4, (void **)&T->C, 1);

    // Also flushes the instruction cache.
    ec = llvm::sys::Memory::protectMappedMemory(
            T->C->MB, llvm::sys::Memory::MF_READ | llvm::sys::Memory::MF_EXEC);
    if (ec) return 0;

    lua_getfield(T->L, LUA_GLOBALSINDEX, "terra");
    lua_getfield(T->L, -1, "initdebugfns");
    lua_pushlightuserdata(T->L, (void *)stacktracefn);
    lua_pushlightuserdata(T->L, (void *)terra_backtrace);
    lua_pushlightuserdata(T->L, (void *)lookupsymbol);
    lua_pushlightuserdata(T->L, (void *)lookupline);
    lua_pushlightuserdata(T->L, (void *)llvmutil_disassemblefunction);
    lua_call(T->L, 5, 0);
    lua_pop(T->L, 1); /* terra table */
    return 0;
}

#else /* no closure encoding for 32 bit ARM or PowerPC yet */

int terra_debuginit(struct terra_State *T) { return 0; }

#endif
