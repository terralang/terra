#include "llvmheaders.h"
#include "tllvmutil.h"
#include "terrastate.h"
#include "tcompilerstate.h"

#if !defined(__arm__) && !defined(__aarch64__)

#ifndef _WIN32
#include <execinfo.h>
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif
#include <ucontext.h>
#include <unistd.h>
#else
#define NOMINMAX
#include <Windows.h>
#include <imagehlp.h>
#include <intrin.h>
#endif

using namespace llvm;

#ifdef DEBUG_INFO_WORKING
static bool pointisbeforeinstruction(uintptr_t point, uintptr_t inst, bool isNextInst) {
    return point < inst || (!isNextInst && point == inst);
}
#endif
static bool stacktrace_findline(terra_CompilerState *C, const TerraFunctionInfo *fi,
                                uintptr_t ip, bool isNextInstr, StringRef *file,
                                size_t *lineno) {
#ifdef DEBUG_INFO_WORKING
    const std::vector<JITEvent_EmittedFunctionDetails::LineStart> &LineStarts =
            fi->efd.LineStarts;
    size_t i;
    for (i = 0; i + 1 < LineStarts.size() &&
                pointisbeforeinstruction(LineStarts[i + 1].Address, ip, isNextInstr);
         i++) {
        // printf("\nscanning for %p, %s:%d
        // %p\n",(void*)ip,DIFile(LineStarts[i].Loc.getScope(*C->ctx)).getFilename().data(),(int)LineStarts[i].Loc.getLine(),(void*)LineStarts[i].Address);
    }

    if (i < LineStarts.size()) {
        if (lineno) *lineno = LineStarts[i].Loc.getLine();
        if (file) *file = DIFile(LineStarts[i].Loc.getScope(*fi->ctx)).getFilename();
        return true;
    } else {
        return false;
    }
#else
    return false;
#endif
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
static int
terra_backtrace(void **frames, int maxN, void *rip, void *rbp) {
    if (maxN > 0) frames[0] = rip;
    Frame *frame = (Frame *)rbp;
    if (!frame) return 1;
    int i;
#ifndef _WIN32
    int fds[2];
    pipe(fds);
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
        if (stacktrace_findline(C, fi, ip, isNextInst, &filename, &lineno)) {
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
    void *rip;
    void *rbp;

#ifndef _WIN32
    if (uap == NULL) {
        rip = __builtin_return_address(0);
        rbp = __builtin_frame_address(1);
    } else {
        ucontext_t *uc = (ucontext_t *)uap;
#ifdef __linux__
        rip = (void *)uc->uc_mcontext.gregs[REG_RIP];
        rbp = (void *)uc->uc_mcontext.gregs[REG_RBP];
#else
#ifdef __FreeBSD__
        rip = (void *)uc->uc_mcontext.mc_rip;
        rbp = (void *)uc->uc_mcontext.mc_rbp;
#else
        rip = (void *)uc->uc_mcontext->__ss.__rip;
        rbp = (void *)uc->uc_mcontext->__ss.__rbp;
#endif
#endif
    }
#else
    if (uap == NULL) {
        CONTEXT cur_context;
        RtlCaptureContext(&cur_context);
        rbp = (void *)cur_context.Rbp;
        rip = _ReturnAddress();
    } else {
        CONTEXT *context = (CONTEXT *)uap;
        rip = (void *)context->Rip;
        rbp = (void *)context->Rbp;
    }
#endif
    int N = terra_backtrace(frames, maxN, rip, rbp);

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
        if (!printfunctioninfo(C, ip, isNextInst, i)) {
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
    if (!stacktrace_findline(C, &fi, (uintptr_t)ip, false, &sr, &r->linenum))
        return false;
    r->name = sr.data();
    r->namelength = sr.size();
    return true;
}

#define CLOSURE_MAX_SIZE 64

static void *createclosure(uint8_t *buf, void *fn, int nargs, void **env, int nenv) {
    assert(nargs <= 4);
    assert(*env);
    uint8_t *code = buf;
#define ENCODE_MOV(reg, imm)           \
    do {                               \
        *code++ = 0x48 | ((reg) >> 3); \
        *code++ = 0xb8 | ((reg)&7);    \
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
    return (void *)buf;
#undef ENCODE_MOV
}

int terra_debuginit(struct terra_State *T) {
    std::error_code ec;
    T->C->MB = llvm::sys::Memory::allocateMappedMemory(
            CLOSURE_MAX_SIZE * 3, NULL,
            llvm::sys::Memory::MF_READ | llvm::sys::Memory::MF_WRITE |
                    llvm::sys::Memory::MF_EXEC,
            ec);

    void *stacktracefn = createclosure((uint8_t *)T->C->MB.base(),
                                       (void *)printstacktrace, 2, (void **)&T->C, 1);
    void *lookupsymbol = createclosure((uint8_t *)T->C->MB.base() + CLOSURE_MAX_SIZE,
                                       (void *)terra_lookupsymbol, 3, (void **)&T->C, 1);
    void *lookupline = createclosure((uint8_t *)T->C->MB.base() + 2 * CLOSURE_MAX_SIZE,
                                     (void *)terra_lookupline, 4, (void **)&T->C, 1);

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

#else /* it arm code just don't include debug interface for now */

int terra_debuginit(struct terra_State* T) { return 0; }

#endif
