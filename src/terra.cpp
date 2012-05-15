#include "terra.h"
#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include <stdio.h>
#include <stdarg.h>
#include <assert.h>

void terra_reporterror(terra_State * T, const char * fmt, ...) {
	va_list ap;
	va_start(ap,fmt);
	vfprintf(stderr,fmt,ap);
	va_end(ap);
	exit(1);
}

terra_State * terra_newstate() {
	terra_State * T = (terra_State*) malloc(sizeof(terra_State));
	assert(T);
	T->L = luaL_newstate();
	assert (T->L);
	luaL_openlibs(T->L);
	//TODO: embed in executable
	if(luaL_dofile(T->L,"src/terralib.lua")) {
		terra_reporterror(T,luaL_checkstring(T->L,-1));
		free(T);
		return NULL;
	}
	luaS_resize(T,32);
	luaX_init(T);
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
	luaZ_init(T,&zio,file_reader,&fileinfo);
	luaY_parser(T,&zio,buff,file,zgetc(&zio));
	fclose(fileinfo.file);
	free(buff);
	return 0;
}
