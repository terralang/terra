#include "terra.h"
#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include "tcompiler.h"
#include <stdio.h>
#include <stdarg.h>
#include <assert.h>
#include <sys/mman.h>

void terra_reporterror(terra_State * T, const char * fmt, ...) {
	va_list ap;
	va_start(ap,fmt);
	vfprintf(stderr,fmt,ap);
	va_end(ap);
	exit(1);
}

struct SourceInfo {
	FILE * file;
	size_t len;
	char * mapped_file;
};

static int opensourcefile(lua_State * L) {
	const char * filename = luaL_checkstring(L,-1);
	FILE * f = fopen(filename,"r");
	if(!f) {
		terra_reporterror(NULL,"failed to open file %s\n",filename);
	}
	fseek(f,0, SEEK_END);
	size_t filesize = ftell(f);
	char * mapped_file = (char*) mmap(0,filesize, PROT_READ, MAP_SHARED, fileno(f), 0);
	if(mapped_file == MAP_FAILED) {
		terra_reporterror(NULL,"failed to map file %s\n",filename);
	}
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
	
	fwrite(&si->mapped_file[begin+1],end - begin,1,stdout);
	
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
	munmap(si->mapped_file,si->len);
	fclose(si->file);
	return 0;
}


terra_State * terra_newstate() {
	terra_State * T = (terra_State*) malloc(sizeof(terra_State));
	assert(T);
	memset(T,0,sizeof(terra_State)); //some of lua stuff expects pointers to be null on entry
	T->L = luaL_newstate();
	assert (T->L);
	luaL_openlibs(T->L);
	//TODO: embed in executable
	if(luaL_dofile(T->L,"src/terralib.lua")) {
		terra_reporterror(T,"%s\n",luaL_checkstring(T->L,-1));
		free(T);
		return NULL;
	}
	
	lua_getfield(T->L,LUA_GLOBALSINDEX,"terra");
	lua_pushcfunction(T->L,opensourcefile);
	lua_setfield(T->L,-2,"opensourcefile");
	lua_pushcfunction(T->L,closesourcefile);
	lua_setfield(T->L,-2,"closesourcefile");
	lua_pushcfunction(T->L,printlocation);
	lua_setfield(T->L,-2,"printlocation");
	lua_pop(T->L,1);
	
	luaS_resize(T,32);
	luaX_init(T);
	
	terra_compilerinit(T);
	
	return T;	
}

struct FileInfo {
	FILE * file;
	char buf[512];
};
static const char * file_reader(terra_State * T, void * fi, size_t *sz) {
	FileInfo * fileinfo = (FileInfo*) fi;
	*sz = fread(fileinfo->buf,1,512,fileinfo->file);
	return fileinfo->buf;
}

int terra_dofile(terra_State * T, const char * file) {
	FileInfo fileinfo;
	fileinfo.file = fopen(file,"r");
	if(!fileinfo.file) {
		terra_reporterror(T,"failed to open file %s\n",file);
	}
	Zio zio;
	Mbuffer * buff = (Mbuffer*) malloc(sizeof(Mbuffer));
	memset(buff,0,sizeof(Mbuffer));
	luaZ_init(T,&zio,file_reader,&fileinfo);
	luaY_parser(T,&zio,buff,file,zgetc(&zio));
	fclose(fileinfo.file);
	free(buff);
	return 0;
}
