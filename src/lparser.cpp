/*
** $Id: lparser.c,v 2.124 2011/12/02 13:23:56 roberto Exp $
** Lua Parser
** See Copyright Notice in lua.h
*/


#include <string.h>
#include <assert.h>
#include <inttypes.h>

#define lparser_c
#define LUA_CORE

//#include "lua.h"

//#include "lcode.h"
//#include "ldebug.h"
//#include "ldo.h"
//#include "lfunc.h"
#include "llex.h"
//#include "lmem.h"
#include "lobject.h"
//#include "lopcodes.h"
#include "lparser.h"
//#include "lstate.h"
#include "lstring.h"
//#include "ltable.h"
#include <vector>
#include <set>
#include <sstream>
#include "llvm/ADT/SmallSet.h"
#include "treadnumber.h"

static void dump_stack(lua_State * L, int elem);


//helpers to ensure that the lua stack contains the right number of arguments after a call
#define RETURNS_N(x,n) do { \
    if(ls->in_terra) { \
        int begin = lua_gettop(ls->L); \
        (x); \
        int end = lua_gettop(ls->L); \
        if(begin + n != end) { \
            fprintf(stderr,"%s:%d: unmatched return\n",__FILE__,__LINE__); \
            luaX_syntaxerror(ls,"error"); \
        } \
    } else { \
        (x); \
    } \
} while(0)

#define RETURNS_1(x) RETURNS_N(x,1)
#define RETURNS_0(x) RETURNS_N(x,0)

/* maximum number of local variables per function (must be smaller
   than 250, due to the bytecode format) */
#define MAXVARS     200

#define hasmultret(k)       ((k) == VCALL || (k) == VVARARG)

typedef llvm::SmallSet<TString*,16> StringSet;

/*
** nodes for block list (list of active blocks)
*/
typedef struct BlockCnt {
  struct BlockCnt *previous;  /* chain */
  StringSet defined;
  int isterra; /* does this scope describe a terra scope or a lua scope?*/
  int languageextensionsdefined;
} BlockCnt;

struct TerraCnt {
    StringSet capturedlocals; /*list of all local variables that this terra block captures from the immediately enclosing lua block */
    BlockCnt block;
    TerraCnt * previous;
};


static int new_table(LexState * ls) {
    if(ls->in_terra) {
        //printf("(new table)\n");
        lua_newtable(ls->L);
        return lua_gettop(ls->L);
    } else return 0;
}
static int new_list(LexState * ls) {
    if(ls->in_terra) {
        luaX_globalpush(ls,TA_NEWLIST);
        lua_call(ls->L,0,1);
        return lua_gettop(ls->L);
    } else return 0;
}

static int new_list_before(LexState * ls) {
    if(ls->in_terra) {
        int t = new_list(ls);
        lua_insert(ls->L,-2);
        return t - 1;
    } else return 0;
}
static void push_string_before(LexState * ls, const char * str) {
    if(ls->in_terra) {
        lua_pushstring(ls->L,str);
        lua_insert(ls->L,-2);
    }
}
//this should eventually be optimized to use 'add_field' with tokens already on the stack
static void add_field(LexState * ls, int table, const char * field) {
    if(ls->in_terra) {
        table = (table < 0) ? (table + lua_gettop(ls->L) + 1) : table; //otherwise table is wrong once we modify the stack 
        //printf("consume field\n");
        
        lua_setfield(ls->L,table,field);
    }
}
static void push_string(LexState * ls, const char * str) {
    if(ls->in_terra) {
        //printf("push string: %s\n",str);
        lua_pushstring(ls->L,str);
    }
}

struct Position {
    int linenumber;
    int offset;
};

static Position getposition(LexState * ls) {
    Position p = { ls->linenumber, ls->currentoffset - 1 };
    return p;
}

static void table_setposition(LexState * ls, int t, Position p) {
    lua_pushinteger(ls->L,p.linenumber);
    lua_setfield(ls->L,t,"linenumber");
    lua_pushinteger(ls->L,p.offset);
    lua_setfield(ls->L,t,"offset");
    lua_pushstring(ls->L, getstr(ls->source));
    lua_setfield(ls->L,t, "filename");
}

static int newobjecterror(lua_State *L) {
    printf("newobjecterror: %s\n",lua_tostring(L,-1));
    exit(1);
}

static int new_object(LexState * ls, const char * k, int N, Position * p) {
    if(ls->in_terra) {
        luaX_globalgetfield(ls, TA_TYPE_TABLE, k);
        lua_insert(ls->L,-(N+1));
        
        lua_pushcfunction(ls->L,newobjecterror);
        lua_insert(ls->L,-(N+2));
        
        lua_pcall(ls->L,N,1,-(N+2));
        
        table_setposition(ls, lua_gettop(ls->L) , *p);
        
        lua_remove(ls->L,-2);
        
        return lua_gettop(ls->L);
    } else return 0;
}

static void add_index(LexState * ls, int table, int n) {
    if(ls->in_terra) {
        //printf("consume index\n");
        lua_pushinteger(ls->L,n);
        lua_pushvalue(ls->L,-2);
        lua_settable(ls->L,table);
        lua_pop(ls->L,1);
    }
}
static int add_entry(LexState * ls, int table) {
    if(ls->in_terra) {
        int n = lua_objlen(ls->L,table);
        add_index(ls,table,n+1);
        return n+1;
    } else return 0;
}

static void push_string(LexState * ls, TString * str) {
    push_string(ls,getstr(str));
}
static void push_boolean(LexState * ls, int b) {
    if(ls->in_terra) {
        //printf("push boolean\n");
        lua_pushboolean(ls->L,b);
    }
}
static void check_no_terra(LexState * ls, const char * thing) {
    if(ls->in_terra) {
        luaX_syntaxerror(ls,luaS_cstringf(ls->LP,"%s cannot be nested in terra functions.", thing));
    }
}
static void check_terra(LexState * ls, const char * thing) {
    if(!ls->in_terra) {
        luaX_syntaxerror(ls,luaS_cstringf(ls->LP,"%s cannot be used outside terra functions.",  thing));
    }
}
/*
** prototypes for recursive non-terminal functions
*/
static void statement (LexState *ls);
static void expr (LexState *ls);
static void terratype(LexState * ls);
static void luaexpr(LexState * ls);
static void embeddedcode(LexState * ls, int isterra, int isexp);
static void doquote(LexState * ls, int isexp);
static void languageextension(LexState * ls, int isstatement, int islocal);

static void definevariable(LexState * ls, TString * varname) {
    ls->fs->bl->defined.insert(varname);
}
static void refvariable(LexState * ls, TString * varname) {
  if(ls->terracnt == NULL)
    return; /* no need to search for variables if we are not in a terra scope at all */
  //printf("searching %s\n",getstr(varname));
  TerraCnt * cur = NULL;
  for(BlockCnt * bl = ls->fs->bl; bl != NULL; bl = bl->previous) {
    //printf("ctx %d\n",bl->isterra);
    if(bl->defined.count(varname)) {
        if(cur && !bl->isterra)
          cur->capturedlocals.insert(varname);
        break;
    }
    if(bl->isterra && bl->previous && !bl->previous->isterra) {
      cur = (cur) ? cur->previous : ls->terracnt;
      assert(cur != NULL);
    }
  }
}

static l_noret error_expected (LexState *ls, int token) {
  luaX_syntaxerror(ls,
      luaS_cstringf(ls->LP, "%s expected", luaX_token2str(ls, token)));
}


static l_noret errorlimit (FuncState *fs, int limit, const char *what) {
  terra_State *L = fs->ls->LP;
  const char *msg;
  int line = fs->f.linedefined;
  const char *where = (line == 0)
                      ? "main function"
                      : luaS_cstringf(L, "function at line %d", line);
  msg = luaS_cstringf(L, "too many %s (limit is %d) in %s",
                             what, limit, where);
  luaX_syntaxerror(fs->ls, msg);
}


static void checklimit (FuncState *fs, int v, int l, const char *what) {
  if (v > l) errorlimit(fs, l, what);
}


static int testnext (LexState *ls, int c) {
  if (ls->t.token == c) {
    luaX_next(ls);
    return 1;
  }
  else return 0;
}


static void check (LexState *ls, int c) {
  if (ls->t.token != c)
    error_expected(ls, c);
}


static void checknext (LexState *ls, int c) {
  check(ls, c);
  luaX_next(ls);
}


#define check_condition(ls,c,msg)   { if (!(c)) luaX_syntaxerror(ls, msg); }



static void check_match (LexState *ls, int what, int who, int where) {
  if (!testnext(ls, what)) {
    if (where == ls->linenumber)
      error_expected(ls, what);
    else {
      luaX_syntaxerror(ls, luaS_cstringf(ls->LP,
             "%s expected (to close %s at line %d)",
              luaX_token2str(ls, what), luaX_token2str(ls, who), where));
    }
  }
}


static TString *str_checkname (LexState *ls) {
  TString *ts;
  check(ls, TK_NAME);
  ts = ls->t.seminfo.ts;
  luaX_next(ls);
  return ts;
}

static void singlevar (LexState *ls) {
  Position p = getposition(ls);
  TString * varname = str_checkname(ls);
  push_string(ls,varname);
  new_object(ls,"var", 1,&p);
  refvariable(ls, varname);
}

