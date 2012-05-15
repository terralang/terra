#include "llex.h"
#include "lstring.h"
#include "lzio.h"
#include "lparser.h"
#include <string.h>
#include <assert.h>
#include "terra.h"


char buf[512];
FILE * file;

int main(int argc, char ** argv) {
	assert(argc == 2);
	terra_State * T = terra_newstate();
	terra_dofile(T,argv[1]);

#if 0
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
