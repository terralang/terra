#ifndef _WIN32
#include <execinfo.h>
#ifndef _XOPEN_SOURCE
#define _XOPEN_SOURCE
#endif
#include <ucontext.h>
#include "llvmheaders.h"
#include "tllvmutil.h"
#include "terrastate.h"
#include "tcompilerstate.h"

using namespace llvm;

static bool pointisbeforeinstruction(uintptr_t point, uintptr_t inst, bool isNextInst) {
    return point < inst || (!isNextInst && point == inst);
}
static bool stacktrace_findline(terra_CompilerState * C, const TerraFunctionInfo * fi, uintptr_t ip, bool isNextInstr, StringRef * file, size_t * lineno) {
    const std::vector<JITEvent_EmittedFunctionDetails::LineStart> & LineStarts = fi->efd.LineStarts;
    int i;
    for(i = 0; i + 1 < LineStarts.size() && pointisbeforeinstruction(LineStarts[i + 1].Address, ip, isNextInstr); i++) {
        //printf("\nscanning for %p, %s:%d %p\n",(void*)ip,DIFile(LineStarts[i].Loc.getScope(*C->ctx)).getFilename().data(),(int)LineStarts[i].Loc.getLine(),(void*)LineStarts[i].Address);
    }
    if(i < LineStarts.size()) {
        if(lineno)
            *lineno = LineStarts[i].Loc.getLine();
        if(file)
            *file = DIFile(LineStarts[i].Loc.getScope(*C->ctx)).getFilename();
        return true;
    } else {
        return false;
    }
}

static bool stacktrace_findsymbol(terra_CompilerState * C, uintptr_t ip, const TerraFunctionInfo ** rfi) {
    for(llvm::DenseMap<const void *, TerraFunctionInfo>::iterator it = C->functioninfo.begin(), end = C->functioninfo.end();
            it != end; ++it) {
        const TerraFunctionInfo & fi = it->second;
        uintptr_t fstart = (uintptr_t) fi.addr;
        uintptr_t fend = fstart + fi.size;
        if(fstart <= ip && ip < fend) {
            *rfi = &fi;
            return true;
        }
    }
    return false;
}

struct Frame {
    Frame * next;
    void * addr;
};
__attribute__((noinline))
static int terra_backtrace(void ** frames, int maxN, void * rip, void * rbp) {
    if(maxN > 0)
        frames[0] = rip;
    Frame * frame = (Frame*) rbp;
    int i;
    int fds[2];
    pipe(fds);
    //successful write to a pipe checks that we can read
    //Frame's memory. Otherwise we might segfault if rbp holds junk.
    for(i = 1; i < maxN && frame != NULL && write(fds[1],frame,sizeof(Frame)) != -1 && frame->addr != NULL; i++) {
        frames[i] = frame->addr;
        frame = frame->next;
    }
    close(fds[0]);
    close(fds[1]);
    return i - 1;
}

static void stacktrace_printsourceline(const char * filename, size_t lineno) {
    FILE * file = fopen(filename,"r");
    if(!file)
        return;
    int c = fgetc(file);
    for(int i = 1; i < lineno && c != EOF;) {
        if(c == '\n')
            i++;
        c = fgetc(file);
    }
    printf("    ");
    while(c != EOF && c != '\n') {
        fputc(c,stdout);
        c = fgetc(file);
    }
    fputc('\n',stdout);
    fclose(file);
}