//tries to parse a symbol "NAME | '['' lua expression '']'"
//returns true if a name was parsed and sets str to that name
//otherwise, str is not modified
static bool checksymbol(LexState * ls, TString ** str) {
  Position p = getposition(ls);
  int line = ls->linenumber;
  if(ls->in_terra && testnext(ls,'[')) {
    RETURNS_1(luaexpr(ls));
    new_object(ls,"escapedident",1,&p);
    check_match(ls, ']', '[', line);
    return false;
  }
  TString * nm = str_checkname(ls);
  if(str)
    *str = nm;
  push_string(ls,nm);
  new_object(ls,"namedident",1,&p);
  return true;
}

static void enterlevel (LexState *ls) {
  terra_State *L = ls->LP;
  ++L->nCcalls;
  checklimit(ls->fs, L->nCcalls, LUAI_MAXCCALLS, "C levels");
}

#define leavelevel(ls)  ((ls)->LP->nCcalls--)

static void enterblock (FuncState *fs, BlockCnt *bl, lu_byte isloop) {
  bl->previous = fs->bl;
  bl->isterra = fs->ls->in_terra;
  bl->languageextensionsdefined = 0;
  fs->bl = bl;
  //printf("entering block %lld\n", (long long int)bl);
  //printf("previous is %lld\n", (long long int)bl->previous);
}

static void leaveblock (FuncState *fs) {
  BlockCnt *bl = fs->bl;
  LexState *ls = fs->ls;
  if(bl->languageextensionsdefined > 0) {
    luaX_globalgetfield(ls, TA_TERRA_OBJECT, "unimportlanguages");
    luaX_globalpush(ls, TA_LANGUAGES_TABLE);
    lua_pushnumber(ls->L, bl->languageextensionsdefined);
    luaX_globalpush(ls, TA_ENTRY_POINT_TABLE);
    lua_call(ls->L, 3, 0);
    ls->languageextensionsenabled -= bl->languageextensionsdefined;
  }
  fs->bl = bl->previous;
  //printf("leaving block %lld\n", (long long int)bl);
  //printf("now is %lld\n", (long long int)fs->bl);
  //for(int i = 0; i < bl->local_variables.size(); i++) {
  //      printf("v[%d] = %s\n",i,getstr(bl->local_variables[i]));
  //}
}

static void enterterra(LexState * ls, TerraCnt * current) {
    current->previous = ls->terracnt;
    ls->terracnt = current;
    ls->in_terra++;
    enterblock(ls->fs, &current->block, 0);
}

static void leaveterra(LexState * ls) {
    assert(ls->in_terra);
    assert(ls->terracnt);
    leaveblock(ls->fs);
    ls->terracnt = ls->terracnt->previous;
    ls->in_terra--;
}

static void open_func (LexState *ls, FuncState *fs, BlockCnt *bl) {
  fs->prev = ls->fs;  /* linked list of funcstates */
  fs->bl = (fs->prev) ? ls->fs->bl : NULL;
  fs->ls = ls;
  ls->fs = fs;
  fs->f.linedefined = 0;
  fs->f.is_vararg = 0;
  fs->f.source = ls->source;
  enterblock(fs, bl, 0);
}


static void close_func (LexState *ls) {
  FuncState *fs = ls->fs;
  leaveblock(fs);
  ls->fs = fs->prev;
}


/*
** opens the main function, which is a regular vararg function with an
** upvalue named LUA_ENV
*/
static void open_mainfunc (LexState *ls, FuncState *fs, BlockCnt *bl) {
  open_func(ls, fs, bl);
  fs->f.is_vararg = 1;  /* main function is always vararg */
}

static void dump_stack(lua_State * L, int elem) {
    lua_pushvalue(L,elem);
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"tree");
    lua_getfield(L,-1,"printraw");
    lua_pushvalue(L,-4);
    lua_call(L, 1, 0);
        
    lua_pop(L,3);
}

/*============================================================*/
/* GRAMMAR RULES */
/*============================================================*/


/*
** check whether current token is in the follow set of a block.
** 'until' closes syntactical blocks, but do not close scope,
** so it handled in separate.
*/
static int block_follow (LexState *ls, int withuntil) {
  switch (ls->t.token) {
    case TK_ELSE: case TK_ELSEIF:
    case TK_END: case TK_EOS: case TK_IN:
      return 1;
    case TK_UNTIL: return withuntil;
    default: return 0;
  }
}


static void statlist (LexState *ls) {
  /* statlist -> { stat [`;'] } */
  int tbl = new_list(ls);
  while (!block_follow(ls, 1)) {
    if (ls->t.token == TK_RETURN) {
      statement(ls);
      add_entry(ls,tbl);
      return;  /* 'return' must be last statement */
    }
    if (ls->t.token == ';') {
      luaX_next(ls);
    } else {
      statement(ls);
      add_entry(ls,tbl);
    }
  }
}

static void push_type(LexState * ls, const char * typ) {
    if(ls->in_terra) {
        luaX_globalgetfield(ls, TA_TERRA_OBJECT, "types");
        lua_getfield(ls->L,-1,typ);
        lua_remove(ls->L,-2); //types object
    }
}

static void push_literal(LexState * ls, const char * typ) {
    if(ls->in_terra) {
        push_type(ls,typ);
        Position p = getposition(ls);
        new_object(ls,"literal",2,&p);
    }
}
static void push_double(LexState * ls, double d) {
    if(ls->in_terra) {
        lua_pushnumber(ls->L,d);
    }
}

static void push_integer(LexState * ls, int64_t i) {
    if(ls->in_terra) {
        void * data = lua_newuserdata(ls->L,sizeof(int64_t));
        *(int64_t*)data = i;
    }
}
static void push_nil(LexState * ls) { 
    if(ls->in_terra)
        lua_pushnil(ls->L);
}

static void yindex (LexState *ls) {
  /* index -> '[' expr ']' */
  luaX_next(ls);  /* skip the '[' */
  
  RETURNS_1(expr(ls));  
  //luaK_exp2val(ls->fs, v);
  checknext(ls, ']');
}


/*
** {======================================================================
** Rules for Constructors
** =======================================================================
*/


struct ConsControl {
  int nh;  /* total number of `record' elements */
  int na;  /* total number of array elements */
};


static void recfield (LexState *ls, struct ConsControl *cc) {
  /* recfield -> (NAME | `['exp1`]') = exp1 */
  FuncState *fs = ls->fs;
  Position pos = getposition(ls);
  if (ls->t.token == TK_NAME) {
    checklimit(fs, cc->nh, MAX_INT, "items in a constructor");
    RETURNS_1(checksymbol(ls, NULL));
  } else  { /* ls->t.token == '[' */
    if(!ls->in_terra) {
      yindex(ls);
    } else {
      RETURNS_1(expr(ls));
      if(ls->t.token == '=') {
        lua_getfield(ls->L,-1, "kind");
        lua_pushstring(ls->L,"luaexpression");
        if(!lua_equal(ls->L,-1,-2))
            luaX_syntaxerror(ls, "unexpected symbol");
        lua_pop(ls->L,2); //kind and luaexpression
        new_object(ls,"escapedident",1,&pos);
      } else {
        /* oops! this wasn't a recfield, but a listfield with an escape */
        new_object(ls,"listfield",1,&pos);
        return;        
      }
    }
  }
  cc->nh++;
  checknext(ls, '=');
  RETURNS_1(expr(ls));
  new_object(ls,"recfield",2,&pos);
}

static void listfield (LexState *ls, struct ConsControl *cc) {
  /* listfield -> exp */
  Position pos = getposition(ls);
  RETURNS_1(expr(ls));
  new_object(ls,"listfield",1,&pos);
  checklimit(ls->fs, cc->na, MAX_INT, "items in a constructor");
  cc->na++;
}


static void field (LexState *ls, struct ConsControl *cc) {
  /* field -> listfield | recfield */
  switch(ls->t.token) {
    case TK_NAME: {  /* may be 'listfield' or 'recfield' */
      if (luaX_lookahead(ls) != '=')  /* expression? */
        listfield(ls, cc);
      else
        recfield(ls, cc);
      break;
    }
    case '[': {
      recfield(ls, cc);
      break;
    }
    default: {
      listfield(ls, cc);
      break;
    }
  }
}


static void constructor (LexState *ls) {
  /* constructor -> '{' [ field { sep field } [sep] ] '}'
     sep -> ',' | ';' */
  int line = ls->linenumber;
  struct ConsControl cc;
  cc.na = cc.nh = 0;
  Position pos = getposition(ls);
  int records = new_list(ls);
  checknext(ls, '{');
  do {
    if (ls->t.token == '}') break;
    RETURNS_1(field(ls, &cc));
    add_entry(ls,records);
  } while (testnext(ls, ',') || testnext(ls, ';'));
  check_match(ls, '}', '{', line);
  new_object(ls,"constructoru",1,&pos);
}

static void structfield (LexState *ls) {
  Position p = getposition(ls);
  push_string(ls,str_checkname(ls));
  checknext(ls, ':');
  RETURNS_1(terratype(ls));
  new_object(ls,"structentry",2,&p);
}

