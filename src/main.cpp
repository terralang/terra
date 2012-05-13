#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include <string.h>
lua_State ls;
#include <assert.h>

char buf[512];
FILE * file;
const char * my_reader(lua_State *L, void *ud, size_t *sz) {
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
	luaS_resize(&ls,32);
	luaX_init(&ls);
	LexState lex;
	TString * name = luaS_new(&ls,"foobar");
	Zio zio;
	lex.buff = (Mbuffer*) malloc(sizeof(Mbuffer));
	luaZ_init(&ls,&zio,my_reader,NULL);
	Dyndata dyd;
#if 1
	luaY_parser(&ls,&zio,lex.buff,&dyd,"foobar",zgetc(&zio));
#else
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