static void printstacktrace(void * uap, void * data) {
    terra_CompilerState * C = (terra_CompilerState*) data;
    const int maxN = 128;
    void * frames[maxN];
    void * rip;
    void * rbp;
    if(uap == NULL) {
        rip = __builtin_return_address(0);
        rbp = __builtin_frame_address(1);
    } else {
        ucontext_t * uc = (ucontext_t*) uap;
#ifdef __linux__
        rip = (void*) uc->uc_mcontext.gregs[REG_RIP];
        rbp = (void*) uc->uc_mcontext.gregs[REG_RBP];
#else
        rip = (void*)uc->uc_mcontext->__ss.__rip;
        rbp = (void*)uc->uc_mcontext->__ss.__rbp;
#endif
    }
    int N = terra_backtrace(frames, maxN,rip,rbp);
    char ** symbols = backtrace_symbols(frames, N);
    for(int i = 0 ; i < N; i++) {
        const TerraFunctionInfo * fi;
        uintptr_t ip = (uintptr_t) frames[i];
        if(stacktrace_findsymbol(C,ip,&fi)) {
            std::string str = fi->fn->getName();
            uintptr_t fstart = (uintptr_t) fi->addr;
            printf("%-3d %-35s 0x%016" PRIxPTR " %s + %d ",i,"terra (JIT)",ip,str.c_str(),(int)(ip - fstart));
            StringRef filename;
            size_t lineno;
            bool isNextInst = i > 0 || uap == NULL; //unless this is the first entry in suspended context then the address is really a pointer to the _next_ instruction
            if(stacktrace_findline(C, fi, ip,isNextInst, &filename, &lineno)) {
                printf("(%s:%d)\n",filename.data(),(int)lineno);
                stacktrace_printsourceline(filename.data(), lineno);
            } else {
                printf("\n");
            }
        } else {
            printf("%s\n",symbols[i]);
        }
    }
    free(symbols);
}

static bool terra_lookupsymbol(void * ip, void ** fnaddr, size_t * fnsize, char * namebuf, size_t N, terra_CompilerState * C) {
    const Function * fn;
    const TerraFunctionInfo * fi;
    if(!stacktrace_findsymbol(C, (uintptr_t)ip, &fi))
        return false;
    
    if(fnaddr)
        *fnaddr = fi->addr;
    if(fnsize)
        *fnsize = fi->size;
    strlcpy(namebuf, fi->fn->getName().str().c_str(), N);
    return true;
}
static bool terra_lookupline(void * fnaddr, void * ip, char * fnamebuf, size_t N, size_t * linenum, terra_CompilerState * C) {
    if(C->functioninfo.count(fnaddr) == 0)
        return false;
    const TerraFunctionInfo & fi = C->functioninfo[fnaddr];
    StringRef sr;
    if(!stacktrace_findline(C, &fi, (uintptr_t)ip, false, &sr, linenum))
        return false;
    strlcpy(fnamebuf, sr.str().c_str(), N);
    return true;
}


static void * createclosure(JITMemoryManager * JMM, void * fn, int nargs, void ** env, int nenv) {
    assert(nargs <= 6);
    assert(*env);
    size_t fnsize = 2 + 10*(nenv + 1);
    uint8_t * buf = JMM->allocateSpace(fnsize, 16);
    uint8_t * code = buf;
#define ENCODE_MOV(reg,imm) do {  \
    *code++ = 0x48 | ((reg) >> 3);\
    *code++ = 0xb8 | ((reg) & 7); \
    void * data = (imm);          \
    memcpy(code,&data, 8);        \
    code += 8;                    \
} while(0);
    const uint8_t regnums[] = {7,6,2,1,8,9};
    ENCODE_MOV(0,fn); /* mov rax, fn */
    for(int i = nargs - nenv; i < nargs; i++)
        ENCODE_MOV(regnums[i],*env++);
    *code++ = 0xff; /* jmp rax */
    *code++ = 0xe0;
    return (void*) buf;
#undef ENCODE_MOV
}

void terra_debuginit(struct terra_State * T, JITMemoryManager * JMM) {
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    void * stacktracefn = createclosure(JMM,(void*)printstacktrace,2,(void**)&T->C,1);
    void * lookupsymbol = createclosure(JMM,(void*)terra_lookupsymbol,6,(void**)&T->C,1);
    void * lookupline =   createclosure(JMM,(void*)terra_lookupline,6,(void**)&T->C,1);
    lua_getfield(T->L, -1, "initdebugfns");
    lua_pushlightuserdata(T->L, (void*)stacktracefn);
    lua_pushlightuserdata(T->L, (void*)terra_backtrace);
    lua_pushlightuserdata(T->L, (void*)lookupsymbol);
    lua_pushlightuserdata(T->L, (void*)lookupline);
    lua_pushlightuserdata(T->L, (void*)llvmutil_disassemblefunction);
    lua_call(T->L, 5, 0);
    lua_pop(T->L,1); /* terra table */
}

#else /* it is WIN32 */
void terra_debuginit(struct terra_State * T, JITMemoryManager * JMM) {}
#endif