static void structbody(LexState * ls) {
    Position p = getposition(ls);
    int records = new_list(ls);
    checknext(ls,'{');
    while(ls->t.token != '}') {
       if(testnext(ls, TK_UNION))
         RETURNS_1(structbody(ls));
       else
         RETURNS_1(structfield(ls));
       add_entry(ls,records);
       if(ls->t.token == ',' || ls->t.token == ';')
         luaX_next(ls);
    }
    check_match(ls,'}','{',p.linenumber);
    new_object(ls,"structlist",1,&p);
}
static void structconstructor(LexState * ls) {
    // already parsed 'struct' or 'struct' name.
    //starting at '{' or '('
    Position p = getposition(ls);
    if(testnext(ls,'(')) {
        RETURNS_1(luaexpr(ls));
        check_match(ls,')','(',p.linenumber);
    } else push_nil(ls);
    structbody(ls);
    new_object(ls,"structdef",2,&p);
}

struct Name {
    std::vector<TString *> data; //for patching the [local] terra a.b.c.d, and [local] var a.b.c.d sugar
};

static void Name_add(Name * name, TString * string) {
    name->data.push_back(string);
}

static void Name_print(Name * name, LexState * ls) {
    size_t N = name->data.size();
    for(size_t i = 0; i < N; i++) {
        OutputBuffer_printf(&ls->output_buffer,"%s",getstr(name->data[i]));
        if(i + 1 < N)
             OutputBuffer_putc(&ls->output_buffer, '.');
    }
}

static void print_captured_locals(LexState * ls, TerraCnt * tc);

/* print_stack not used anywhere right now - comment out to eliminate
   compiler warning */
#if 0
static void print_stack(lua_State * L, int idx) {
    lua_pushvalue(L,idx);
    lua_getfield(L,LUA_GLOBALSINDEX,"print");
    lua_insert(L,-2);
    lua_call(L,1,0);
}
#endif

//store the lua object on the top of the stack to to the _G.terra._trees table, returning its index in the table
static int store_value(LexState * ls) {
    int i = 0;
    if(ls->in_terra) {
        luaX_globalpush(ls, TA_FUNCTION_TABLE);
        lua_insert(ls->L,-2);
        i = add_entry(ls, lua_gettop(ls->L) - 1);
        lua_pop(ls->L,1); /*remove function table*/
    }
    return i;
}

static void printtreesandnames(LexState * ls, std::vector<int> * trees, std::vector<TString *> * names) {
  OutputBuffer_printf(&ls->output_buffer,"{");
  for(size_t i = 0; i < trees->size(); i++) {
    OutputBuffer_printf(&ls->output_buffer,"_G.terra._trees[%d]",(*trees)[i]);
    if (i + 1 < trees->size())
      OutputBuffer_putc(&ls->output_buffer,',');
  }
  OutputBuffer_printf(&ls->output_buffer,"},{");
  for(size_t i = 0; i < names->size(); i++) {
    OutputBuffer_printf(&ls->output_buffer,"\"%s\"",getstr((*names)[i]));
    if (i + 1 < names->size())
      OutputBuffer_putc(&ls->output_buffer,',');
  }
  OutputBuffer_printf(&ls->output_buffer,"}");
}

/* }====================================================================== */

static int vardecl(LexState *ls, int requiretype, TString ** vname) {
    Position p = getposition(ls);
    int wasstring = checksymbol(ls, vname);
    if (ls->in_terra && wasstring && (requiretype || ls->t.token == ':')) {
        checknext(ls, ':');
        RETURNS_1(terratype(ls));
    } else push_nil(ls);
    new_object(ls,"unevaluatedparam",2,&p);
    return wasstring;
}

static void parlist (LexState *ls) {
  /* parlist -> [ param { `,' param } ] */
  FuncState *fs = ls->fs;
  Proto *f = &fs->f;
  int tbl = new_list(ls);
  f->is_vararg = 0;
  std::vector<TString *> vnames;
  if (ls->t.token != ')') {  /* is `parlist' not empty? */
    do {
      switch (ls->t.token) {
        case TK_NAME: case '[': {  /* param -> NAME */
          TString * vname;
          if(vardecl(ls, 1, &vname))
            vnames.push_back(vname);
          add_entry(ls,tbl);
          break;
        }
        case TK_DOTS: {  /* param -> `...' */
          luaX_next(ls);
          f->is_vararg = 1;
          break;
        }
        default: luaX_syntaxerror(ls, "<name> or " LUA_QL("...") " expected");
      }
    } while (!f->is_vararg && testnext(ls, ','));
  }
  for(size_t i = 0; i < vnames.size(); i++)
    definevariable(ls, vnames[i]);
}
static void block (LexState *ls);

static void body (LexState *ls, int ismethod, int line) {
  /* body ->  `(' parlist `)' block END */
  FuncState new_fs;
  BlockCnt bl;
  open_func(ls, &new_fs, &bl);
  new_fs.f.linedefined = line;
  Position p = getposition(ls);
  checknext(ls, '(');
  RETURNS_1(parlist(ls));
  if (ismethod) {
    definevariable(ls, luaS_new(ls->LP,"self"));
  }
  push_boolean(ls,new_fs.f.is_vararg);
  checknext(ls, ')');
  if(ls->in_terra && testnext(ls,':')) {
    RETURNS_1(terratype(ls));
  } else push_nil(ls);
  RETURNS_1(block(ls));
  new_fs.f.lastlinedefined = ls->linenumber;
  check_match(ls, TK_END, TK_FUNCTION, line);
  close_func(ls);
  new_object(ls,"functiondefu",4,&p);
}

static int explist (LexState *ls) {
  /* explist -> expr { `,' expr } */
  int n = 1;  /* at least one expression */
  int lst = new_list(ls);
  expr(ls);
  add_entry(ls,lst);
  while (testnext(ls, ',')) {
    //luaK_exp2nextreg(ls->fs, v);
    expr(ls);
    add_entry(ls,lst);
    n++;
  }
  return n;
}


static void funcargs (LexState *ls, int line) {
  switch (ls->t.token) {
    case '(': {  /* funcargs -> `(' [ explist ] `)' */
      luaX_next(ls);
      if (ls->t.token == ')') {  /* arg list is empty? */
        new_list(ls); //empty return list
      } else {
        RETURNS_1(explist(ls));
      }
      check_match(ls, ')', '(', line);
      break;
    }
    case '{': {  /* funcargs -> constructor */
      int exps = new_list(ls);
      RETURNS_1(constructor(ls));
      add_entry(ls,exps);
      break;
    }
    case TK_STRING: {  /* funcargs -> STRING */
      //codestring(ls, &args, ls->t.seminfo.ts);
      int exps = new_list(ls);
      push_string(ls,ls->t.seminfo.ts);
      push_literal(ls,"rawstring");
      add_entry(ls,exps);
      luaX_next(ls);  /* must use `seminfo' before `next' */
      break;
    }
    case '`': case TK_QUOTE: {
        int exps = new_list(ls);
        doquote(ls,ls->t.token == '`');
        add_entry(ls, exps);
        break;
    }
    default: {
      luaX_syntaxerror(ls, "function arguments expected");
    }
  }
}




/*
** {======================================================================
** Expression parsing
** =======================================================================
*/

static void prefixexp (LexState *ls) {
  /* prefixexp -> NAME | '(' expr ')' */
  
  switch (ls->t.token) {
    case '(': {
      int line = ls->linenumber;
      luaX_next(ls);
      RETURNS_1(expr(ls));
      check_match(ls, ')', '(', line);
      return;
    }
    case '[': {
      check_terra(ls, "escape");
      int line = ls->linenumber;
      luaX_next(ls);
      RETURNS_1(luaexpr(ls));
      check_match(ls, ']', '[', line);
      return;
    }
    case TK_NAME: {
      RETURNS_1(singlevar(ls));
      return;
    }
    default: {
      luaX_syntaxerror(ls, "unexpected symbol");
    }
  }
}

static int issplitprimary(LexState * ls) {
    if(ls->lastline != ls->linenumber) {
        luaX_insertbeforecurrenttoken(ls, ';');
        return 1;
    } else {
        return 0;
    }
}

static void primaryexp (LexState *ls) {
  /* primaryexp ->
        prefixexp { `.' NAME | `[' exp `]' | `:' NAME funcargs | funcargs } */
  int line = ls->linenumber;
  RETURNS_1(prefixexp(ls));
  Position p = getposition(ls);
  for (;;) {
    switch (ls->t.token) {
      case '.': {  /* fieldsel */
        luaX_next(ls);
        checksymbol(ls,NULL);
        new_object(ls,"selectu",2,&p);
        break;
      }
      case '[': {  /* `[' exp1 `]' */
        if(issplitprimary(ls))
            return;
        RETURNS_1(yindex(ls));
        new_object(ls,"index",2,&p);
        break;
      }
      case ':': {  /* `:' NAME funcargs */
        luaX_next(ls);
        RETURNS_1(checksymbol(ls,NULL));
        RETURNS_1(funcargs(ls, line));
        new_object(ls,"method",3,&p);
        break;
      }
      case '(': case '`': case TK_QUOTE: /* funcargs */
        if(issplitprimary(ls))
            return;
        /* fallthrough */
      case TK_STRING: case '{': {
        RETURNS_1(funcargs(ls, line));
        new_object(ls,"apply",2,&p);
        break;
      }
      default: return;
    }
  }
}

