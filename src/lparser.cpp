/*
** $Id: lparser.c,v 2.124 2011/12/02 13:23:56 roberto Exp $
** Lua Parser
** See Copyright Notice in lua.h
*/


#include <string.h>
#include <assert.h>
#ifdef _WIN32
#include "ext/setjmp.h"
#else
#include <setjmp.h>
#endif

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
#include "tkind.h"
#include <vector>
#include <set>
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
        int t = new_table(ls); //printf("(new table)\n");
        luaX_globalpush(ls,TA_LIST_METATABLE);
        lua_setmetatable(ls->L,-2);
        return t;
    } else return 0;
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
static void push_kind(LexState * ls, const char * str) {
    if(ls->in_terra) {
        lua_pushstring(ls->L,str);
        luaX_globalgettable(ls,TA_KINDS_TABLE);
        assert(!lua_isnil(ls->L,-1));
    }
}
static void table_setposition(LexState * ls, int t, int line, int offset) {
    lua_pushinteger(ls->L,line);
    lua_setfield(ls->L,t,"linenumber");
    
    lua_pushinteger(ls->L,offset);
    lua_setfield(ls->L,t,"offset");
    
    lua_pushstring(ls->L, getstr(ls->source));
    lua_setfield(ls->L,t, "filename");
    
}
static int new_table(LexState * ls, T_Kind k) {
    if(ls->in_terra) {
        //printf("push %s ",str);
        int t = new_table(ls);
        lua_pushinteger(ls->L,k);
        add_field(ls, t,"kind");
        luaX_globalpush(ls, TA_TREE_METATABLE);
        lua_setmetatable(ls->L,-2);
        table_setposition(ls,t,ls->linenumber, ls->currentoffset - 1);
        return t;
    } else return 0;
}
static int new_table_before(LexState * ls, T_Kind k, bool infix = false) {
    lua_State * L = ls->L;
    if(ls->in_terra) {
        int t = new_table(ls,k);
        //check if the thing on the top of the stack has line number and offset info, if it does then propagate it to this entry
        if(!infix && lua_istable(L, -2)) {
            lua_getfield(L, -2, "linenumber");
            lua_getfield(L, -3, "offset");
            if(lua_isnumber(L, -1) && lua_isnumber(L,-2)) {
                int offset = lua_tointeger(L, -1);
                int linenumber = lua_tointeger(L, -2);
                table_setposition(ls,t,linenumber,offset);
            }
            lua_pop(L,2);
        }
        lua_insert(L,-2);
        return t - 1;
    } else return 0;
}

