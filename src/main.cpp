/* See Copyright Notice in ../LICENSE.txt */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <io.h>
#include "ext/getopt.h"
#define isatty(x) _isatty(x)
#define NOMINMAX
#include <Windows.h>
#else
#include <signal.h>
#include <getopt.h>
#include <unistd.h>
#endif
#include "terra.h"

static void doerror(lua_State * L) {
    fprintf(stderr,"%s\n",luaL_checkstring(L,-1));
    lua_close(L);
    terra_llvmshutdown();
    exit(1);
}
const char * progname = NULL;
static void dotty (lua_State *L);
void parse_args(lua_State * L, int argc, char ** argv, terra_Options * options, bool * interactive, int * begin_script);
static int getargs (lua_State *L, char **argv, int n);
static int docall (lua_State *L, int narg, int clear);

static void (*terratraceback)(void*);

#ifndef _WIN32
void sigsegv(int sig, siginfo_t *info, void * uap) {
    signal(sig,SIG_DFL); //reset signal to default, just in case traceback itself crashes
    terratraceback(uap);  //call terra's pretty traceback
    raise(sig);   //rethrow the signal to the default handler
}
void registerhandler() {
	struct sigaction sa;
	sa.sa_flags = SA_RESETHAND | SA_SIGINFO;
	sigemptyset(&sa.sa_mask);
	sa.sa_sigaction = sigsegv;
	sigaction(SIGSEGV, &sa, NULL);
	sigaction(SIGILL, &sa, NULL);
}
#else
LONG WINAPI windowsexceptionhandler(EXCEPTION_POINTERS * ExceptionInfo) {
	terratraceback(ExceptionInfo->ContextRecord);
	return EXCEPTION_EXECUTE_HANDLER;
}
void registerhandler() {
	SetUnhandledExceptionFilter(windowsexceptionhandler);
}
#endif

void setupcrashsignal(lua_State * L) {
    lua_getglobal(L, "terralib");
    lua_getfield(L, -1, "traceback");
    const void * tb = lua_topointer(L,-1);
    if(!tb)
        return; //debug not supported
    terratraceback = *(void(* const *)(void*))tb;
	registerhandler();
    lua_pop(L,2);
}

static int luapanic (lua_State * L) { //so that we can set a debugger breakpoint and catch the error
    printf("PANIC: unprotected error in call to Lua API (%s)\n",lua_tostring(L,-1));
    exit(1);
}

int main(int argc, char ** argv) {
    progname = argv[0];
    lua_State * L = luaL_newstate();
    luaL_openlibs(L);
    lua_atpanic(L,luapanic);
    terra_Options options;
    memset(&options, 0, sizeof(terra_Options));
    
    bool interactive = false;
    int scriptidx;

    parse_args(L,argc,argv,&options,&interactive,&scriptidx);
    
    if(terra_initwithoptions(L, &options))
        doerror(L);
    
    setupcrashsignal(L);
    
    if(options.cmd_line_chunk != NULL) {
      if(terra_dostring(L,options.cmd_line_chunk))
        doerror(L);
      free(options.cmd_line_chunk);
    }

    if(scriptidx < argc) {
      int narg = getargs(L, argv, scriptidx);  
      lua_setglobal(L, "arg");
      const char * filename = argv[scriptidx];
      if(!strcmp(filename,"-"))
        filename = NULL;
      if(terra_loadfile(L,filename))
        doerror(L);
      lua_insert(L, -(narg + 1));
      if(docall(L,narg,0))
        doerror(L);
    }
    
    if(isatty(0) && (interactive || (scriptidx == argc && !options.cmd_line_chunk))) {
        progname = NULL;
        dotty(L);
    }
    
    lua_close(L);
    terra_llvmshutdown();
    
    return 0;
}

static void print_welcome();
void usage() {
    print_welcome();
    printf("terra [OPTIONS] [source-file] [arguments-to-source-file]\n"
           "    -v enable verbose debugging output\n"
           "    -g enable debugging symbols\n"
           "    -h print this help message\n"
           "    -i enter the REPL after processing source files\n"
           "    -m use LLVM's MCJIT\n"
           "    -e 'chunk' : execute command-line 'chunk' of code\n"
           "    -  Execute stdin instead of script and stop parsing options\n");
}