//TODO: eventually we should record the set of possibly used symbols, and only quote the ones appearing in it
static void print_captured_locals(LexState * ls, TerraCnt * tc) {
    OutputBuffer_printf(&ls->output_buffer,"function() return terra.makeenv({ ");
    int in_terra = ls->in_terra;
    ls->in_terra = 1; //force new_table, etc to do something, not the cleanest way to express this...
    int tbl = new_table(ls);
    for(StringSet::iterator i = tc->capturedlocals.begin(), end = tc->capturedlocals.end();
        i != end;
        ++i) {
        TString * iv = *i;
        const char * str = getstr(iv);
        lua_pushboolean(ls->L,true);
        add_field(ls,tbl,str);
        OutputBuffer_printf(&ls->output_buffer,"%s = %s;",str,str);
    }
    int defined = store_value(ls);
    ls->in_terra = in_terra;
    OutputBuffer_printf(&ls->output_buffer," },_G.terra._trees[%d],getfenv()) end",defined);
}

static void doquote(LexState * ls, int isexp) {
    int isfullquote = ls->t.token == '`' || ls->t.token == TK_QUOTE;
    
    check_no_terra(ls, isexp ? "`" : "quote");
    
    TerraCnt tc;
    enterterra(ls, &tc);
    Token begin = ls->t;
    int line = ls->linenumber;
    if(isfullquote)
        luaX_next(ls); //skip ` or quote
    if(isexp) {
        RETURNS_1(expr(ls));
    } else {
        FuncState * fs = ls->fs;
        BlockCnt bc;
        enterblock(fs, &bc, 0);
        Position p = getposition(ls);
        RETURNS_1(statlist(ls));
        if(isfullquote && testnext(ls, TK_IN)) {
            RETURNS_1(explist(ls));
        } else {
            new_list(ls);
        }
        push_boolean(ls, true);
        if(isfullquote)
            check_match(ls, TK_END, TK_QUOTE, line);
        leaveblock(fs);
        new_object(ls,"letin",3,&p);
    }
    
    luaX_patchbegin(ls,&begin);
    int id = store_value(ls);
    OutputBuffer_printf(&ls->output_buffer,"(terra.definequote(_G.terra._trees[%d],",id);
    print_captured_locals(ls,&tc);
    OutputBuffer_printf(&ls->output_buffer,"))");
    luaX_patchend(ls,&begin);
    leaveterra(ls);
}

//buf should be at least 128 chars
static void number_type(LexState * ls, int flags, char * buf) {
    if(ls->in_terra) {
      if(flags & F_ISINTEGER) {
        const char * sign = (flags & F_ISUNSIGNED) ? "u" : "";
        const char * sz = (flags & F_IS8BYTES) ? "64" : "";
        sprintf(buf,"%sint%s",sign,sz);
      } else {
        sprintf(buf,"%s",(flags & F_IS8BYTES) ? "double" : "float");
      }
    }
}

static void blockescape(LexState * ls) {
    check_terra(ls, "escape");
    int line = ls->linenumber;
    luaX_next(ls);
    embeddedcode(ls,0,0);
    check_match(ls, TK_END, TK_ESCAPE, line);
}

static void bodyortype(LexState * ls, int ismethod) {
    if(ls->t.token == '(') {
        body(ls, ismethod, ls->linenumber);
    } else {
        checknext(ls, TK_DBCOLON);
        terratype(ls);
    }
}

static void simpleexp (LexState *ls) {
  /* simpleexp -> NUMBER | STRING | NIL | TRUE | FALSE | ... |
                  constructor | FUNCTION body | primaryexp */
  switch (ls->t.token) {
    case TK_NUMBER: {
      char buf[128];
      int flags = ls->t.seminfo.flags;
      number_type(ls, flags, &buf[0]);
      if(flags & F_ISINTEGER) {
        push_integer(ls,ls->t.seminfo.i);
        push_literal(ls,buf);
        sprintf(buf,"%" PRIu64,ls->t.seminfo.i);
        push_string(ls,buf);
        add_field(ls,-2,"stringvalue");
        
      } else {
        push_double(ls,ls->t.seminfo.r);
        push_literal(ls, buf);
      }
      break;
    }
    case TK_STRING: {
      push_string(ls,ls->t.seminfo.ts);
      push_literal(ls,"rawstring");
      break;
    }
    case TK_NIL: {
      if(ls->in_terra)
        lua_pushnil(ls->L);
      push_literal(ls,"niltype");
      break;
    }
    case TK_TRUE: {
      //init_exp(v, VTRUE, 0);
      push_boolean(ls,true);
      push_literal(ls,"bool");
      break;
    }
    case TK_FALSE: {
      push_boolean(ls,false);
      push_literal(ls,"bool");
      break;
    }
    case TK_DOTS: {  /* vararg */
      FuncState *fs = ls->fs;
      check_condition(ls, fs->f.is_vararg,
                      "cannot use " LUA_QL("...") " outside a vararg function");
      break;
    }
    case '{': {  /* constructor */
      constructor(ls);
      return;
    }
    case '`': case TK_QUOTE: { /* quote expression */
        doquote(ls,ls->t.token == '`');
        return;
    }
    case TK_ESCAPE: {
        blockescape(ls);
        return;
    }
    case TK_FUNCTION: {
      luaX_next(ls);
      body(ls, 0, ls->linenumber);
      return;
    }
    case TK_TERRA: {
        check_no_terra(ls,"nested terra functions");
        
        TerraCnt tc;
        enterterra(ls, &tc);
        Token begin = ls->t;
        luaX_next(ls);
        bodyortype(ls,0);
        luaX_patchbegin(ls,&begin);
        int id = store_value(ls);
        OutputBuffer_printf(&ls->output_buffer,"terra.anonfunction(_G.terra._trees[%d],",id);
        print_captured_locals(ls,&tc);
        OutputBuffer_printf(&ls->output_buffer,")");
        luaX_patchend(ls,&begin);
        leaveterra(ls);
        return;
    }
    case TK_SPECIAL: {
        languageextension(ls, 0, 0);
        return;
    }
    case TK_STRUCT: {
        check_no_terra(ls,"struct declarations");
        Token begin = ls->t;
        
        luaX_next(ls); //skip over struct, struct constructor expects it to be parsed already
        
        
        TerraCnt tc;
        enterterra(ls, &tc);
        
        structconstructor(ls);
        int id = store_value(ls);
    
        luaX_patchbegin(ls,&begin);
        OutputBuffer_printf(&ls->output_buffer,"terra.anonstruct(_G.terra._trees[%d],",id);
        print_captured_locals(ls,&tc);
        OutputBuffer_printf(&ls->output_buffer,")");
        luaX_patchend(ls,&begin);
        
        leaveterra(ls);
        return;
    } break;
    default: {
      primaryexp(ls);
      return;
    }
  }
  luaX_next(ls);
}

/*
** grep "ORDER OPR" if you change these enums  (ORDER OP)
*/
typedef enum BinOpr {
  OPR_ADD, OPR_SUB, OPR_MUL, OPR_DIV, OPR_MOD, 
  OPR_POW, OPR_CONCAT,
  OPR_LSHIFT, OPR_RSHIFT,
  OPR_EQ, OPR_LT, OPR_LE,
  OPR_NE, OPR_GT, OPR_GE,
  OPR_AND, OPR_OR,
  OPR_FUNC_PTR,
  OPR_NOBINOPR
} BinOpr;


typedef enum UnOpr { OPR_MINUS, OPR_NOT, OPR_LEN, OPR_DEREF, OPR_ADDR, OPR_NOUNOPR } UnOpr;

static UnOpr getunopr (int op) {
  switch (op) {
    case TK_NOT: return OPR_NOT;
    case '-': return OPR_MINUS;
    case '#': return OPR_LEN;
    case '&': return OPR_ADDR;
    case '@': return OPR_DEREF;
    default: return OPR_NOUNOPR;
  }
}


static BinOpr getbinopr (int op) {
  switch (op) {
    case '+': return OPR_ADD;
    case '-': return OPR_SUB;
    case '*': return OPR_MUL;
    case '/': return OPR_DIV;
    case '%': return OPR_MOD;
    case '^': return OPR_POW;
    case TK_CONCAT: return OPR_CONCAT;
    case TK_NE: return OPR_NE;
    case TK_EQ: return OPR_EQ;
    case '<': return OPR_LT;
    case TK_LE: return OPR_LE;
    case '>': return OPR_GT;
    case TK_GE: return OPR_GE;
    case TK_AND: return OPR_AND;
    case TK_OR: return OPR_OR;
    case TK_FUNC_PTR: return OPR_FUNC_PTR;
    case TK_LSHIFT: return OPR_LSHIFT;
    case TK_RSHIFT: return OPR_RSHIFT;
    default: return OPR_NOBINOPR;
  }
}
static void check_lua_operator(LexState * ls, int op) {
    switch(op) {
        case '@': case TK_LSHIFT: case TK_RSHIFT:
            if(!ls->in_terra)
                luaX_syntaxerror(ls,luaS_cstringf(ls->LP,"@, <<, and >> operators not supported in Lua code."));
            break;
        case '#':
            if(ls->in_terra)
                luaX_syntaxerror(ls,luaS_cstringf(ls->LP,"# operator not supported in Terra code."));
            break;
        default:
            break;
    }
}