static int new_list_before(LexState * ls) {
    if(ls->in_terra) {
        int t = new_list(ls);
        lua_insert(ls->L,-2);
        return t - 1;
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
static void expr (LexState *ls, expdesc *v);
static void terratype(LexState * ls);
static void luaexpr(LexState * ls);
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

/* semantic error */
static l_noret semerror (LexState *ls, const char *msg) {
  ls->t.token = 0;  /* remove 'near to' from final message */
  luaX_syntaxerror(ls, msg);
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

static TString * singlevar (LexState *ls) {
  int tbl = new_table(ls,T_var); 
  TString *varname = str_checkname(ls);
  push_string(ls,varname);
  add_field(ls,tbl,"name");
  refvariable(ls, varname);
  return varname;
}

//tries to parse a symbol "NAME | '['' lua expression '']'"
//returns true if a name was parsed and sets str to that name
//otherwise, str is not modified
static bool checksymbol(LexState * ls, TString ** str) {
  int tbl = new_table(ls,T_symbol);
  int line = ls->linenumber;
  if(ls->in_terra && testnext(ls,'[')) {
    RETURNS_1(luaexpr(ls));
    add_field(ls, tbl, "expression");
    check_match(ls, ']', '[', line);
    return false;
  }
  TString * nm = str_checkname(ls);
  if(str)
    *str = nm;
  push_string(ls,nm);
  add_field(ls,tbl,"name");
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
  fs->bl = bl;
  //printf("entering block %lld\n", (long long int)bl);
  //printf("previous is %lld\n", (long long int)bl->previous);
}

static void breaklabel (LexState *ls) {

}

static void leaveblock (FuncState *fs) {
  BlockCnt *bl = fs->bl;
  LexState *ls = fs->ls;
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
  terra_State *L = ls->LP;
  Proto *f;
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
  terra_State *L = ls->LP;
  FuncState *fs = ls->fs;
  leaveblock(fs);
  ls->fs = fs->prev;
}


/*
** opens the main function, which is a regular vararg function with an
** upvalue named LUA_ENV
*/
static void open_mainfunc (LexState *ls, FuncState *fs, BlockCnt *bl) {
  //expdesc v;
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
    case TK_END: case TK_EOS:
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


static void fieldsel (LexState *ls) {
  /* fieldsel -> ['.' | ':'] NAME */
  FuncState *fs = ls->fs;
  expdesc key;
  luaX_next(ls);  /* skip the dot or colon */
  int tbl = new_table_before(ls,T_selectconst, true);
  add_field(ls,tbl,"value");
  push_string(ls,str_checkname(ls));
  add_field(ls,tbl,"field");
}

static void push_literal(LexState * ls, const char * typ) {
    if(ls->in_terra) {
        int lit = new_table_before(ls,T_literal);
        add_field(ls,lit,"value");
        lua_getglobal(ls->L,typ);
        add_field(ls,lit,"type");
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

static void yindex (LexState *ls, expdesc *v) {
  /* index -> '[' expr ']' */
  luaX_next(ls);  /* skip the '[' */
  
  RETURNS_1(expr(ls, v));  
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
  expdesc key, val;
  int tbl = new_table(ls,T_recfield);
  if (ls->t.token == TK_NAME) {
    checklimit(fs, cc->nh, MAX_INT, "items in a constructor");
    RETURNS_1(checksymbol(ls, NULL));
  }
  else  { /* ls->t.token == '[' */
    if(!ls->in_terra) {
      yindex(ls, &key);
    } else {
      checksymbol(ls,NULL);
      if(ls->t.token != '=') {
        /* oops! this wasn't a recfield, but a listfield with an antiquote 
           this is a somewhat unfortunate corner case of terra's parsing rules: we need to fix the AST now */
        lua_getfield(ls->L,-1,"expression");
        lua_remove(ls->L,-2); //remove the T_symbol, now we have { kind = recfield }, luaexpression
        add_field(ls,tbl,"value");
        //replace T_recfield with T_listfield
        push_double(ls,T_listfield);
        add_field(ls,tbl,"kind");
        return;        
      }
    }
  }
  add_field(ls,tbl,"key");
  cc->nh++;
  checknext(ls, '=');
  RETURNS_1(expr(ls, &val));
  add_field(ls,tbl,"value");
}

static void listfield (LexState *ls, struct ConsControl *cc) {
  /* listfield -> exp */
  expdesc val;
  int tbl = new_table(ls,T_listfield);
  RETURNS_1(expr(ls, &val));
  add_field(ls,tbl,"value");
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


static void constructor (LexState *ls, expdesc *t) {
  /* constructor -> '{' [ field { sep field } [sep] ] '}'
     sep -> ',' | ';' */
  FuncState *fs = ls->fs;
  int line = ls->linenumber;
  struct ConsControl cc;
  cc.na = cc.nh = 0;
  int tbl = new_table(ls,T_constructor);
  int records = new_list(ls);
  checknext(ls, '{');
  do {
    if (ls->t.token == '}') break;
    RETURNS_1(field(ls, &cc));
    add_entry(ls,records);
  } while (testnext(ls, ',') || testnext(ls, ';'));
  check_match(ls, '}', '{', line);
  add_field(ls,tbl,"records");
}


static void structconstructor(LexState * ls, T_Kind kind);


static void recstruct (LexState *ls) {
  int tbl = new_table(ls,T_structentry);
  push_string(ls,str_checkname(ls));
  add_field(ls,tbl,"key");
  checknext(ls, ':');
  RETURNS_1(terratype(ls));
  add_field(ls,tbl,"type");
}

static void liststruct (LexState *ls) {
  /* listfield -> exp */
  
  if(testnext(ls,TK_UNION)) {
    RETURNS_1(structconstructor(ls,T_union));
  } else {
    int tbl = new_table(ls,T_structentry);
    RETURNS_1(terratype(ls));
    add_field(ls,tbl,"type");
  }
}

static void structfield (LexState *ls) {
  /* field -> listfield | recfield */
  switch(ls->t.token) {
    case TK_NAME: {  /* may be 'listfield' or 'recfield' */
      if (luaX_lookahead(ls) != ':')  /* expression? */
        liststruct(ls);
      else
        recstruct(ls);
      break;
    }
    default: {
      liststruct(ls);
      break;
    }
  }
}

static void structconstructor(LexState * ls, T_Kind kind) {
    // already parsed 'struct' or 'struct' name.
    //starting at '{'
    int line = ls->linenumber;
    int tbl = new_table(ls,kind);
    int records = new_list(ls);
    checknext(ls,'{');
    do {
       if (ls->t.token == '}') break;
       RETURNS_1(structfield(ls));
       add_entry(ls,records);
    } while(testnext(ls, ',') || testnext(ls, ';'));
    check_match(ls,'}','{',line);
    add_field(ls,tbl,"records");
}

struct Name {
    std::vector<TString *> data; //for patching the [local] terra a.b.c.d, and [local] var a.b.c.d sugar
};

static void Name_add(Name * name, TString * string) {
    name->data.push_back(string);
}

static void Name_print(Name * name, LexState * ls, int subname = 0) {
    size_t N = name->data.size() + subname;
    for(size_t i = 0; i < N; i++) {
        OutputBuffer_printf(&ls->output_buffer,"%s",getstr(name->data[i]));
        if(i + 1 < N)
             OutputBuffer_putc(&ls->output_buffer, '.');
    }
}

static void print_captured_locals(LexState * ls, TerraCnt * tc);

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

static void parlist (LexState *ls) {
  /* parlist -> [ param { `,' param } ] */
  FuncState *fs = ls->fs;
  Proto *f = &fs->f;
  int tbl = new_list(ls);
  int nparams = 0;
  f->is_vararg = 0;
  std::vector<TString *> vnames;
  if (ls->t.token != ')') {  /* is `parlist' not empty? */
    do {
      switch (ls->t.token) {
        case TK_NAME: case '[': {  /* param -> NAME */
          expdesc e;
          int entry = new_table(ls,T_entry);
          TString * vname;
          int wasstring = checksymbol(ls,&vname);
          add_field(ls,entry,"name");
          if(vname)
            vnames.push_back(vname);
          if(ls->in_terra && (wasstring || ls->t.token == ':')) {
            checknext(ls,':');
            RETURNS_1(terratype(ls));
            add_field(ls,entry,"type");
          }
          add_entry(ls,tbl);
          nparams++;
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

static void body (LexState *ls, expdesc *e, int ismethod, int line) {
  /* body ->  `(' parlist `)' block END */
  FuncState new_fs;
  BlockCnt bl;
  open_func(ls, &new_fs, &bl);
  new_fs.f.linedefined = line;
  checknext(ls, '(');
  int tbl = new_table(ls,T_function);
  RETURNS_1(parlist(ls));
  if (ismethod) {
    definevariable(ls, luaS_new(ls->LP,"self"));
  }
  add_field(ls,tbl,"parameters");
  push_boolean(ls,new_fs.f.is_vararg);
  add_field(ls,tbl,"is_varargs");
  checknext(ls, ')');
  if(ls->in_terra && testnext(ls,':')) {
    RETURNS_1(terratype(ls));
    add_field(ls,tbl,"return_types");
  }
  int blk = new_table(ls,T_block);
  RETURNS_1(statlist(ls));
  add_field(ls,blk,"statements");
  add_field(ls,tbl,"body");
  new_fs.f.lastlinedefined = ls->linenumber;
  check_match(ls, TK_END, TK_FUNCTION, line);
  //codeclosure(ls, new_fs.f, e);
  
  close_func(ls);
}

static int explist (LexState *ls, expdesc *v) {
  /* explist -> expr { `,' expr } */
  int n = 1;  /* at least one expression */
  int lst = new_list(ls);
  expr(ls, v);
  add_entry(ls,lst);
  while (testnext(ls, ',')) {
    //luaK_exp2nextreg(ls->fs, v);
    expr(ls, v);
    add_entry(ls,lst);
    n++;
  }
  return n;
}


static void funcargs (LexState *ls, expdesc *f, int line) {
  FuncState *fs = ls->fs;
  expdesc args;
  int base, nparams;
  switch (ls->t.token) {
    case '(': {  /* funcargs -> `(' [ explist ] `)' */
      luaX_next(ls);
      if (ls->t.token == ')') {  /* arg list is empty? */
        new_list(ls); //empty return list
      } else {
        RETURNS_1(explist(ls, &args));
      }
      check_match(ls, ')', '(', line);
      break;
    }
    case '{': {  /* funcargs -> constructor */
      int exps = new_list(ls);
      RETURNS_1(constructor(ls, &args));
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

static void prefixexp (LexState *ls, expdesc *v) {
  /* prefixexp -> NAME | '(' expr ')' */
  
  switch (ls->t.token) {
    case '(': {
      int line = ls->linenumber;
      luaX_next(ls);
      RETURNS_1(expr(ls, v));
      check_match(ls, ')', '(', line);
      if(ls->in_terra) {
        //if an call was parenthesized, mark it truncated
        //so that it only returns one argument
        int tbl = new_table_before(ls, T_truncate);
        add_field(ls, tbl, "value");
      }
      //luaK_dischargevars(ls->fs, v);
      return;
    }
    case '[': {
      check_terra(ls, "antiquotation");
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

static void primaryexp (LexState *ls, expdesc *v) {
  /* primaryexp ->
        prefixexp { `.' NAME | `[' exp `]' | `:' NAME funcargs | funcargs } */
  FuncState *fs = ls->fs;
  int line = ls->linenumber;
  RETURNS_1(prefixexp(ls, v));
  for (;;) {
    switch (ls->t.token) {
      case '.': {  /* fieldsel */
        luaX_next(ls);
        int tbl = new_table_before(ls,T_select, true);
        add_field(ls,tbl,"value");
        checksymbol(ls,NULL);
        add_field(ls,tbl,"field");
        break;
      }
      case '[': {  /* `[' exp1 `]' */
        if(issplitprimary(ls))
            return;
        expdesc key;
        //luaK_exp2anyregup(fs, v);
        
        int tbl = new_table_before(ls,T_index,true);
        add_field(ls,tbl,"value");
        RETURNS_1(yindex(ls, &key));
        add_field(ls,tbl,"index");
        //luaK_indexed(fs, v, &key);
        break;
      }
      case ':': {  /* `:' NAME funcargs */
        expdesc key;
        luaX_next(ls);
        int tbl = new_table_before(ls,T_method,true);
        add_field(ls,tbl,"value");
        RETURNS_1(checksymbol(ls,NULL));
        add_field(ls,tbl,"name");
        RETURNS_1(funcargs(ls, v, line));
        add_field(ls,tbl,"arguments");
        
        break;
      }
      case '(': /* funcargs */
        if(issplitprimary(ls))
            return;
        /* fallthrough */
      case TK_STRING: case '{': {
        //luaK_exp2nextreg(fs, v);
        int tbl = new_table_before(ls,T_apply,true);
        add_field(ls,tbl,"value");
        RETURNS_1(funcargs(ls, v, line));
        add_field(ls,tbl,"arguments");
        break;
      }
      default: return;
    }
  }
}

//TODO: eventually we should record the set of possibly used symbols, and only quote the ones appearing in it
static void print_captured_locals(LexState * ls, TerraCnt * tc) {
    OutputBuffer_printf(&ls->output_buffer,"function() return setmetatable({ ");
    for(StringSet::iterator i = tc->capturedlocals.begin(), end = tc->capturedlocals.end();
        i != end;
        ++i) {
        TString * iv = *i;
        const char * str = getstr(iv);
        /*OutputBuffer_puts(&ls->output_buffer, strlen(str), str);
        OutputBuffer_puts(&ls->output_buffer, 3, " = ");
        OutputBuffer_puts(&ls->output_buffer, strlen(str), str);
        OutputBuffer_puts(&ls->output_buffer, 2, "; ");*/
        OutputBuffer_printf(&ls->output_buffer,"%s = %s;",str,str);
    }
    OutputBuffer_printf(&ls->output_buffer," }, { __index = terra.makeenvunstrict(getfenv()) }) end");
}

static void block (LexState *ls);

static void doquote(LexState * ls, bool isexp) {
    check_no_terra(ls, isexp ? "`" : "quote");
    
    TerraCnt tc;
    enterterra(ls, &tc);
    
    Token begin = ls->t;
    int line = ls->linenumber;
    luaX_next(ls); //skip ` or quote
    if(isexp) {
        expdesc exp;
        RETURNS_1(expr(ls,&exp));
    } else {
        RETURNS_1(block(ls));
        check_match(ls, TK_END, TK_QUOTE, line);
    }
    int tbl = lua_gettop(ls->L);
    
    luaX_patchbegin(ls,&begin);
    int id = store_value(ls);
    OutputBuffer_printf(&ls->output_buffer,"terra.definequote(_G.terra._trees[%d],",id);
    print_captured_locals(ls,&tc);
    OutputBuffer_printf(&ls->output_buffer,")");
    luaX_patchend(ls,&begin);
    leaveterra(ls);
}

static void simpleexp (LexState *ls, expdesc *v) {
  /* simpleexp -> NUMBER | STRING | NIL | TRUE | FALSE | ... |
                  constructor | FUNCTION body | primaryexp */
  switch (ls->t.token) {
    case TK_NUMBER: {
      //v->u.nval = ls->t.seminfo.r;
      int flags = ls->t.seminfo.flags;
      if(flags & F_ISINTEGER) {
        push_integer(ls,ls->t.seminfo.i);
        const char * sign = (flags & F_ISUNSIGNED) ? "u" : "";
        const char * sz = (flags & F_IS8BYTES) ? "64" : "";
        char buf[128];
        sprintf(buf,"%sint%s",sign,sz);
        push_literal(ls,buf);
        sprintf(buf,"%lld",ls->t.seminfo.i);
        push_string(ls,buf);
        add_field(ls,lua_gettop(ls->L) - 1,"stringvalue");
      } else {
        push_double(ls,ls->t.seminfo.r);
        if(flags & F_IS8BYTES)
            push_literal(ls,"double");
        else
            push_literal(ls,"float");
      }
      break;
    }
    case TK_STRING: {
      push_string(ls,ls->t.seminfo.ts);
      push_literal(ls,"rawstring");
      break;
    }
    case TK_NIL: {
      push_boolean(ls,false);
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
      //init_exp(v, VVARARG, 0 /*luaK_codeABC(fs, OP_VARARG, 0, 1, 0)*/);
      break;
    }
    case '{': {  /* constructor */
      constructor(ls, v);
      return;
    }
    case '`': { /* quote expression */
        doquote(ls,true);
        return;
    }
    case TK_QUOTE: {
        doquote(ls,false);
        return;
    }
    case TK_FUNCTION: {
      luaX_next(ls);
      body(ls, v, 0, ls->linenumber);
      return;
    }
    case TK_TERRA: {
        check_no_terra(ls,"nested terra functions");
        
        TerraCnt tc;
        enterterra(ls, &tc);
        Token begin = ls->t;
        luaX_next(ls);
        body(ls,v,0,ls->linenumber);
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
        
        structconstructor(ls,T_struct);
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
      primaryexp(ls, v);
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
   {11,10}                           /* function pointer*/
};

#define UNARY_PRIORITY  9  /* priority for unary operators */


/*
** subexpr -> (simpleexp | unop subexpr) { binop subexpr }
** where `binop' is any binary operator with a priority higher than `limit'
*/
static BinOpr subexpr (LexState *ls, expdesc *v, int limit) {
  BinOpr op;
  UnOpr uop;
  enterlevel(ls);
  uop = getunopr(ls->t.token);
  check_lua_operator(ls,ls->t.token);
  Token begintoken = ls->t;
  
  if (uop != OPR_NOUNOPR) {
    
    int line = ls->linenumber;
    int tbl = new_table(ls,T_operator);
    push_kind(ls,luaX_token2rawstr(ls,ls->t.token));
    add_field(ls,tbl,"operator");
    luaX_next(ls);
    Token beginexp = ls->t;
    int exps = new_list(ls);
    RETURNS_1(subexpr(ls, v, UNARY_PRIORITY));
    add_entry(ls,exps);
    add_field(ls,tbl,"operands");
    
    if(uop == OPR_ADDR) { //desugar &a to terra.types.pointer(a)
        const char * expstring = luaX_saveoutput(ls, &beginexp);
        luaX_patchbegin(ls, &begintoken);
        OutputBuffer_printf(&ls->output_buffer,"terra.types.pointer(%s)", expstring);
        luaX_patchend(ls, &begintoken);
    }
    
  }
  else RETURNS_1(simpleexp(ls, v));
  /* expand while operators have priorities higher than `limit' */
  
  op = getbinopr(ls->t.token);
  const char * lhs_string = NULL;
  if(op == OPR_FUNC_PTR) {
    lhs_string = luaX_saveoutput(ls,&begintoken);
  }
  check_lua_operator(ls,ls->t.token);
  while (op != OPR_NOBINOPR && priority[op].left > limit) {
    expdesc v2;
    BinOpr nextop;
    int line = ls->linenumber;
    int exps = new_list_before(ls);
    add_entry(ls,exps); //add prefix to operator list
    int tbl = new_table_before(ls,T_operator,true); //need to create this before we call next to ensure we record the right position
    exps++; //we just put a table before it, so it is one higher on the stack
    const char * token = luaX_token2rawstr(ls,ls->t.token);
    luaX_next(ls);
    Token beginrhs = ls->t;
    /* read sub-expression with higher priority */
    RETURNS_1(nextop = subexpr(ls, &v2, priority[op].right));
    
    if(lhs_string) { //desugar a -> b to terra.types.functype(a,b)
        const char * rhs_string = luaX_saveoutput(ls,&beginrhs);
        luaX_patchbegin(ls, &begintoken);
        OutputBuffer_printf(&ls->output_buffer,"terra.types.funcpointer(%s,%s)",lhs_string,rhs_string);
        luaX_patchend(ls,&begintoken);
        lhs_string = NULL;
    }
    add_entry(ls,exps);
    
   
    add_field(ls,tbl,"operands");
    push_kind(ls,token);
    add_field(ls,tbl,"operator");
    op = nextop;
  }
  leavelevel(ls);
  return op;  /* return first untreated operator */
}


static void expr (LexState *ls, expdesc *v) {
  RETURNS_1(subexpr(ls, v, 0));
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


static void luaexpr(LexState * ls) {
    assert(ls->in_terra);
    expdesc v;
    
    //terra types are lua expressions.
    //to resolve them we stop processing terra code and start processing lua code
    //we capture the string of lua code and then evaluate it later to get the actual type
    int tbl = new_table(ls, T_luaexpression);
    Token begintoken = ls->t;
    int in_terra = ls->in_terra;
    
    ls->in_terra = 0;
    FuncState * fs = ls->fs;
    BlockCnt bl;
    enterblock(ls->fs, &bl, 0);
    RETURNS_1(expr(ls,&v));
    leaveblock(fs);
    ls->in_terra = in_terra;
    
    const char * output;
    int N;
    
    ExprReaderData data;
    data.step = 0;
    luaX_getoutput(ls, &begintoken, &data.data, &data.N);
    
    if(lua_load(ls->L, expr_reader, &data, "$terra$") != 0) {
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
    
    add_field(ls, tbl, "expression");
    
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
  int blk = new_table(ls,T_block);
  enterblock(fs, &bl, 0);
  RETURNS_1(statlist(ls));
  add_field(ls,blk,"statements");
  leaveblock(fs);
}


/*
** structure to chain all variables in the left-hand side of an
** assignment
*/
struct LHS_assign {
  struct LHS_assign *prev;
  expdesc v;  /* variable (global, local, upvalue, or indexed) */
};

static void lhsexp(LexState * ls, expdesc * v) {
    if(ls->t.token == '@') {
        expr(ls,v);
    } else {
        primaryexp(ls,v);
    }
}

static void assignment (LexState *ls, struct LHS_assign *lh, int nvars, int lhs) {
  expdesc e;
  //TODO: audit, make sure this check still happens
  //check_condition(ls, vkisvar(lh->v.k), "syntax error");
  if (testnext(ls, ',')) {  /* assignment -> `,' primaryexp assignment */
    struct LHS_assign nv;
    nv.prev = lh;
    RETURNS_1(lhsexp(ls, &nv.v));
    //if(ls->in_terra)
    //  lua_pop(ls->L,1);
    add_entry(ls,lhs);
    checklimit(ls->fs, nvars + ls->LP->nCcalls, LUAI_MAXCCALLS,
                    "C levels");
    RETURNS_0(assignment(ls, &nv, nvars+1,lhs));
  }
  else {  /* assignment -> `=' explist */
    int nexps;
    checknext(ls, '=');
    int tbl = new_table_before(ls,T_assignment, true);
    add_field(ls,tbl,"lhs");
    RETURNS_1(nexps = explist(ls, &e));
    add_field(ls,tbl,"rhs");
  }
  //init_exp(&e, VNONRELOC, ls->fs->freereg-1);  /* default assignment */
}


static void cond (LexState *ls, expdesc * v) {
  /* cond -> exp */
  RETURNS_1(expr(ls, v));  /* read condition */
}


static void gotostat (LexState *ls) {
  int line = ls->linenumber;
  TString *label;
  int g;
  if (testnext(ls, TK_GOTO)) {
    int tbl = new_table(ls,T_goto);
    
    checksymbol(ls,NULL);
    add_field(ls,tbl,"label");

  } else {
    int tbl = new_table(ls,T_break);
    luaX_next(ls);  /* skip break */
    label = luaS_new(ls->LP, "break");
  }

}

static void labelstat (LexState *ls) {
  check_terra(ls,"goto labels");
  /* label -> '::' NAME '::' */
  int tbl = new_table(ls,T_label);
  RETURNS_1(checksymbol(ls,NULL));
  FuncState *fs = ls->fs;
  checknext(ls, TK_DBCOLON);  /* skip double colon */
  /* create new entry for this label */
  /* skip other no-op statements */
  add_field(ls,tbl,"value");
}


static void whilestat (LexState *ls, int line) {
  /* whilestat -> WHILE cond DO block END */
  FuncState *fs = ls->fs;
  //int whileinit;
  int tbl = new_table(ls,T_while);
  int condexit;
  BlockCnt bl;
  luaX_next(ls);  /* skip WHILE */
  expdesc c;
  RETURNS_1(cond(ls,&c));
  add_field(ls,tbl,"condition");
  enterblock(fs, &bl, 1);
  checknext(ls, TK_DO);
  RETURNS_1(block(ls));
  add_field(ls,tbl,"body");
  check_match(ls, TK_END, TK_WHILE, line);
  leaveblock(fs);
}


static void repeatstat (LexState *ls, int line) {
  /* repeatstat -> REPEAT block UNTIL cond */
  int condexit;
  FuncState *fs = ls->fs;
  BlockCnt bl1, bl2;
  enterblock(fs, &bl1, 1);  /* loop block */
  enterblock(fs, &bl2, 0);  /* scope block */
  luaX_next(ls);  /* skip REPEAT */
  int tbl = new_table(ls,T_repeat);
  int blk = new_table(ls,T_block);
  RETURNS_1(statlist(ls));
  add_field(ls,blk,"statements");
  add_field(ls,tbl,"body");
  check_match(ls, TK_UNTIL, TK_REPEAT, line);
  expdesc c;
  RETURNS_1(cond(ls,&c));
  add_field(ls,tbl,"condition");
  leaveblock(fs);  /* finish scope */
  leaveblock(fs);  /* finish loop */
}


static void exp1 (LexState *ls, expdesc * e) {
  expr(ls, e);
}


static void forbody (LexState *ls, int line, int nvars, int isnum, BlockCnt * bl) {
  /* forbody -> DO block */
  FuncState *fs = ls->fs;
  checknext(ls, TK_DO);
  enterblock(fs, bl, 0);  /* scope for declared variables */
  RETURNS_1(block(ls));
  leaveblock(fs);  /* end of scope for declared variables */
}


static void fornum (LexState *ls, TString *varname, int line) {
  /* fornum -> NAME = exp1,exp1[,exp1] forbody */
  FuncState *fs = ls->fs;
  int tbl = new_table_before(ls,T_fornum);
  add_field(ls,tbl,"varname");
  checknext(ls, '=');
  expdesc a,b,c;
  RETURNS_1(exp1(ls,&a));  /* initial value */
  add_field(ls,tbl,"initial");
  checknext(ls, ',');
  RETURNS_1(exp1(ls,&b));  /* limit */
  add_field(ls,tbl,"limit");
  if (testnext(ls, ',')) {
    RETURNS_1(exp1(ls,&c));  /* optional step */
  } else {  /* default step = 1 */
    push_integer(ls, 1);
    push_literal(ls, "int64");
  }
  add_field(ls,tbl,"step");
  BlockCnt bl;
  if(varname)
    definevariable(ls, varname);
  RETURNS_1(forbody(ls, line, 1, 1, &bl));
  add_field(ls,tbl,"body");
}


static void forlist (LexState *ls, TString *indexname) {
  /* forlist -> NAME {,NAME} IN explist forbody */
  FuncState *fs = ls->fs;
  expdesc e;
  int nvars = 4;  /* gen, state, control, plus at least one declared var */
  int line;
  int tbl = new_table_before(ls,T_forlist);
  int vars = new_list_before(ls);
  add_entry(ls,vars);
  /* create declared variables */
  BlockCnt bl;
  if(indexname)
    definevariable(ls, indexname);
  
  while (testnext(ls, ',')) {
    TString * name = NULL;
    checksymbol(ls,&name);
    add_entry(ls,vars);
    if(name)
      definevariable(ls,name);
    nvars++;
  }
  add_field(ls,tbl,"variables");
  checknext(ls, TK_IN);
  line = ls->linenumber;
  RETURNS_1(explist(ls, &e));
  add_field(ls,tbl,"iterators");
  RETURNS_1(forbody(ls, line, nvars - 3, 0, &bl));
  add_field(ls,tbl,"body");
}

static void forstat (LexState *ls, int line) {
  /* forstat -> FOR (fornum | forlist) END */
  FuncState *fs = ls->fs;
  TString *varname = NULL;
  BlockCnt bl;
  enterblock(fs, &bl, 1);  /* scope for loop and control variables */
  luaX_next(ls);  /* skip `for' */
  checksymbol(ls,&varname);
  switch (ls->t.token) {
    case '=': RETURNS_0(fornum(ls, varname, line)); break;
    case ',': case TK_IN: RETURNS_0(forlist(ls, varname)); break;
    default: luaX_syntaxerror(ls, LUA_QL("=") " or " LUA_QL("in") " expected");
  }
  check_match(ls, TK_END, TK_FOR, line);
  leaveblock(fs);  /* loop scope (`break' jumps to this point) */
}

static void test_then_block (LexState *ls) {
  /* test_then_block -> [IF | ELSEIF] cond THEN block */
  BlockCnt bl;
  FuncState *fs = ls->fs;
  expdesc v;
  luaX_next(ls);  /* skip IF or ELSEIF */
  int tbl = new_table(ls,T_ifbranch);
  RETURNS_1(cond(ls, &v));  /* read condition */
  add_field(ls,tbl,"condition");
  checknext(ls, TK_THEN);
  int discard_remainder = 0;
  if (ls->t.token == TK_GOTO || ls->t.token == TK_BREAK) {
    enterblock(fs, &bl, 0);  /* must enter block before 'goto' */
    int blk = new_table(ls,T_block);
    int stmts = new_list(ls);
    RETURNS_1(gotostat(ls));  /* handle goto/break */
    add_entry(ls,stmts);
    add_field(ls,blk,"statements");
    add_field(ls,tbl,"body");
    if (block_follow(ls, 0)) {  /* 'goto' is the entire block? */
      leaveblock(fs);
      return;  /* and that is it */
    }
    else {  /* must skip over 'then' part if condition is false */
      discard_remainder = 1;
    }
  }
  else {  /* regular case (not goto/break) */
    enterblock(fs, &bl, 0);
  }
  int blk = new_table(ls,T_block);
  RETURNS_1(statlist(ls));  /* `then' part */
  add_field(ls,blk,"statements");
  if(!discard_remainder) {
    add_field(ls,tbl,"body");
  } else {
    if(ls->in_terra) lua_pop(ls->L,1); //discard block after goto
  }
  leaveblock(fs);
}

static void ifstat (LexState *ls, int line) {
  /* ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END */
  FuncState *fs = ls->fs;
  int tbl = new_table(ls,T_if);
  int branches = new_list(ls);
  RETURNS_1(test_then_block(ls));  /* IF cond THEN block */
  add_entry(ls,branches);
  while (ls->t.token == TK_ELSEIF) {
    RETURNS_1(test_then_block(ls));  /* ELSEIF cond THEN block */
    add_entry(ls,branches);
  }
  add_field(ls,tbl,"branches");
  if (testnext(ls, TK_ELSE)) {
    RETURNS_1(block(ls));  /* `else' part */
    add_field(ls,tbl,"orelse"); 
  }
  check_match(ls, TK_END, TK_IF, line);
}

static void localfunc (LexState *ls) {
  expdesc b;
  FuncState *fs = ls->fs;
  TString * name = str_checkname(ls);
  definevariable(ls, name);
  body(ls, &b, 0, ls->linenumber);  /* function created in next register */
  /* debug information will only see the variable after this point! */
  
}

static TString * varappendname(LexState * ls, int nametable, Name * name) {
  TString * vname = str_checkname(ls);
  Name_add(name,vname);
  push_string(ls, vname);
  add_entry(ls, nametable);
  return vname;
}

//terra variables appearing at global scope
static void varname (LexState *ls, expdesc *v, int islocal, Name * name) {
  /* funcname -> NAME {fieldsel} */
  int nametable = new_list(ls);
  
  TString * vname = varappendname(ls,nametable,name);
  while(!islocal && testnext(ls, '.'))
    varappendname(ls, nametable, name);
    
  int tbl = new_table_before(ls, T_entry);
  add_field(ls,tbl,"name");

  if(testnext(ls, ':')) {
    RETURNS_1(terratype(ls));
    add_field(ls,tbl,"type");
  }

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
  int nvars = 0;
  int nexps;
  expdesc e;
  int tbl = new_table(ls,T_defvar);
  int vars = new_list(ls);
  std::vector<TString *> declarednames;
  do {
    int entry = new_table(ls,T_entry);
    TString * vname = NULL;
    RETURNS_1(checksymbol(ls,&vname));
    if(vname)
      declarednames.push_back(vname);
    add_field(ls,entry,"name");
    if(ls->in_terra && testnext(ls,':')) {
      RETURNS_1(terratype(ls));
      add_field(ls,entry,"type");
    }
    add_entry(ls,vars);
    nvars++;
  } while (testnext(ls, ','));
  add_field(ls,tbl,"variables");
  if (testnext(ls, '=')) {
    RETURNS_1(nexps = explist(ls, &e));
    add_field(ls,tbl,"initializers");
  } else {
    //blank initializers
    nexps = 0;
  }
  for(size_t i = 0; i < declarednames.size(); i++) {
    definevariable(ls, declarednames[i]);
  }
  
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
  expdesc b;
  luaX_next(ls);  /* skip FUNCTION */
  int ismethod = funcname(ls);
  body(ls, &b, ismethod, line);
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
      Name_add(name, luaS_new(ls->LP,"methods"));
      Name_add(name,vname);
    }
  }
  
  return ismethod;
}

void print_value_and_name(LexState * ls, Name * name) {
    Name_print(name,ls);
    OutputBuffer_printf(&ls->output_buffer, ", \"");
    Name_print(name,ls);
    OutputBuffer_putc(&ls->output_buffer, '"');
}

void print_declaration(LexState * ls, Name * names, std::vector<int> * nameidxs, const char * declfn){
    if(nameidxs->size() == 0)
        return;
    for(size_t i = 0; i < nameidxs->size(); i++) {
        Name_print(&names[(*nameidxs)[i]], ls);
        if(i + 1 < nameidxs->size())
            OutputBuffer_putc(&ls->output_buffer, ',');
    }
    OutputBuffer_printf(&ls->output_buffer, " = terra.%s(%d", declfn,nameidxs->size());
    for(size_t i = 0; i < nameidxs->size(); i++) {
        OutputBuffer_putc(&ls->output_buffer, ',');
        print_value_and_name(ls, &names[(*nameidxs)[i]]);
    }
    OutputBuffer_printf(&ls->output_buffer,"); ");
}

struct TDefn {
    char kind; //'f'unction 'm'ethod 's'truct
    int nameidx;
    int treeid;
};

static void terrastats(LexState * ls, bool emittedlocal) {
    Token begin = ls->t;
    
    std::vector<Name> names;
    
    std::vector<bool> islocalname;
    size_t nlocals = 0;
    std::vector<int> structdecls;
    std::vector<int> fndecls;
    
    std::vector<TDefn> defs;
    
    TerraCnt tc;
    
    enterterra(ls, &tc);
    
    bool islocal = emittedlocal;
    for(int idx = 0; true; idx++) {
        int token = ls->t.token;
        luaX_next(ls); /* consume starting token */
        names.push_back(Name());
        Name * name = &names.back();

        islocalname.push_back(islocal);
        if(islocal)
            nlocals++;
        
        int ismethod = terraname(ls, islocal, token, name);
        switch(token) {
            case TK_TERRA: {
                expdesc b;
                fndecls.push_back(idx);
                if(ls->t.token == '(') {
                    body(ls, &b, ismethod, ls->linenumber);
                    int tree = store_value(ls);
					TDefn tdefn = {ismethod ? 'm' : 'f', idx, tree};
                    defs.push_back(tdefn);
                }
            } break;
            case TK_STRUCT: {
                structdecls.push_back(idx);
                if(ls->t.token == '{') {
                    structconstructor(ls,T_struct);
                    int tree = store_value(ls);
					TDefn tdefn = { 's', idx, tree};
                    defs.push_back(tdefn);
                }
            } break;
        }
        if(!testnext(ls,TK_AND))
            break;
        islocal = testnext(ls, TK_LOCAL);
    }
    
    leaveterra(ls);
    
    luaX_patchbegin(ls,&begin);
    
    //print the new local names (if any) and define them in the local context
    //register the references to non-local names
    if(nlocals > 0 && !emittedlocal)
         OutputBuffer_printf(&ls->output_buffer, "local ");
    for(size_t i = 0, emitted = 0; i < names.size(); i++) {
        Name * name = &names[i];
        TString * firstname = name->data[0];
        if(islocalname[i]) {
            Name_print(name, ls);
            definevariable(ls, firstname);
            tc.capturedlocals.insert(firstname);
            if(++emitted < nlocals)
                OutputBuffer_putc(&ls->output_buffer, ',');
        } else {
            refvariable(ls, firstname);
        }
    }
    if(nlocals > 0)
        OutputBuffer_putc(&ls->output_buffer, ';');
    
    //declare (but don't define the objects)
    //strict mode is disabled during declarations since we need to see if the object already has a definition
    OutputBuffer_printf(&ls->output_buffer,"Strict.strict = false; ");
    print_declaration(ls, &names[0], &structdecls, "declarestructs");
    print_declaration(ls, &names[0], &fndecls, "declarefunctions");
    OutputBuffer_printf(&ls->output_buffer,"Strict.strict = true; ");
    
    //specify definitions for objects
    
    OutputBuffer_printf(&ls->output_buffer, "terra.defineobjects(\"");
    for(size_t i = 0; i < defs.size(); i++)
        OutputBuffer_putc(&ls->output_buffer, defs[i].kind);
    OutputBuffer_printf(&ls->output_buffer, "\",");
    print_captured_locals(ls, &tc);
    
    for(size_t i = 0; i < defs.size(); i++) {
        Name * name = &names[defs[i].nameidx];
        OutputBuffer_putc(&ls->output_buffer, ',');
        print_value_and_name(ls, name);
        OutputBuffer_printf(&ls->output_buffer, ", _G.terra._trees[%d] ", defs[i].treeid);
        if(defs[i].kind == 'm') {
            OutputBuffer_putc(&ls->output_buffer, ',');
            Name_print(name, ls, -2); //print just the object names
        }
    }
    OutputBuffer_putc(&ls->output_buffer,')');
    luaX_patchend(ls,&begin);
}

static void exprstat (LexState *ls) {
  /* stat -> func | assignment */
  FuncState *fs = ls->fs;
  struct LHS_assign v;
  RETURNS_1(lhsexp(ls, &v.v));
  if(ls->t.token != '=' && ls->t.token != ',')  { /* stat -> func */
    //nop
  } else {  /* stat -> assignment */
    v.prev = NULL;
    int tbl = new_list_before(ls); //assignment list is put into a table
    add_entry(ls,tbl);
    RETURNS_0(assignment(ls, &v, 1,tbl)); //assignment will replace this table with the actual assignment node
  }
}


static void retstat (LexState *ls) {
  /* stat -> RETURN [explist] [';'] */
  FuncState *fs = ls->fs;
  expdesc e;
  int tbl = new_table(ls,T_return);
  int first, nret;  /* registers with returned values */
  if (block_follow(ls, 1) || ls->t.token == ';') {
    first = nret = 0;  /* return no values */
    new_list(ls);
  } else {
    RETURNS_1(nret = explist(ls, &e));  /* optional return values */
  }
  add_field(ls,tbl,"expressions");
  testnext(ls, ';');  /* skip optional semicolon */
}


static void statement (LexState *ls) {
  int line = ls->linenumber;  /* may be needed for error messages */

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
      RETURNS_1(forstat(ls, line));
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
      /*otherwise, fallthrough to the normal error message.*/
    default: {  /* stat -> func | assignment */
      RETURNS_1(exprstat(ls));
      break;
    }
  }
  leavelevel(ls);
}

static int le_next(lua_State * L) {
    LexState * ls = (LexState*) lua_topointer(L,lua_upvalueindex(1));
    luaX_next(ls);
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
            lua_pushinteger(ls->L,T_nametoken);
        }
        lua_setfield(ls->L,-2,"type");
    } break;
    case TK_STRING:
        lua_pushinteger(ls->L,T_stringtoken);
        lua_setfield(ls->L,-2,"type");
        lua_pushstring(ls->L,getstr(t->seminfo.ts));
        lua_setfield(ls->L,-2,"value");
        break;
    case TK_NUMBER:
        lua_pushinteger(ls->L,T_numbertoken);
        lua_setfield(ls->L,-2,"type");
        lua_pushnumber(ls->L,t->seminfo.r);
        lua_setfield(ls->L,-2,"value");
        break;
    case TK_SPECIAL:
        lua_pushstring(ls->L,getstr(t->seminfo.ts));
        lua_setfield(ls->L,-2,"type");
        break;
    case TK_EOS:
        lua_pushnumber(ls->L,T_eostoken);
        lua_setfield(ls->L,-2,"type");
        break;
    default:
        lua_pushstring(ls->L,luaX_token2rawstr(ls,t->token));
        lua_setfield(ls->L,-2,"type");
        break;
    }
}

static int le_cur(lua_State * L) {
    LexState * ls = (LexState*) lua_topointer(L,lua_upvalueindex(1));
    converttokentolua(ls, &ls->t);
    table_setposition(ls, lua_gettop(ls->L), ls->linenumber, ls->currentoffset - 1);
    return 1;
}
static int le_lookahead(lua_State * L) {
    LexState * ls = (LexState*) lua_topointer(L,lua_upvalueindex(1));
    luaX_lookahead(ls);
    converttokentolua(ls, &ls->lookahead);
    return 1;
}

static int le_luaexpr(lua_State * L) {
  LexState * ls = (LexState*) lua_topointer(L,lua_upvalueindex(1));
  
  sigjmp_buf * old_dest = ls->error_dest;
  sigjmp_buf error_dest;
  int err = sigsetjmp(error_dest, 0);
  if(!err) {
    ls->error_dest = &error_dest;
    luaexpr(ls);
  } else {
    /* there was an error, it is on the top of the stack
       we need to call lua's error handler to rethrow the error. */
    ls->error_dest = old_dest;
    ls->rethrow = 1; /* prevent languageextension from adding the context again */
    lua_error(ls->L); /* does not return */
  }
  //reset to previous error handler
  ls->error_dest = old_dest;
  //TODO: catch and re-throw the error
  lua_getfield(ls->L,-1,"expression");
  lua_remove(ls->L,-2); /* remove original object, we just want to return the function */
  return 1;
}

static void languageextension(LexState * ls, int isstatement, int islocal) {
    lua_State * L = ls->L;
    Token begin = ls->t;
    int ismethod;
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
    lua_pushcclosure(ls->L,le_luaexpr,1);
    
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
  TString *tname = luaS_new(T, name);
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
  
  
  lua_getfield(L,to,"tree");
  luaX_globalset(&lexstate, TA_TREE_METATABLE);
  
  lua_getfield(L,to,"list");
  luaX_globalset(&lexstate, TA_LIST_METATABLE);
  
  lua_getfield(L,to,"kinds");
  luaX_globalset(&lexstate, TA_KINDS_TABLE);
  
  lua_getfield(L,to,"languageextension");
  lua_getfield(L,-1,"languages");
  lexstate.languageextensionsenabled = lua_objlen(L,-1) > 0;
  lua_pop(L,1);
  lua_getfield(L,-1,"entrypoints");
  lua_remove(L,-2); /*remove language extension table*/
  luaX_globalset(&lexstate, TA_ENTRY_POINT_TABLE);
  
  lua_pop(L,1); /* remove gs and terra object from stack */
  
  assert(lua_gettop(L) == lexstate.stacktop);
  sigjmp_buf error_dest;
  int err = sigsetjmp(error_dest,0);
  if(!err) {
    lexstate.error_dest = &error_dest;
    luaX_setinput(T, &lexstate, z, tname, firstchar);
    open_mainfunc(&lexstate, &funcstate, &bl);
    luaX_next(&lexstate);  /* read first token */
    statlist(&lexstate);  /* main body */
    check(&lexstate, TK_EOS);
    close_func(&lexstate);
    assert(!funcstate.prev && !lexstate.fs);
  } else {
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
  DEBUG_ONLY(T) {
    printf("********* passing to lua ************\n%s\n*************************************\n",lexstate.output_buffer.data);
  }
  //loadbuffer doesn't like null terminators, so rewind to before them
  while(lexstate.output_buffer.data[lexstate.output_buffer.N-1] == '\0' && lexstate.output_buffer.N > 0) {
    lexstate.output_buffer.N--;
  }
  err = luaL_loadbuffer(L, lexstate.output_buffer.data, lexstate.output_buffer.N, name);  
  cleanup(&lexstate);
  return err;
}