void parse_args(lua_State * L, int  argc, char ** argv, terra_Options * options, bool * interactive, int * begin_script) {
    int ch;
    static struct option longopts[] = {
        { "help",      0,     NULL,           'h' },
        { "verbose",   0,     NULL,           'v' },
        { "debugsymbols",   0,     NULL,           'g' },
        { "interactive",     0,     NULL,     'i' },
        { "mcjit", 0, NULL, 'm' },
        { "execute", required_argument, NULL, 'e' },
        { NULL,        0,     NULL,            0 }
    };
    /*  Parse commandline options  */
    opterr = 0;
    while ((ch = getopt_long(argc, argv, "+hvgime:p:", longopts, NULL)) != -1) {
        switch (ch) {
            case 'v':
                options->verbose++;
                break;
            case 'i':
                *interactive = true;
                break;
            case 'g':
                options->debug++;
                break;
            case 'm':
                options->usemcjit = 1;
                break;
            case 'e':
                options->cmd_line_chunk = (char*)malloc(strlen(optarg) + 1);
                strcpy(options->cmd_line_chunk, optarg);
                break;
            case ':':
            case 'h':
            default:
                usage();
                exit(-1);
                break;
        }
    }
    *begin_script = optind;
}
//this stuff is from lua's lua.c repl implementation:

#ifndef _WIN32
#include "linenoise.h"
#define lua_readline(L,b,p)    ((void)L, ((b)=linenoise(p)) != NULL)
#define lua_saveline(L,idx) \
    if (lua_strlen(L,idx) > 0)  /* non-empty line? */ \
      linenoiseHistoryAdd(lua_tostring(L, idx));  /* add it to history */
#define lua_freeline(L,b)    ((void)L, free(b))
#else
#define lua_readline(L,b,p)     \
        ((void)L, fputs(p, stdout), fflush(stdout),  /* show prompt */ \
        fgets(b, LUA_MAXINPUT, stdin) != NULL)  /* get line */
#define lua_saveline(L,idx)     { (void)L; (void)idx; }
#define lua_freeline(L,b)       { (void)L; (void)b; }
#endif

static void l_message (const char *pname, const char *msg) {
  if (pname) fprintf(stderr, "%s: ", pname);
  fprintf(stderr, "%s\n", msg);
  fflush(stderr);
}

static int report (lua_State *L, int status) {
  if (status && !lua_isnil(L, -1)) {
    const char *msg = lua_tostring(L, -1);
    if (msg == NULL) msg = "(error object is not a string)";
    l_message(progname, msg);
    lua_pop(L, 1);
  }
  return status;
}

static int incomplete (lua_State *L, int status) {
  if (status == LUA_ERRSYNTAX) {
    size_t lmsg;
    const char *msg = lua_tolstring(L, -1, &lmsg);
    const char *tp = msg + lmsg - (sizeof("'<eof>'") - 1);
    if (strstr(msg, "'<eof>'") == tp) {
      lua_pop(L, 1);
      return 1;
    }
  }
  return 0;  /* else... */
}

static int getargs (lua_State *L, char **argv, int n) {
  int narg;
  int i;
  int argc = 0;
  while (argv[argc]) argc++;  /* count total number of arguments */
  narg = argc - (n + 1);  /* number of arguments to the script */
  luaL_checkstack(L, narg + 3, "too many arguments to script");
  for (i=n+1; i < argc; i++)
    lua_pushstring(L, argv[i]);
  lua_createtable(L, narg, n + 1);
  for (i=0; i < argc; i++) {
    lua_pushstring(L, argv[i]);
    lua_rawseti(L, -2, i - n);
  }
  return narg;
}

#define LUA_MAXINPUT 512
#define LUA_PROMPT "> " 
#define LUA_PROMPT2 ">> "

static const char *get_prompt (lua_State *L, int firstline) {
  const char *p;
  lua_getfield(L, LUA_GLOBALSINDEX, firstline ? "_PROMPT" : "_PROMPT2");
  p = lua_tostring(L, -1);
  if (p == NULL) p = (firstline ? LUA_PROMPT : LUA_PROMPT2);
  lua_pop(L, 1);  /* remove global */
  return p;
}