static const struct {
  lu_byte left;  /* left priority for each binary operator */
  lu_byte right; /* right priority */
} priority[] = {  /* ORDER OPR */
   {7, 7}, {7, 7}, {8, 8}, {8, 8}, {8, 8},  /* `+' `-' `*' `/' `%' */
   {11, 10}, {6, 5},                 /* ^, .. (right associative) */
   {4, 4}, {4, 4},                   /* << >> */
   {3, 3}, {3, 3}, {3, 3},          /* ==, <, <= */
   {3, 3}, {3, 3}, {3, 3},          /* ~=, >, >= */
   {2, 2}, {1, 1},                  /* and, or */
   {3,2}                           /* function pointer*/
};

#define UNARY_PRIORITY  9  /* priority for unary operators */


/*
** subexpr -> (simpleexp | unop subexpr) { binop subexpr }
** where `binop' is any binary operator with a priority higher than `limit'
*/
static BinOpr subexpr (LexState *ls, int limit) {
  BinOpr op;
  UnOpr uop;
  enterlevel(ls);
  uop = getunopr(ls->t.token);
  check_lua_operator(ls,ls->t.token);
  Token begintoken = ls->t;
  
  if (uop != OPR_NOUNOPR) {
    Position p = getposition(ls);
    push_string(ls,luaX_token2rawstr(ls,ls->t.token));
    luaX_next(ls);
    Token beginexp = ls->t;
    int exps = new_list(ls);
    RETURNS_1(subexpr(ls, UNARY_PRIORITY));
    add_entry(ls,exps);
    
    if(uop == OPR_ADDR) { //desugar &a to terra.types.pointer(a)
        const char * expstring = luaX_saveoutput(ls, &beginexp);
        luaX_patchbegin(ls, &begintoken);
        OutputBuffer_printf(&ls->output_buffer,"terra.types.pointer(%s)", expstring);
        luaX_patchend(ls, &begintoken);
    }
    new_object(ls, "operator", 2, &p);
  }
  else RETURNS_1(simpleexp(ls));
  /* expand while operators have priorities higher than `limit' */
  
  op = getbinopr(ls->t.token);
  const char * lhs_string = NULL;
  if(op == OPR_FUNC_PTR) {
    lhs_string = luaX_saveoutput(ls,&begintoken);
    //leading whitespace will be included before the token, so skip it here
    while(isspace(*lhs_string))
      lhs_string++;
  }
  while (op != OPR_NOBINOPR && priority[op].left > limit) {
    check_lua_operator(ls,ls->t.token);
    BinOpr nextop;
    int exps = new_list_before(ls);
    add_entry(ls,exps); //add prefix to operator list
    Position pos = getposition(ls);
    
    const char * token = luaX_token2rawstr(ls,ls->t.token);
    luaX_next(ls);
    Token beginrhs = ls->t;
    /* read sub-expression with higher priority */
    RETURNS_1(nextop = subexpr(ls, priority[op].right));
    
    if(lhs_string) { //desugar a -> b to terra.types.functype(a,b)
        const char * rhs_string = luaX_saveoutput(ls,&beginrhs);
        luaX_patchbegin(ls, &begintoken);
        OutputBuffer_printf(&ls->output_buffer,"terra.types.funcpointer(%s,%s)",lhs_string,rhs_string);
        luaX_patchend(ls,&begintoken);
        lhs_string = NULL;
    }
    add_entry(ls,exps);
    
    push_string_before(ls,token);
    
    new_object(ls,"operator",2,&pos);
    
    op = nextop;
  }
  leavelevel(ls);
  return op;  /* return first untreated operator */
}


static void expr (LexState *ls) {
  RETURNS_1(subexpr(ls, 0));
}


struct ExprReaderData {
    int step;
    const char * data;
    int N;
};
const char * expr_reader(lua_State * L, void * data, size_t * size) {
    ExprReaderData * d = (ExprReaderData *) data;
    if(d->step == 0) {
        const char * ret = "return ";
        *size = strlen(ret);
        d->step++;
        return ret;
    } else if(d->step == 1) {
        d->step++;
        *size = d->N;
        return d->data;
    } else {
        *size = 0;
        return NULL;
    }
}


static void embeddedcode(LexState * ls, int isterra, int isexp) {
    assert(ls->in_terra);
    
    //terra types are lua expressions.
    //to resolve them we stop processing terra code and start processing lua code
    //we capture the string of lua code and then evaluate it later to get the actual type
    Position pos = getposition(ls);
    Token begintoken = ls->t;
    int in_terra = ls->in_terra;
    
    ls->in_terra = 0;
    FuncState * fs = ls->fs;
    BlockCnt bl;
    enterblock(ls->fs, &bl, 0);
    
    if(isterra) {
        doquote(ls,isexp);
    } else if(isexp)
        expr(ls);
    else
        statlist(ls);
    leaveblock(fs);
    ls->in_terra = in_terra;
    
    ExprReaderData data;
    data.step = (isexp || isterra) ? 0 : 1; //is the string we captured an expression? it is if we captured a quote (terra.definequote(...)) or a lua expression
    luaX_getoutput(ls, &begintoken, &data.data, &data.N);
    std::stringstream ss;
    ss << "@$terra$" << getstr(ls->source) << "$terra$" << begintoken.seminfo.linebegin;
    if(lua_load(ls->L, expr_reader, &data, ss.str().c_str()) != 0) {
        //we already parsed this buffer, so this should rarely cause an error
        //we need to find the line number in the error string, add it to where we began this line,
        //and then report the error with the correct line number
        const char * error = luaL_checkstring(ls->L, -1);
        while(*error != ':')
            error++;
        char * aftererror;
        int lineoffset = strtol(error+1,&aftererror,10);
        
        luaX_reporterror(ls, luaS_cstringf(ls->LP,"%s:%d: %s\n",getstr(ls->source),begintoken.seminfo.linebegin + lineoffset - 1,aftererror+1));
    }
    
    push_boolean(ls, isexp);
    new_object(ls,"luaexpression",2,&pos);
}

static void luaexpr(LexState * ls) {
    embeddedcode(ls,0, 1);
}

static void terratype(LexState * ls) {
  luaexpr(ls);
}

/* }==================================================================== */



/*
** {======================================================================
** Rules for Statements
** =======================================================================
*/


static void block (LexState *ls) {
  /* block -> statlist */
  FuncState *fs = ls->fs;
  BlockCnt bl;
  Position p = getposition(ls);
  
  enterblock(fs, &bl, 0);
  RETURNS_1(statlist(ls));
  leaveblock(fs);
  
  new_object(ls,"block",1,&p);
}

static void lhsexp(LexState * ls) {
    if(ls->t.token == '@') {
        expr(ls);
    } else {
        primaryexp(ls);
    }
}

static void assignment (LexState *ls, int nvars, int lhs) {
  if (testnext(ls, ',')) {  /* assignment -> `,' primaryexp assignment */
    RETURNS_1(lhsexp(ls));
    add_entry(ls,lhs);
    checklimit(ls->fs, nvars + ls->LP->nCcalls, LUAI_MAXCCALLS, "C levels");
    RETURNS_0(assignment(ls, nvars+1,lhs));
  } else {  /* assignment -> `=' explist */
    checknext(ls, '=');
    Position pos = getposition(ls);
    RETURNS_1(explist(ls));
    new_object(ls,"assignment",2,&pos);
  }
}


static void cond (LexState *ls) {
  /* cond -> exp */
  RETURNS_1(expr(ls));  /* read condition */
}


static void gotostat (LexState *ls) {
  Position pos = getposition(ls);
  if (testnext(ls, TK_GOTO)) {
    checksymbol(ls,NULL);
    new_object(ls,"gotostat",1,&pos);
  } else {
    new_object(ls,"breakstat",0,&pos);
    luaX_next(ls);  /* skip break */
  }

}

static void labelstat (LexState *ls) {
  check_terra(ls,"goto labels");
  /* label -> '::' NAME '::' */
  Position pos = getposition(ls);
  RETURNS_1(checksymbol(ls,NULL));
  checknext(ls, TK_DBCOLON);  /* skip double colon */
  new_object(ls,"label",1,&pos);
}


static void whilestat (LexState *ls, int line) {
  /* whilestat -> WHILE cond DO block END */
  FuncState *fs = ls->fs;
  Position pos = getposition(ls);
  BlockCnt bl;
  luaX_next(ls);  /* skip WHILE */
  RETURNS_1(cond(ls));
  enterblock(fs, &bl, 1);
  checknext(ls, TK_DO);
  RETURNS_1(block(ls));
  check_match(ls, TK_END, TK_WHILE, line);
  leaveblock(fs);
  new_object(ls,"whilestat",2,&pos);
}


static void repeatstat (LexState *ls, int line) {
  /* repeatstat -> REPEAT block UNTIL cond */
  FuncState *fs = ls->fs;
  BlockCnt bl1, bl2;
  enterblock(fs, &bl1, 1);  /* loop block */
  enterblock(fs, &bl2, 0);  /* scope block */
  luaX_next(ls);  /* skip REPEAT */
  int stmts = new_list(ls);
  Position pos = getposition(ls);
  
  RETURNS_1(statlist(ls));
  check_match(ls, TK_UNTIL, TK_REPEAT, line);
  RETURNS_1(cond(ls));
  
  leaveblock(fs);  /* finish scope */
  leaveblock(fs);  /* finish loop */
  new_object(ls,"repeatstat",2,&pos);
  add_entry(ls, stmts);
  new_object(ls,"block",1,&pos);
}

