/*
** $Id: llex.h,v 1.72 2011/11/30 12:43:51 roberto Exp $
** Lexical Analyzer
** See Copyright Notice in lua.h
*/

#ifndef llex_h
#define llex_h

//#include "lobject.h"
#include "lzio.h"
#include "lutil.h"
#include <vector>
#include <algorithm>

#define FIRST_RESERVED  257

/*
* WARNING: if you change the order of this enumeration,
* grep "ORDER RESERVED"
*/
enum RESERVED {
  /* terminal symbols denoted by reserved words */
  TK_AND = FIRST_RESERVED, TK_BREAK,
  TK_DO, TK_ELSE, TK_ELSEIF, TK_END, TK_FALSE, TK_FOR, TK_FUNCTION,
  TK_GOTO, TK_IF, TK_IN, TK_LOCAL, TK_NIL, TK_NOT, TK_OR, TK_REPEAT,
  TK_RETURN, TK_THEN, TK_TRUE, TK_UNTIL, TK_WHILE, TK_TERRA, TK_VAR, TK_STRUCT, TK_UNION, TK_QUOTE, TK_IMPORT, TK_DEFER, TK_ESCAPE, /* WARNING: if you add a new last terminal, make sure to update NUM_RESERVED below to be the last terminal */
  /* other terminal symbols */
  TK_CONCAT, TK_DOTS, TK_EQ, TK_GE, TK_LE, TK_NE, TK_DBCOLON, TK_FUNC_PTR, TK_LSHIFT, TK_RSHIFT, TK_EOS,
  TK_NUMBER, TK_NAME, TK_STRING, TK_SPECIAL
};

/* number of reserved words */
#define NUM_RESERVED    (cast(int, TK_ESCAPE-FIRST_RESERVED+1))


typedef struct {
  union {
      luaP_Number r;
      TString * ts;
  };
  int flags; //same as ReadNumber flags
  uint64_t i; //integer value, for terra
  int linebegin; //line on which we _started_ parsing this token
  int buffer_begin; //position in buffer where we _started_ parsing this token
} SemInfo;  /* semantics information */


typedef struct Token {
  int token;
  SemInfo seminfo;
} Token;


struct OutputBuffer {
    int N;
    int space;
    char * data;
};

static inline void OutputBuffer_init(OutputBuffer * buf) {
    buf->N = 0;
    buf->space = 1024;
    buf->data = (char*) malloc(buf->space);
}
static inline void OutputBuffer_free(OutputBuffer * buf) {
    buf->N = 0;
    buf->space = 0;
    free(buf->data);
    buf->data = NULL;
}
static inline void OutputBuffer_resize(OutputBuffer * buf, int newsize) {
    buf->N = std::min(newsize,buf->N);
    buf->space = newsize;
    buf->data = (char*) realloc(buf->data,newsize);
}
static inline void OutputBuffer_putc(OutputBuffer * buf, char c) {
    if(buf->N == buf->space)
        OutputBuffer_resize(buf,buf->space * 2);
    buf->data[buf->N] = c;
    buf->N++;
}
static inline void OutputBuffer_rewind(OutputBuffer * buf, int size) {
    buf->N -= std::min(buf->N,size);
}
static inline void OutputBuffer_printf(OutputBuffer * buf,const char * fmt,...) {
    if(buf->N == buf->space) {
        OutputBuffer_resize(buf,buf->space * 2);
    }
    while(1) {
        va_list ap;
        va_start(ap,fmt);
        int most_written = buf->space - buf->N;
        int n = vsnprintf(buf->data + buf->N, most_written, fmt, ap);
        if(n > -1 && n < most_written) {
            buf->N += n;
            return;
        }
        OutputBuffer_resize(buf, buf->space * 2);
    }
}
static inline void OutputBuffer_puts(OutputBuffer * buf, int N, const char * str) {
    if(buf->N + N > buf->space) {
        OutputBuffer_resize(buf,std::max(buf->space * 2,buf->N + N));
    }
    memcpy(buf->data + buf->N,str,N);
    buf->N += N;
}

struct TerraCnt;
/* state of the lexer plus state of the parser when shared by all
   functions */
typedef struct LexState {
  int current;  /* current character (charint) */
  int linenumber;  /* input line counter */
  int lastline;  /* line of last token `consumed' */
  int currentoffset;
  Token t;  /* current token */
  Token lookahead;  /* look ahead token */
  struct FuncState *fs;  /* current function (parser) */
  TerraCnt * terracnt;
  lua_State *L;
  int n_lua_objects; /*number of lua objects already in table of lua asts*/
  terra_State *LP;
  ZIO *z;  /* input stream */
  Mbuffer *buff;  /* buffer for tokens */
  TString * source;  /* current source name */
  TString * envn;  /* environment variable name */
  char decpoint;  /* locale decimal point */

  int in_terra;
  OutputBuffer output_buffer;

  struct {
      char * buffer;
      int N;
      int space;
  } patchinfo; //data to fix up output stream when we insert terra information
  
  int stacktop; /* top of lua stack when we start this function */
  int languageextensionsenabled; /* 0 if extensions are off */
  int rethrow; /* set to 1 when le_luaexpr needs to re-report an error message, used to suppress the duplicate
                  addition of context information */
  char lextable; /* &lextable is the registry key for lua state associated with the LexState object*/
} LexState;


LUAI_FUNC void luaX_init (terra_State *L);
LUAI_FUNC void luaX_setinput (terra_State *L, LexState *ls, ZIO *z,
                              TString * source, int firstchar);
LUAI_FUNC TString * luaX_newstring (LexState *ls, const char *str, size_t l);
LUAI_FUNC void luaX_next (LexState *ls);
LUAI_FUNC int luaX_lookahead (LexState *ls);
LUAI_FUNC l_noret luaX_syntaxerror (LexState *ls, const char *s);
LUAI_FUNC const char * luaX_token2str (LexState *ls, int token);
LUAI_FUNC void luaX_patchbegin(LexState *ls, Token * begin_token);
LUAI_FUNC void luaX_patchend(LexState *ls, Token * begin_token);
LUAI_FUNC void luaX_insertbeforecurrenttoken(LexState * ls, char c);
const char * luaX_saveoutput(LexState * ls, Token * begin_token);
void luaX_getoutput(LexState * ls, Token * begin_token, const char ** output, int * N);
const char * luaX_token2rawstr(LexState * ls, int token);

void luaX_pushtstringtable(terra_State * L);
void luaX_poptstringtable(terra_State * L);
l_noret luaX_reporterror(LexState * ls, const char * err);


enum TA_Globals {
    TA_TERRA_OBJECT = 1,
    TA_FUNCTION_TABLE,
    TA_NEWLIST,
    TA_ENTRY_POINT_TABLE,
    TA_LANGUAGES_TABLE,
    TA_TYPE_TABLE,
    TA_LAST_GLOBAL
};
//accessors for lua state assocated with the Terra lexer
void luaX_globalpush(LexState * ls, TA_Globals k);
void luaX_globalgettable(LexState * ls, TA_Globals k);
void luaX_globalgetfield(LexState * ls, TA_Globals k, const char * field);
void luaX_globalset(LexState * ls, TA_Globals k);

#endif