static int pushline (lua_State *L, int firstline) {
  char buffer[LUA_MAXINPUT];
  char *b = buffer;
  size_t l;
  const char *prmt = get_prompt(L, firstline);
  if (lua_readline(L, b, prmt) == 0)
    return 0;  /* no input */
  l = strlen(b);
  if (l > 0 && b[l-1] == '\n')  /* line ends with newline? */
    b[l-1] = '\0';  /* remove it */
  if (firstline && b[0] == '=')  /* first line starts with `=' ? */
    lua_pushfstring(L, "return %s", b+1);  /* change it to `return' */
  else
    lua_pushstring(L, b);
  lua_saveline(L, -1);
  lua_freeline(L, b);
  return 1;
}

static int loadline (lua_State *L) {
  int status;
  lua_settop(L, 0);
  if (!pushline(L, 1))
    return -1;  /* no input */
  for (;;) {  /* repeat until gets a complete line */
    status = terra_loadbuffer(L, lua_tostring(L, 1), lua_strlen(L, 1), "stdin");
    if (!incomplete(L, status)) break;  /* cannot try to add lines? */
    if (!pushline(L, 0))  /* no more input? */
      return -1;
    lua_pushliteral(L, "\n");  /* add a new line... */
    lua_insert(L, -2);  /* ...between the two lines */
    lua_concat(L, 3);  /* join them */
  }
  lua_remove(L, 1);  /* remove line */
  return status;
}

static int traceback (lua_State *L) {
  if (!lua_isstring(L, 1))  /* 'message' not a string? */
    return 1;  /* keep it intact */
  lua_getfield(L, LUA_GLOBALSINDEX, "debug");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 1;
  }
  lua_getfield(L, -1, "traceback");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 2);
    return 1;
  }
  lua_pushvalue(L, 1);  /* pass error message */
  lua_pushinteger(L, 2);  /* skip this function and traceback */
  lua_call(L, 2, 1);  /* call debug.traceback */
  return 1;
}

static lua_State *globalL = NULL;

static void lstop (lua_State *L, lua_Debug *ar) {
  (void)ar;  /* unused arg. */
  lua_sethook(L, NULL, 0, 0);
  luaL_error(L, "interrupted!");
}

static void laction (int i) {
  signal(i, SIG_DFL); /* if another SIGINT happens before lstop,
                              terminate process (default action) */
  lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}


static int docall (lua_State *L, int narg, int clear) {
  int status;
  globalL = L;
  int base = lua_gettop(L) - narg;  /* function index */
  lua_pushcfunction(L, traceback);  /* push traceback function */
  lua_insert(L, base);  /* put it under chunk and args */
  signal(SIGINT, laction);
  status = lua_pcall(L, narg, (clear ? 0 : LUA_MULTRET), base);
  signal(SIGINT, SIG_DFL);
  lua_remove(L, base);  /* remove traceback function */
  /* force a complete garbage collection in case of errors */
  if (status != 0) lua_gc(L, LUA_GCCOLLECT, 0);
  return status;
}
static void print_welcome() {
    printf("\n"
           "Terra -- A low-level counterpart to Lua\n"
           "Release " TERRA_VERSION_STRING "\n"
           "\n"
           "Stanford University\n"
           "zdevito@stanford.edu\n"
           "\n");
}
static void dotty (lua_State *L) {
  int status;
  print_welcome();
  while ((status = loadline(L)) != -1) {
    if (status == 0) status = docall(L, 0, 0);
    report(L,status);
    if (status == 0 && lua_gettop(L) > 0) {  /* any result to print? */
      lua_getglobal(L, "print");
      lua_insert(L, 1);
      if (lua_pcall(L, lua_gettop(L)-1, 0, 0) != 0)
        lua_pushfstring(L,
                        "error calling " LUA_QL("print") " (%s)",
                        lua_tostring(L, -1));
        report(L,status);
    }
  }
  lua_settop(L, 0);  /* clear stack */
  fputs("\n", stdout);
  fflush(stdout);
}

#if 0
//a much simpler main function:
#include <stdio.h>
#include "terra.h"

static void doerror(lua_State * L) {
    printf("%s\n",luaL_checkstring(L,-1));
    exit(1);
}
int main(int argc, char ** argv) {
    lua_State * L = luaL_newstate();
    luaL_openlibs(L);
    if(terra_init(L))
        doerror(L);
    for(int i = 1; i < argc; i++)
        if(terra_dofile(L,argv[i]))
            doerror(L);
    return 0;
}
#endif