static void forbody (LexState *ls, int line, int isnum, BlockCnt * bl) {
  /* forbody -> DO block */
  FuncState *fs = ls->fs;
  checknext(ls, TK_DO);
  enterblock(fs, bl, 0);  /* scope for declared variables */
  RETURNS_1(block(ls));
  leaveblock(fs);  /* end of scope for declared variables */
}

static void fornum (LexState *ls, TString *varname, Position * p) {
  /* fornum -> NAME = exp1,exp1[,exp1] forbody */
  checknext(ls, '=');
  RETURNS_1(expr(ls));  /* initial value */
  checknext(ls, ',');
  RETURNS_1(expr(ls));  /* limit */
  if (testnext(ls, ',')) {
    RETURNS_1(expr(ls));  /* optional step */
  } else {
    push_nil(ls);
  }
  BlockCnt bl;
  if(varname)
    definevariable(ls, varname);
  RETURNS_1(forbody(ls, p->linenumber, 1, &bl));
  new_object(ls,"fornumu",5,p);
  int blk = new_list_before(ls);
  add_entry(ls, blk);
  new_object(ls, "block", 1, p);
}


static void forlist (LexState *ls, TString *indexname, Position * p) {
  /* forlist -> NAME {,NAME} IN explist forbody */
  int vars = new_list_before(ls);
  add_entry(ls,vars);
  /* create declared variables */
  BlockCnt bl;
  if(indexname)
    definevariable(ls, indexname);
  
  while (testnext(ls, ',')) {
    TString * name;
    if(vardecl(ls, 0, &name))
      definevariable(ls,name);
    add_entry(ls,vars);
  }
  checknext(ls, TK_IN);
  int line = ls->linenumber;
  if(ls->in_terra)
    RETURNS_1(expr(ls));
  else
    RETURNS_1(explist(ls));
  RETURNS_1(forbody(ls, line, 0, &bl));
  new_object(ls,"forlist",3,p);
}

static void forstat (LexState *ls, Position * p) {
  /* forstat -> FOR (fornum | forlist) END */
  FuncState *fs = ls->fs;
  TString *varname = NULL;
  BlockCnt bl;
  enterblock(fs, &bl, 1);  /* scope for loop and control variables */
  luaX_next(ls);  /* skip `for' */
  
  vardecl(ls, 0, &varname);
  
  switch (ls->t.token) {
    case '=': RETURNS_0(fornum(ls, varname, p)); break;
    case ',': case TK_IN: RETURNS_0(forlist(ls, varname,p)); break;
    default: luaX_syntaxerror(ls, LUA_QL("=") " or " LUA_QL("in") " expected");
  }
  check_match(ls, TK_END, TK_FOR, p->linenumber);
  leaveblock(fs);  /* loop scope (`break' jumps to this point) */
}

static void test_then_block (LexState *ls) {
  /* test_then_block -> [IF | ELSEIF] cond THEN block */
  BlockCnt bl;
  luaX_next(ls);  /* skip IF or ELSEIF */
  Position p = getposition(ls);
  RETURNS_1(cond(ls));  /* read condition */
  checknext(ls, TK_THEN);
  RETURNS_1(block(ls));
  new_object(ls,"ifbranch",2,&p);
}

static void ifstat (LexState *ls, int line) {
  /* ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END */
  Position p = getposition(ls);
  int branches = new_list(ls);
  RETURNS_1(test_then_block(ls));  /* IF cond THEN block */
  add_entry(ls,branches);
  while (ls->t.token == TK_ELSEIF) {
    RETURNS_1(test_then_block(ls));  /* ELSEIF cond THEN block */
    add_entry(ls,branches);
  }
  if (testnext(ls, TK_ELSE)) {
    RETURNS_1(block(ls));  /* `else' part */ 
  } else push_nil(ls);
  check_match(ls, TK_END, TK_IF, line);
  new_object(ls,"ifstat",2,&p);
}

static void localfunc (LexState *ls) {
  TString * name = str_checkname(ls);
  definevariable(ls, name);
  body(ls, 0, ls->linenumber);  /* function created in next register */
  /* debug information will only see the variable after this point! */
  
}

void print_name_list(LexState * ls, std::vector<Name> * definednames) {
    for(size_t i = 0; i < definednames->size(); i++) {
        Name_print(&(*definednames)[i], ls);
        if(i + 1 < definednames->size())
            OutputBuffer_putc(&ls->output_buffer, ',');
    }
}

static void localstat (LexState *ls) {
  /* stat -> LOCAL NAME {`,' NAME} [`=' explist] */
  Position p = getposition(ls);
  int vars = new_list(ls);
  std::vector<TString *> declarednames;
  do {
    TString * vname;
    if(vardecl(ls, 0, &vname))
      declarednames.push_back(vname);
    add_entry(ls,vars);
  } while (testnext(ls, ','));
  if (testnext(ls, '=')) {
    push_boolean(ls,true);
    RETURNS_1(explist(ls));
  } else {
    push_boolean(ls,false);
    new_list(ls);
  }
  for(size_t i = 0; i < declarednames.size(); i++) {
    definevariable(ls, declarednames[i]);
  }
  new_object(ls,"defvar",3,&p);
}

static int funcname (LexState *ls) {
  /* funcname -> NAME {fieldsel} [`:' NAME] */
  int ismethod = 0;
  TString * vname = str_checkname(ls);
  refvariable(ls, vname);
  while(testnext(ls,'.')) {
    str_checkname(ls);
  }
  if (testnext(ls,':')) {
    ismethod = 1;
    str_checkname(ls);
  }
  return ismethod;
}

static void dump(LexState * ls) {
    lua_State * L = ls->L;
    printf("object is:\n");
    int tree = lua_gettop(L);
    lua_getfield(L,LUA_GLOBALSINDEX,"terra");
    lua_getfield(L,-1,"tree");
    lua_getfield(L,-1,"printraw");
    lua_pushvalue(L, tree);
    lua_call(L, 1, 0);
    
    lua_pop(L,2);
}


static void funcstat (LexState *ls, int line) {
  /* funcstat -> FUNCTION funcname body */
  luaX_next(ls);  /* skip FUNCTION */
  int ismethod = funcname(ls);
  body(ls, ismethod, line);
}

static int terraname (LexState *ls, int islocal, int token, Name * name) {
  /* funcname -> NAME {fieldsel} [`:' NAME] */
  int ismethod = 0;
  
  TString * vname = str_checkname(ls);
  Name_add(name,vname);
  
  if(!islocal) {
    while(testnext(ls,'.')) {
      TString * vname = str_checkname(ls);
      Name_add(name,vname);
    }
    if (TK_TERRA == token && testnext(ls,':')) {
      ismethod = 1;
      TString * vname = str_checkname(ls);
      Name_add(name,vname);
    }
  }
  
  return ismethod;
}

struct TDefn {
    char kind; //'f'unction 'm'ethod 's'truct
    int treeid; //-1 indicates no tree
    int islocal;
};
bool startsTerraStat(LexState * ls) {
    if(ls->t.token == TK_TERRA || ls->t.token == TK_STRUCT)
        return true;
    if(ls->t.token == TK_LOCAL) {
        luaX_lookahead(ls);
        return ls->lookahead.token == TK_TERRA || ls->lookahead.token == TK_STRUCT;
    } else return false;
}

static void terrastats(LexState * ls, bool emittedlocal) {
    Token begin = ls->t;
    
    std::vector<Name> names;
    std::vector<TDefn> defs;
    size_t nlocals = 0;
    
    TerraCnt tc;
    
    enterterra(ls, &tc);
    
    bool islocal = emittedlocal;
    for(int idx = 0; true; idx++) {
        int token = ls->t.token;
        luaX_next(ls); /* consume starting token */
        names.push_back(Name());
        Name * name = &names.back();
        int ismethod = terraname(ls, islocal, token, name);
        if(islocal)
            nlocals++;
        else
            refvariable(ls,name->data[0]); //non-local names are references because we look up old value
        TDefn tdefn; tdefn.treeid = -1; tdefn.islocal = islocal;
        switch(token) {
            case TK_TERRA: {
                tdefn.kind = ismethod ? 'm' : 'f';
                bodyortype(ls, ismethod);
                tdefn.treeid = store_value(ls);
            } break;
            case TK_STRUCT: {
                tdefn.kind = 's';
                if(ls->t.token == '{' || ls->t.token == '(') {
                    structconstructor(ls);
                    tdefn.treeid = store_value(ls);
                }
            } break;
        }
        defs.push_back(tdefn);
        if(!startsTerraStat(ls))
            break;
        islocal = testnext(ls, TK_LOCAL);
    }
    
    leaveterra(ls);
    
    luaX_patchbegin(ls,&begin);
    
    //print the new local names (if any) and define them in the local context
    if(!emittedlocal && nlocals > 0)
        OutputBuffer_printf(&ls->output_buffer, "local ");
    for(size_t i = 0,emitted = 0; i < names.size(); i++) {
        Name * name = &names[i];
        TString * firstname = name->data[0];
        if(defs[i].islocal) {
            Name_print(name, ls);
            definevariable(ls, firstname);
            tc.capturedlocals.insert(firstname); //capture these locals so that the constructor doesn't see old values
            if(++emitted < nlocals)
                OutputBuffer_putc(&ls->output_buffer, ',');
        }
    }
    if(nlocals > 0)
        OutputBuffer_putc(&ls->output_buffer, ';');
        
    bool hasreturns = false;
    for(size_t i = 0; i < names.size(); i++) {
        if(names[i].data.size() == 1) {
            if(hasreturns) OutputBuffer_putc(&ls->output_buffer, ',');
            Name_print(&names[i],ls);
            hasreturns = true;
        }
    }
    if(hasreturns)
        OutputBuffer_printf(&ls->output_buffer, " = ");
    OutputBuffer_printf(&ls->output_buffer, "terra.defineobjects(\"");
    for(size_t i = 0; i < defs.size(); i++)
        OutputBuffer_putc(&ls->output_buffer, defs[i].kind);
    OutputBuffer_printf(&ls->output_buffer, "\",");
    print_captured_locals(ls, &tc);
    for(size_t i = 0; i < defs.size(); i++) {
        Name * name = &names[i];
        OutputBuffer_printf(&ls->output_buffer, ", \"");
        Name_print(name,ls);
        OutputBuffer_printf(&ls->output_buffer, "\", _G.terra._trees[%d]",defs[i].treeid);
    }
    OutputBuffer_putc(&ls->output_buffer,')');
    luaX_patchend(ls,&begin);
}

