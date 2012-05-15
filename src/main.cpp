#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include <string.h>
#include <assert.h>



char buf[512];
FILE * file;
const char * my_reader(luaP_State *L, void *ud, size_t *sz) {
	char * r = fgets(buf,512,file);
	if(r) {
		*sz = strlen(r);
	} else {
		*sz = 0;
	}
	return buf;
}
int main(int argc, char ** argv) {
	assert(argc == 2);
	file = fopen(argv[1],"r");
	lua_State * L = luaL_newstate();
	luaL_openlibs(L);
	luaL_dofile(L,"src/terralib.lua");
	assert (L);
	luaP_State ls;
	luaS_resize(&ls,32);
	luaX_init(&ls);
	TString * name = luaS_new(&ls,"foobar");
	Zio zio;
	Mbuffer * buff = (Mbuffer*) malloc(sizeof(Mbuffer));
	luaZ_init(&ls,&zio,my_reader,NULL);
#if 1
	assert(L);
	luaY_parser(L,&ls,&zio,buff,"foobar",zgetc(&zio));
#else
	LexState lex;
	lex.buff = buff;
	luaX_setinput(&ls,&lex,&zio,name,zgetc(&zio));
	do {
		luaX_next(&lex);
		const char * tok = luaX_token2str(&lex,lex.t.token);
		printf("token: %s ",tok);
		switch(lex.t.token) {
		case TK_NAME:
		case TK_STRING:
			printf("(%s)",getstr(lex.t.seminfo.ts));
			break;
		case TK_NUMBER:
			printf("(%f)",lex.t.seminfo.r);
			break;
		default:
			break;
		}
		printf("\n");
	} while(lex.t.token != TK_EOS);
#endif
	return 0;
}
