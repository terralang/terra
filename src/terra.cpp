/* See Copyright Notice in ../LICENSE.txt */

#include "terra.h"
#include "terrastate.h"
#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include "tcompiler.h"
#include "tkind.h"
#include "tcwrapper.h"
#include "tcuda.h"

#include <stdio.h>
#include <stdarg.h>
#include <assert.h>
#ifndef _WIN32
#include <sys/mman.h>
#endif


static char * vstringf(const char * fmt, va_list ap) {
    int N = 128;
    char * buf = (char*) malloc(N);
    while(1) {
        int n = vsnprintf(buf, N, fmt, ap);
        if(n > -1 && n < N) {
            return buf;
        }
        if(n > -1)
            N = n + 1;
        else
            N *= 2;
        free(buf);
        buf = (char*) malloc(N);
    }
}

void terra_vpusherror(terra_State * T, const char * fmt, va_list ap) {
    char * buf = vstringf(fmt,ap);
    lua_pushstring(T->L, buf);
    free(buf);
}

void terra_pusherror(terra_State * T, const char * fmt, ...) {
    va_list ap;
    va_start(ap,fmt);
    terra_vpusherror(T,fmt,ap);
    va_end(ap);
}

void terra_reporterror(terra_State * T, const char * fmt, ...) {
    va_list ap;
    va_start(ap,fmt);
    terra_vpusherror(T,fmt,ap);
    va_end(ap);
    lua_error(T->L);
}

struct SourceInfo {
    FILE * file;
    size_t len;
    char * mapped_file;
};

static terra_State * getterra(lua_State * L) {
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"__terrastate");
    terra_State * T = (terra_State *) lua_touserdata(L, -1);
    assert(T->L == L);
    lua_pop(L,2);
    return T;
}

static int opensourcefile(lua_State * L) {
    const char * filename = luaL_checkstring(L,-1);
    FILE * f = fopen(filename,"r");
    if(!f) {
        //this might not be a valid filename, or might no longer exist..
        //returning 0 here will suppress printing the carrot ^ but other error messages will still print
        //terra_reporterror(getterra(L),"failed to open file %s\n",filename);
        return 0;
    }
    fseek(f,0, SEEK_END);
    size_t filesize = ftell(f);
#ifndef _MSC_VER
    char * mapped_file = (char*) mmap(0,filesize, PROT_READ, MAP_SHARED, fileno(f), 0);
    if(mapped_file == MAP_FAILED) {
        terra_reporterror(getterra(L),"failed to map file %s\n",filename);
    }
#else
    fseek(f,0,SEEK_SET);
    char *mapped_file = (char*)malloc(filesize);
	filesize = fread(mapped_file, 1, filesize, f);
#endif
    lua_pop(L,1);
    
    SourceInfo * si = (SourceInfo*) lua_newuserdata(L,sizeof(SourceInfo));
    
    si->file = f;
    si->mapped_file = mapped_file;
    si->len = filesize;
    return 1;
}



static int printlocation(lua_State * L) {
    int token = luaL_checkint(L,-1);
    SourceInfo * si = (SourceInfo*) lua_touserdata(L,-2);
    assert(si);
    
    
    int begin = token;
    while(begin > 0 && si->mapped_file[begin] != '\n')
        begin--;
    
    int end = token;
    while(end < si->len && si->mapped_file[end] != '\n')
        end++;
    
    if(begin > 0)
        begin++;
        
    fwrite(&si->mapped_file[begin],end - begin,1,stdout);
    fputc('\n',stdout);
    while(begin < token) {
        if(si->mapped_file[begin] == '\t')
            fputs("        ",stdout);
        else
            fputc(' ',stdout);
        begin++;
    }
    fputc('^',stdout);
    fputc('\n',stdout);
    
    return 0;
}
static int closesourcefile(lua_State * L) {
    SourceInfo * si = (SourceInfo*) lua_touserdata(L,-1);
    assert(si);
#ifndef _MSC_VER
    munmap(si->mapped_file,si->len);
#else
    free(si->mapped_file);
    si->mapped_file = nullptr;
#endif
    fclose(si->file);
    return 0;
}