static void exprstat (LexState *ls) {
  /* stat -> func | assignment */
  RETURNS_1(lhsexp(ls));
  if(ls->t.token != '=' && ls->t.token != ',')  { /* stat -> func */
    //nop
  } else {  /* stat -> assignment */
    int tbl = new_list_before(ls); //assignment list is put into a table
    add_entry(ls,tbl);
    RETURNS_0(assignment(ls, 1,tbl)); //assignment will replace this table with the actual assignment node
  }
}


static void retstat (LexState *ls) {
  /* stat -> RETURN [explist] [';'] */
  Position p = getposition(ls);
  new_list(ls); //empty statements
  if (block_follow(ls, 1) || ls->t.token == ';') {
    new_list(ls);
  } else {
    RETURNS_1(explist(ls));  /* optional return values */
  }
  push_boolean(ls, false); //has statements
  testnext(ls, ';');  /* skip optional semicolon */
  new_object(ls, "letin", 3, &p);
  new_object(ls,"returnstat",1,&p);
}


static void statement (LexState *ls) {
  Position p = getposition(ls);
  int line = p.linenumber;  /* may be needed for error messages */

  enterlevel(ls);
  
  switch (ls->t.token) {
    case TK_IF: {  /* stat -> ifstat */
      RETURNS_1(ifstat(ls, line));
      break;
    }
    case TK_WHILE: {  /* stat -> whilestat */
      RETURNS_1(whilestat(ls, line));
      break;
    }
    case TK_DO: {  /* stat -> DO block END */
      luaX_next(ls);  /* skip DO */
      RETURNS_1(block(ls));
      check_match(ls, TK_END, TK_DO, line);
      break;
    }
    case TK_FOR: {  /* stat -> forstat */
      //TODO: AST
      RETURNS_1(forstat(ls, &p));
      break;
    }
    case TK_REPEAT: {  /* stat -> repeatstat */
      RETURNS_1(repeatstat(ls, line));
      break;
    }
    case TK_FUNCTION: {  /* stat -> funcstat */
      check_no_terra(ls,"lua functions");
      funcstat(ls, line);
      break;
    }
    case TK_TERRA: case TK_STRUCT: {
      check_no_terra(ls, "terra declarations");
      terrastats(ls, false);
    } break;
    case TK_SPECIAL: {
        check_no_terra(ls, "language extensions");
        languageextension(ls, 1, 0);
    } break;
    case TK_LOCAL: {  /* stat -> localstat */
      luaX_next(ls);  /* skip LOCAL */
      check_no_terra(ls,"local keywords");
      if (testnext(ls, TK_FUNCTION)) { /* local function? */
        localfunc(ls);
      } else if(ls->t.token == TK_STRUCT || ls->t.token == TK_TERRA) {
        terrastats(ls, true);
      } else if(ls->t.token == TK_SPECIAL) {
        languageextension(ls, 1, 1);
      } else {
        localstat(ls);
      }
      break;
    }
    case TK_VAR: {
        check_terra(ls, "variables");
        luaX_next(ls); /* skip var */
        RETURNS_1(localstat(ls));
        break;  
    }
    case TK_DBCOLON: {  /* stat -> label */
      
      luaX_next(ls);  /* skip double colon */
      RETURNS_1(labelstat(ls));
      break;
    }
    case TK_RETURN: {  /* stat -> retstat */
      luaX_next(ls);  /* skip RETURN */
      RETURNS_1(retstat(ls));
      break;
    }
    case TK_BREAK:   /* stat -> breakstat */
    case TK_GOTO: {  /* stat -> 'goto' NAME */
      RETURNS_1(gotostat(ls));
      break;
    }
    case TK_IMPORT: {
      check_no_terra(ls, "import statements");
      Token begin = ls->t;
      luaX_next(ls);
      check(ls,TK_STRING);
      luaX_globalgetfield(ls, TA_TERRA_OBJECT, "importlanguage");
      luaX_globalpush(ls, TA_LANGUAGES_TABLE);
      luaX_globalpush(ls, TA_ENTRY_POINT_TABLE);
      lua_pushstring(ls->L, getstr(ls->t.seminfo.ts));
      ls->languageextensionsenabled++;
      ls->fs->bl->languageextensionsdefined++;
      
      if(lua_pcall(ls->L, 3, 0, 0)) {
        const char * str = luaL_checkstring(ls->L,-1);
        luaX_reporterror(ls, str);
      }
      luaX_next(ls); /* skip string */
      luaX_patchbegin(ls, &begin);
      OutputBuffer_printf(&ls->output_buffer, "do end");
      luaX_patchend(ls, &begin);
      break;
    }
    case TK_DEFER: {
        Position p = getposition(ls);
        luaX_next(ls);
        expr(ls);
        new_object(ls,"defer",1,&p);
        break;
    }
    case TK_ESCAPE: {
        blockescape(ls);
        break;
    }
      /*otherwise, fallthrough to the normal error message.*/
    default: {  /* stat -> func | assignment */
      RETURNS_1(exprstat(ls));
      break;
    }
  }
  leavelevel(ls);
}

static void le_handleerror(LexState * ls) {
  /* there was an error, it is on the top of the stack
       we need to call lua's error handler to rethrow the error. */
  ls->rethrow = 1; /* prevent languageextension from adding the context again */
  lua_error(ls->L); /* does not return */
}
static int le_next(lua_State * L) {
    LexState * ls = const_cast<LexState*>((const LexState *) lua_topointer(L,lua_upvalueindex(1)));
    try {
      luaX_next(ls);
    } catch(...) {
      le_handleerror(ls);
    }
    return 0;
}

static void converttokentolua(LexState * ls, Token * t) {
    lua_newtable(ls->L);
    switch(t->token) {
    case TK_NAME: {
        lua_getfield(ls->L,lua_upvalueindex(2),getstr(t->seminfo.ts));
        int iskeyword = !lua_isnil(ls->L,-1);
        lua_pop(ls->L,1);
        lua_pushstring(ls->L,getstr(t->seminfo.ts));
        if(!iskeyword) {
            lua_setfield(ls->L,-2,"value");
            lua_pushstring(ls->L,"<name>");
        }
        lua_setfield(ls->L,-2,"type");
    } break;
    case TK_STRING:
        lua_pushstring(ls->L,"<string>");
        lua_setfield(ls->L,-2,"type");
        lua_pushstring(ls->L,getstr(t->seminfo.ts));
        lua_setfield(ls->L,-2,"value");
        break;
    case TK_NUMBER: {
        char buf[128];
        lua_pushstring(ls->L,"<number>");
        lua_setfield(ls->L,-2,"type");
        int flags = t->seminfo.flags;
        number_type(ls, flags, &buf[0]);
        push_type(ls,buf);
        lua_setfield(ls->L,-2,"valuetype");
        if (flags & F_IS8BYTES && flags & F_ISINTEGER) {
            uint64_t * ip = (uint64_t*) lua_newuserdata(ls->L,sizeof(uint64_t));
            *ip = t->seminfo.i;
        } else {
            lua_pushnumber(ls->L,t->seminfo.r);
        }
        lua_setfield(ls->L,-2,"value");
    } break;
    case TK_SPECIAL:
        lua_pushstring(ls->L,getstr(t->seminfo.ts));
        lua_setfield(ls->L,-2,"type");
        break;
    case TK_EOS:
        lua_pushstring(ls->L,"<eos>");
        lua_setfield(ls->L,-2,"type");
        break;
    default:
        lua_pushstring(ls->L,luaX_token2rawstr(ls,t->token));
        lua_setfield(ls->L,-2,"type");
        break;
    }
}

static int le_cur(lua_State * L) {
    LexState * ls = const_cast<LexState*>((const LexState *) lua_topointer(L,lua_upvalueindex(1)));
    converttokentolua(ls, &ls->t);
    Position p = getposition(ls);
    table_setposition(ls, lua_gettop(ls->L), p);
    return 1;
}
static int le_lookahead(lua_State * L) {
    LexState * ls = const_cast<LexState*>((const LexState *) lua_topointer(L,lua_upvalueindex(1)));
    try {
      luaX_lookahead(ls);
      converttokentolua(ls, &ls->lookahead);
    } catch(...) {
      le_handleerror(ls);
    }
    return 1;
}

static int le_embeddedcode(lua_State * L) {
  LexState * ls = const_cast<LexState*>((const LexState *) lua_topointer(L,lua_upvalueindex(1)));
  bool isterra = lua_toboolean(L,1);
  bool isexp = lua_toboolean(L,2);
  try {
    embeddedcode(ls,isterra,isexp);
  } catch(...) {
    le_handleerror(ls);
  }
  lua_getfield(ls->L,-1,"expression");
  lua_remove(ls->L,-2); /* remove original object, we just want to return the function */
  return 1;
}

static void languageextension(LexState * ls, int isstatement, int islocal) {
    lua_State * L = ls->L;
    Token begin = ls->t;
    std::vector<Name> names;
    TerraCnt tc;
    
    enterterra(ls, &tc); //specifically to capture local variables, not for other reasons
    
    int top = lua_gettop(L);
    //setup call to the language
    
    luaX_globalgetfield(ls, TA_TERRA_OBJECT,"runlanguage");
    luaX_globalgetfield(ls, TA_ENTRY_POINT_TABLE, getstr(ls->t.seminfo.ts));
    
    lua_pushlightuserdata(ls->L,(void*)ls);
    lua_getfield(ls->L,-2,"keywordtable");
    lua_pushcclosure(ls->L,le_cur,2);
    
    lua_pushlightuserdata(ls->L,(void*)ls);
    lua_getfield(ls->L,-3,"keywordtable");
    lua_pushcclosure(ls->L,le_lookahead,2);
    
    lua_pushlightuserdata(ls->L,(void*)ls);
    lua_pushcclosure(ls->L,le_next,1);

    lua_pushlightuserdata(ls->L,(void*)ls);
    lua_pushcclosure(ls->L,le_embeddedcode,1);
    
    lua_pushstring(ls->L,getstr(ls->source));
    lua_pushboolean(ls->L,isstatement);
    lua_pushboolean(ls->L,islocal);
    
    if(lua_pcall(ls->L,8,3,0)) {
        const char * str = luaL_checkstring(ls->L,-1);
        if(ls->rethrow)
            luaX_reporterror(ls, str);
        else /* add line information */
            luaX_syntaxerror(ls, str);
    }
    
    /* register all references from user code */
    lua_pushnil(L);
    while (lua_next(L,-2) != 0) {
        size_t len;
        const char * str = lua_tolstring(L,-1,&len);
        refvariable(ls, luaS_newlstr(ls->LP,str,len));
        lua_pop(L,1);
    }
    
    lua_pop(L,1); /* remove _references list */
    
    //put names returned into names object
    
    lua_pushnil(L);
    while (lua_next(L, -2) != 0) {
        names.push_back(Name());
        lua_pushnil(L);
        while(lua_next(L,-2) != 0) {
            size_t len;
            const char * str = lua_tolstring(L,-1,&len);
            names.back().data.push_back(luaS_newlstr(ls->LP, str, len));
            lua_pop(L,1);
        }
        lua_pop(L, 1);
    }
    lua_pop(L,1); /* no longer need names, top of stack is now the user's function */
    
    //object on top of stack
    int n = store_value(ls);
    
    leaveterra(ls);
    
    //patch the thing into place
    
    luaX_patchbegin(ls,&begin);
    
    if(isstatement && names.size() > 0) {
        print_name_list(ls, &names);
        if(islocal) {
            for(size_t i = 0; i < names.size(); i++) {
                definevariable(ls, names[i].data[0]);
            }
        }
        OutputBuffer_printf(&ls->output_buffer," = ");
    }
    
    OutputBuffer_printf(&ls->output_buffer,"_G.terra._trees[%d](",n);
    print_captured_locals(ls,&tc);
    OutputBuffer_printf(&ls->output_buffer,")");
    luaX_patchend(ls,&begin);
    
    assert(lua_gettop(L) == top);
}

/* }====================================================================== */

static void cleanup(LexState * ls) {
    luaX_poptstringtable(ls->LP); //we can forget all the non-reserved strings
    OutputBuffer_free(&ls->output_buffer);
    if(ls->buff->buffer) {
        free(ls->buff->buffer);
        ls->buff->buffer = NULL;
    }
    free(ls->buff);
    ls->buff = NULL;
    if(ls->patchinfo.buffer) {
        free(ls->patchinfo.buffer);
        ls->patchinfo.buffer = NULL;
        ls->patchinfo.N = 0;
        ls->patchinfo.space = 0;
    }
    
    //clear the registry index entry for our state
    lua_pushlightuserdata(ls->L,&ls->lextable);
    lua_pushnil(ls->L);
    lua_rawset(ls->L,LUA_REGISTRYINDEX);
}

int luaY_parser (terra_State *T, ZIO *z,
                    const char *name, int firstchar) {
  (void)dump; //suppress warning for unused debugging functions
  (void)dump_stack; 
  (void)printtreesandnames;
  LexState lexstate;
  FuncState funcstate;
  //memset(&lexstate,0,sizeof(LexState));
  //memset(&funcstate,0,sizeof(FuncState));
  
  Mbuffer * buff = (Mbuffer*) malloc(sizeof(Mbuffer));
  memset(buff,0,sizeof(Mbuffer));
    
  luaX_pushtstringtable(T);
  
  BlockCnt bl;
  bl.previous = NULL;
  lua_State * L = T->L;
  lexstate.L = L;
  lexstate.in_terra = 0;
  lexstate.terracnt = NULL;
  TString *tname = (name[0] == '@') ? luaS_new(T, name + 1) : luaS_stringf(T,"[string \"%s\"]",name);
  lexstate.buff = buff;
  lexstate.n_lua_objects = 0;
  lexstate.rethrow = 0;
  OutputBuffer_init(&lexstate.output_buffer);
  if(!lua_checkstack(L,1 + LUAI_MAXCCALLS)) {
      abort();
  }
  lexstate.stacktop = lua_gettop(L);
  
  
  lua_pushlightuserdata(L,&lexstate.lextable);
  lua_newtable(L); /* lua state for lexer */
  lua_rawset(L,LUA_REGISTRYINDEX);
  
  lua_getfield(L,LUA_GLOBALSINDEX,"terra"); //TA_TERRA_OBJECT
  int to = lua_gettop(L);
  
  lua_pushvalue(L,-1);
  luaX_globalset(&lexstate, TA_TERRA_OBJECT);
  
  lua_getfield(L,to,"_trees");
  luaX_globalset(&lexstate, TA_FUNCTION_TABLE);
  
  
  lua_getfield(L,to,"irtypes");
  luaX_globalset(&lexstate, TA_TYPE_TABLE);
  
  lua_getfield(L,to,"newlist");
  luaX_globalset(&lexstate, TA_NEWLIST);
  
  lua_newtable(L);
  luaX_globalset(&lexstate, TA_ENTRY_POINT_TABLE);
  lua_newtable(L);
  luaX_globalset(&lexstate, TA_LANGUAGES_TABLE);
  lexstate.languageextensionsenabled = 0;
  
  lua_pop(L,1); /* remove gs and terra object from stack */
  
  assert(lua_gettop(L) == lexstate.stacktop);
  try {
    luaX_setinput(T, &lexstate, z, tname, firstchar);
    open_mainfunc(&lexstate, &funcstate, &bl);
    luaX_next(&lexstate);  /* read first token */
    statlist(&lexstate);  /* main body */
    check(&lexstate, TK_EOS);
    close_func(&lexstate);
    assert(!funcstate.prev && !lexstate.fs);
  } catch(int err) {
    cleanup(&lexstate);
    assert(lua_gettop(L) > lexstate.stacktop);
    if(lua_gettop(L) > lexstate.stacktop + 1) {
        lua_replace(L,lexstate.stacktop + 1); //put the error message at the new top of stack
        lua_settop(L, lexstate.stacktop + 1); //reset the stack to just 1 above where it orignally (holding the error message)
    }
    assert(lua_gettop(L) == lexstate.stacktop + 1);
    return err;
  }

  assert(lua_gettop(L) == lexstate.stacktop);
  
  /* all scopes should be correctly finished */
  OutputBuffer_putc(&lexstate.output_buffer,'\0');
  VERBOSE_ONLY(T) {
    printf("********* passing to lua ************\n%s\n*************************************\n",lexstate.output_buffer.data);
  }
  //loadbuffer doesn't like null terminators, so rewind to before them
  while(lexstate.output_buffer.data[lexstate.output_buffer.N-1] == '\0' && lexstate.output_buffer.N > 0) {
    lexstate.output_buffer.N--;
  }
  
  int err = luaL_loadbuffer(L, lexstate.output_buffer.data, lexstate.output_buffer.N, name);
  cleanup(&lexstate);
  
  return err;
}