//implementations of lua functions load, loadfile, loadstring

static const char *reader_luaload(lua_State *L, void *ud, size_t *size) {
    size_t fnvalue = (size_t)ud;
    lua_pushvalue(L,fnvalue);
    lua_call(L,0,1);
    if(lua_isnil(L,-1)) {
        lua_pop(L,1);
        return NULL;
    }
    const char * str = lua_tolstring(L,-1,size);
    lua_pop(L,1);
    return str;
}

int terra_luaload(lua_State * L) {
    const char * chunkname = "=(load)";
    size_t fnvalue;
    if(lua_gettop(L) == 2) {
        chunkname = luaL_checkstring(L,-1);
        fnvalue = lua_gettop(L) - 1;
    } else {
        fnvalue = lua_gettop(L);
    }

    if(terra_load(L,reader_luaload,(void*)fnvalue,chunkname)) {
        lua_pushnil(L);
        lua_pushvalue(L,-2);
        lua_remove(L,-3);
        return 2;
    }
    return 1;
}

int terra_lualoadfile(lua_State * L) {
    const char * file = luaL_checkstring(L,-1);
    if(terra_loadfile(L,file)) {
        lua_pushnil(L);
        lua_pushvalue(L,-2);
        lua_remove(L,-3);
        return 2;
    }
    return 1;
}

int terra_lualoadstring(lua_State * L) {
    const char * string = luaL_checkstring(L,-1);
    if(terra_loadstring(L,string)) {
        lua_pushnil(L);
        lua_pushvalue(L,-2);
        lua_remove(L,-3);
        return 2;
    }
    return 1;
}

//defines terralib bytecodes
#include "terralib.h"
//defines strict.lua bytecodes
#include "strict.h"

int terra_loadandrunbytecodes(lua_State * L, const char * bytecodes, size_t size, const char * name) {
    return luaL_loadbuffer(L, bytecodes, size, name) 
           || lua_pcall(L,0,LUA_MULTRET,0);
}
int terra_init(lua_State * L) {
    terra_State * T = (terra_State*) malloc(sizeof(terra_State));
    assert(T);
    memset(T,0,sizeof(terra_State)); //some of lua stuff expects pointers to be null on entry
    T->L = L;
    assert (T->L);
    lua_newtable(T->L);
    
    lua_pushlightuserdata(L, T);
    lua_setfield(L, -2, "__terrastate"); //reference to our T object, so that we can load it from the lua state on other API calls
    
    lua_setfield(T->L,LUA_GLOBALSINDEX,"terra"); //create global terra object
    terra_kindsinit(T); //initialize lua mapping from T_Kind to/from string
    


    int err =    terra_loadandrunbytecodes(T->L,luaJIT_BC_strict,luaJIT_BC_strict_SIZE, "strict.lua")
              || terra_loadandrunbytecodes(T->L,luaJIT_BC_terralib,luaJIT_BC_terralib_SIZE, "terralib.lua");
              
    if(err) {
        free(T);
        return err;
    }
    
    terra_cwrapperinit(T);
    
    lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
    lua_pushcfunction(T->L,opensourcefile);
    lua_setfield(T->L,-2,"opensourcefile");
    lua_pushcfunction(T->L,closesourcefile);
    lua_setfield(T->L,-2,"closesourcefile");
    lua_pushcfunction(T->L,printlocation);
    lua_setfield(T->L,-2,"printlocation");

    lua_pushcfunction(T->L,terra_luaload);
    lua_setfield(T->L,-2,"load");
    lua_pushcfunction(T->L,terra_lualoadstring);
    lua_setfield(T->L,-2,"loadstring");
    lua_pushcfunction(T->L,terra_lualoadfile);
    lua_setfield(T->L,-2,"loadfile");
    
    lua_newtable(T->L);
    lua_setfield(T->L,-2,"_trees"); //to hold parser generated trees
    lua_pop(T->L,1);
    
    luaX_init(T);
    
    err = terra_compilerinit(T);
    if(err) {
        free(T);
        return err;
    }

    err = terra_cudainit(T); /* if cuda is not enabled, this does nothing */
    if(err) {
        free(T);
        return err;
    }

    return 0;   
}

struct FileInfo {
    FILE * file;
    char buf[512];
};
static const char * file_reader(lua_State * T, void * fi, size_t *sz) {
    FileInfo * fileinfo = (FileInfo*) fi;
    *sz = fread(fileinfo->buf,1,512,fileinfo->file);
    return fileinfo->buf;
}

int terra_load(lua_State *L,lua_Reader reader, void *data, const char *chunkname) {
    int st = lua_gettop(L);
    terra_State * T = getterra(L);
    Zio zio;
    luaZ_init(T,&zio,reader,data);
    int r = luaY_parser(T,&zio,chunkname,zgetc(&zio));
    assert(lua_gettop(L) == st + 1);
    return r;
}


//these helper functions are from the LuaJIT implementation for loadfile and loadstring:

#define TERRA_BUFFERSIZE 512

typedef struct FileReaderCtx {
  FILE *fp;
  char buf[TERRA_BUFFERSIZE];
} FileReaderCtx;

static const char *reader_file(lua_State *L, void *ud, size_t *size)
{
  FileReaderCtx *ctx = (FileReaderCtx *)ud;
  if (feof(ctx->fp)) return NULL;
  *size = fread(ctx->buf, 1, sizeof(ctx->buf), ctx->fp);
  return *size > 0 ? ctx->buf : NULL;
}

typedef struct StringReaderCtx {
  const char *str;
  size_t size;
} StringReaderCtx;

static const char *reader_string(lua_State *L, void *ud, size_t *size)
{
  StringReaderCtx *ctx = (StringReaderCtx *)ud;
  if (ctx->size == 0) return NULL;
  *size = ctx->size;
  ctx->size = 0;
  return ctx->str;
}
//end helper functions

int terra_loadfile(lua_State * L, const char * file) {
    FileReaderCtx ctx;
    ctx.fp = fopen(file,"r");
    if(!ctx.fp) {
       terra_State * T = getterra(L);
       terra_pusherror(T,"failed to open file '%s'",file);
       return LUA_ERRFILE;
    }
    /*peek to see if we have a POSIX comment '#', which we repect on the first like for #! */
    int c = fgetc(ctx.fp);
    ungetc(c,ctx.fp);
    if(c == '#') { /* skip the POSIX comment */
        do {
            c = fgetc(ctx.fp);   
        } while(c != '\n' && c != EOF);
    }

    int r = terra_load(L,reader_file,&ctx,file);
    fclose(ctx.fp);
    return r;
}

int terra_loadbuffer(lua_State * L, const char *buf, size_t size, const char *name) {
    StringReaderCtx ctx;
    ctx.str = buf;
    ctx.size = size;
    return terra_load(L,reader_string,&ctx,name);
}

int terra_loadstring(lua_State *L, const char *s) {
  return terra_loadbuffer(L, s, strlen(s), "<string>");
}
int terra_setverbose(lua_State * L, int v) {
    terra_State * T = getterra(L);
    T->verbose = v;
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_pushinteger(L, v);
    lua_setfield(L, -2, "isverbose");
    lua_pop(L,1);
    return 0;
}

int terra_loadlanguage(lua_State * L) {
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"loadlanguage");
    lua_remove(L,-2); /* remove terra table */
    lua_pushvalue(L,-2); /* push original argument */
    lua_remove(L,-3); /* stack is now [loadlanguage(argument)] */
    return lua_pcall(L,1,1,0);
}
