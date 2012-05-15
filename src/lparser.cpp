/*
** $Id: lparser.c,v 2.124 2011/12/02 13:23:56 roberto Exp $
** Lua Parser
** See Copyright Notice in lua.h
*/


#include <string.h>
#include <assert.h>

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



#define AST_TOKENS(_) \
	_(kind) \
	_(type)

enum TA_Token {
	TA_TOKEN_ZERO = 0, //tokens refer to stack locations in Lua, so should start at 1.
#define MAKE_AST_ENUM(x) TA_##x,
	AST_TOKENS(MAKE_AST_ENUM)
	TA_LAST_TOKEN
#undef MAKE_AST_ENUM
};
#define TA_NUM_TOKENS (TA_LAST_TOKEN - 1)

enum TA_Globals {
	TA_FUNCTION_TABLE = TA_LAST_TOKEN,
	TA_LAST_GLOBAL
};


const char * token_to_string[] = {
	""
#define MAKE_AST_STRING(x) #x,
	AST_TOKENS(MAKE_AST_STRING)
	""
};

//helpers to ensure that the lua stack contains the right number of arguments after a call
#define RETURNS_N(x,n) do { \
	if(ls->in_terra) { \
		int begin = lua_gettop(ls->L); \
		(x); \
		int end = lua_gettop(ls->L); \
		assert(begin + n == end); \
	} else { \
		(x); \
	} \
} while(0)

#define RETURNS_1(x) RETURNS_N(x,1)

/* maximum number of local variables per function (must be smaller
   than 250, due to the bytecode format) */
#define MAXVARS		200

#define hasmultret(k)		((k) == VCALL || (k) == VVARARG)

/*
** nodes for block list (list of active blocks)
*/
typedef struct BlockCnt {
  struct BlockCnt *previous;  /* chain */
  std::vector<TString *> local_variables;
} BlockCnt;



/*
** prototypes for recursive non-terminal functions
*/
static void statement (LexState *ls);
static void expr (LexState *ls, expdesc *v);


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
  luaP_State *L = fs->ls->LP;
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


#define check_condition(ls,c,msg)	{ if (!(c)) luaX_syntaxerror(ls, msg); }



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

static void checkname (LexState *ls, expdesc *e) {
	str_checkname(ls);
}

static void singlevar (LexState *ls, expdesc *var) {
  TString *varname = str_checkname(ls);
}


static void enterlevel (LexState *ls) {
  luaP_State *L = ls->LP;
  ++L->nCcalls;
  checklimit(ls->fs, L->nCcalls, LUAI_MAXCCALLS, "C levels");
}

#define leavelevel(ls)	((ls)->LP->nCcalls--)

static void enterblock (FuncState *fs, BlockCnt *bl, lu_byte isloop) {
  bl->previous = fs->bl;
  fs->bl = bl;
}

static void breaklabel (LexState *ls) {

}

static void leaveblock (FuncState *fs) {
  BlockCnt *bl = fs->bl;
  LexState *ls = fs->ls;
  fs->bl = bl->previous;
  for(int i = 0; i < bl->local_variables.size(); i++) {
	  printf("v[%d] = %s\n",i,getstr(bl->local_variables[i]));
  }
}

static void open_func (LexState *ls, FuncState *fs, BlockCnt *bl) {
  luaP_State *L = ls->LP;
  Proto *f;
  fs->prev = ls->fs;  /* linked list of funcstates */
  fs->ls = ls;
  ls->fs = fs;
  fs->f.linedefined = 0;
  fs->f.is_vararg = 0;
  fs->f.source = ls->source;
  enterblock(fs, bl, 0);
}


static void close_func (LexState *ls) {
  luaP_State *L = ls->LP;
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
  while (!block_follow(ls, 1)) {
    if (ls->t.token == TK_RETURN) {
      statement(ls);
      return;  /* 'return' must be last statement */
    }
    statement(ls);
  }
}


static void fieldsel (LexState *ls, expdesc *v) {
  /* fieldsel -> ['.' | ':'] NAME */
  FuncState *fs = ls->fs;
  expdesc key;
  //luaK_exp2anyregup(fs, v);
  luaX_next(ls);  /* skip the dot or colon */
  checkname(ls, &key);
  //luaK_indexed(fs, v, &key);
}


static void yindex (LexState *ls, expdesc *v) {
  /* index -> '[' expr ']' */
  luaX_next(ls);  /* skip the '[' */
  expr(ls, v);
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
  if (ls->t.token == TK_NAME) {
    checklimit(fs, cc->nh, MAX_INT, "items in a constructor");
    checkname(ls, &key);
  }
  else  /* ls->t.token == '[' */
    yindex(ls, &key);
  cc->nh++;
  checknext(ls, '=');
  expr(ls, &val);
}

static void listfield (LexState *ls, struct ConsControl *cc) {
  /* listfield -> exp */
  expdesc val;
  expr(ls, &val);
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
  checknext(ls, '{');
  do {
    if (ls->t.token == '}') break;
    field(ls, &cc);
  } while (testnext(ls, ',') || testnext(ls, ';'));
  check_match(ls, '}', '{', line);
}

/* }====================================================================== */



static void parlist (LexState *ls) {
  /* parlist -> [ param { `,' param } ] */
  FuncState *fs = ls->fs;
  Proto *f = &fs->f;
  int nparams = 0;
  f->is_vararg = 0;
  if (ls->t.token != ')') {  /* is `parlist' not empty? */
    do {
      switch (ls->t.token) {
        case TK_NAME: {  /* param -> NAME */
          str_checkname(ls);
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
}


static void body (LexState *ls, expdesc *e, int ismethod, int line) {
  /* body ->  `(' parlist `)' block END */
  FuncState new_fs;
  BlockCnt bl;
  open_func(ls, &new_fs, &bl);
  new_fs.f.linedefined = line;
  checknext(ls, '(');
  if (ismethod) {
  }
  parlist(ls);
  checknext(ls, ')');
  statlist(ls);
  new_fs.f.lastlinedefined = ls->linenumber;
  check_match(ls, TK_END, TK_FUNCTION, line);
  //codeclosure(ls, new_fs.f, e);
  close_func(ls);
}


static int explist (LexState *ls, expdesc *v) {
  /* explist -> expr { `,' expr } */
  int n = 1;  /* at least one expression */
  expr(ls, v);
  while (testnext(ls, ',')) {
    //luaK_exp2nextreg(ls->fs, v);
    expr(ls, v);
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
      } else {
        explist(ls, &args);
      }
      check_match(ls, ')', '(', line);
      break;
    }
    case '{': {  /* funcargs -> constructor */
      constructor(ls, &args);
      break;
    }
    case TK_STRING: {  /* funcargs -> STRING */
      //codestring(ls, &args, ls->t.seminfo.ts);
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
      expr(ls, v);
      check_match(ls, ')', '(', line);
      //luaK_dischargevars(ls->fs, v);
      return;
    }
    case TK_NAME: {
      singlevar(ls, v);
      return;
    }
    default: {
      luaX_syntaxerror(ls, "unexpected symbol");
    }
  }
}


static void primaryexp (LexState *ls, expdesc *v) {
  /* primaryexp ->
        prefixexp { `.' NAME | `[' exp `]' | `:' NAME funcargs | funcargs } */
  FuncState *fs = ls->fs;
  int line = ls->linenumber;
  prefixexp(ls, v);
  for (;;) {
    switch (ls->t.token) {
      case '.': {  /* fieldsel */
        fieldsel(ls, v);
        break;
      }
      case '[': {  /* `[' exp1 `]' */
        expdesc key;
        //luaK_exp2anyregup(fs, v);
        yindex(ls, &key);
        //luaK_indexed(fs, v, &key);
        break;
      }
      case ':': {  /* `:' NAME funcargs */
        expdesc key;
        luaX_next(ls);
        checkname(ls, &key);
        //luaK_self(fs, v, &key);
        funcargs(ls, v, line);
        break;
      }
      case '(': case TK_STRING: case '{': {  /* funcargs */
        //luaK_exp2nextreg(fs, v);
        funcargs(ls, v, line);
        break;
      }
      default: return;
    }
  }
}


static void simpleexp (LexState *ls, expdesc *v) {
  /* simpleexp -> NUMBER | STRING | NIL | TRUE | FALSE | ... |
                  constructor | FUNCTION body | primaryexp */
  switch (ls->t.token) {
    case TK_NUMBER: {
      //v->u.nval = ls->t.seminfo.r;
      break;
    }
    case TK_STRING: {
      break;
    }
    case TK_NIL: {
      //init_exp(v, VNIL, 0);
      break;
    }
    case TK_TRUE: {
      //init_exp(v, VTRUE, 0);
      break;
    }
    case TK_FALSE: {
      //init_exp(v, VFALSE, 0);
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
    case TK_FUNCTION: {
      luaX_next(ls);
      body(ls, v, 0, ls->linenumber);
      return;
    }
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
  OPR_ADD, OPR_SUB, OPR_MUL, OPR_DIV, OPR_MOD, OPR_POW,
  OPR_CONCAT,
  OPR_EQ, OPR_LT, OPR_LE,
  OPR_NE, OPR_GT, OPR_GE,
  OPR_AND, OPR_OR,
  OPR_NOBINOPR
} BinOpr;


typedef enum UnOpr { OPR_MINUS, OPR_NOT, OPR_LEN, OPR_NOUNOPR } UnOpr;

static UnOpr getunopr (int op) {
  switch (op) {
    case TK_NOT: return OPR_NOT;
    case '-': return OPR_MINUS;
    case '#': return OPR_LEN;
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
    default: return OPR_NOBINOPR;
  }
}

static const struct {
  lu_byte left;  /* left priority for each binary operator */
  lu_byte right; /* right priority */
} priority[] = {  /* ORDER OPR */
   {6, 6}, {6, 6}, {7, 7}, {7, 7}, {7, 7},  /* `+' `-' `*' `/' `%' */
   {10, 9}, {5, 4},                 /* ^, .. (right associative) */
   {3, 3}, {3, 3}, {3, 3},          /* ==, <, <= */
   {3, 3}, {3, 3}, {3, 3},          /* ~=, >, >= */
   {2, 2}, {1, 1}                   /* and, or */
};

#define UNARY_PRIORITY	8  /* priority for unary operators */


/*
** subexpr -> (simpleexp | unop subexpr) { binop subexpr }
** where `binop' is any binary operator with a priority higher than `limit'
*/
static BinOpr subexpr (LexState *ls, expdesc *v, int limit) {
  BinOpr op;
  UnOpr uop;
  enterlevel(ls);
  uop = getunopr(ls->t.token);
  if (uop != OPR_NOUNOPR) {
    int line = ls->linenumber;
    luaX_next(ls);
    subexpr(ls, v, UNARY_PRIORITY);
  }
  else simpleexp(ls, v);
  /* expand while operators have priorities higher than `limit' */
  op = getbinopr(ls->t.token);
  while (op != OPR_NOBINOPR && priority[op].left > limit) {
    expdesc v2;
    BinOpr nextop;
    int line = ls->linenumber;
    luaX_next(ls);
    /* read sub-expression with higher priority */
    nextop = subexpr(ls, &v2, priority[op].right);
    op = nextop;
  }
  leavelevel(ls);
  return op;  /* return first untreated operator */
}


static void expr (LexState *ls, expdesc *v) {
  subexpr(ls, v, 0);
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
  enterblock(fs, &bl, 0);
  statlist(ls);
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

static void assignment (LexState *ls, struct LHS_assign *lh, int nvars) {
  expdesc e;
  //TODO: audit, make sure this check still happens
  //check_condition(ls, vkisvar(lh->v.k), "syntax error");
  if (testnext(ls, ',')) {  /* assignment -> `,' primaryexp assignment */
    struct LHS_assign nv;
    nv.prev = lh;
    primaryexp(ls, &nv.v);
    checklimit(ls->fs, nvars + ls->LP->nCcalls, LUAI_MAXCCALLS,
                    "C levels");
    assignment(ls, &nv, nvars+1);
  }
  else {  /* assignment -> `=' explist */
    int nexps;
    checknext(ls, '=');
    nexps = explist(ls, &e);
  }
  //init_exp(&e, VNONRELOC, ls->fs->freereg-1);  /* default assignment */
}


static void cond (LexState *ls, expdesc * v) {
  /* cond -> exp */
  expr(ls, v);  /* read condition */
}


static void gotostat (LexState *ls) {
  int line = ls->linenumber;
  TString *label;
  int g;
  if (testnext(ls, TK_GOTO))
    label = str_checkname(ls);
  else {
    luaX_next(ls);  /* skip break */
    label = luaS_new(ls->LP, "break");
  }

}

static void labelstat (LexState *ls, TString *label, int line) {
  /* label -> '::' NAME '::' */
  FuncState *fs = ls->fs;
  checknext(ls, TK_DBCOLON);  /* skip double colon */
  /* create new entry for this label */
  /* skip other no-op statements */
  while (ls->t.token == ';' || ls->t.token == TK_DBCOLON)
    statement(ls);

}


static void whilestat (LexState *ls, int line) {
  /* whilestat -> WHILE cond DO block END */
  FuncState *fs = ls->fs;
  //int whileinit;
  int condexit;
  BlockCnt bl;
  luaX_next(ls);  /* skip WHILE */
  expdesc c;
  cond(ls,&c);
  enterblock(fs, &bl, 1);
  checknext(ls, TK_DO);
  block(ls);
  check_match(ls, TK_END, TK_WHILE, line);
  leaveblock(fs);
}


static void repeatstat (LexState *ls, int line) {
  /* repeatstat -> REPEAT block UNTIL cond */
  int condexit;
  FuncState *fs = ls->fs;
  //int repeat_init = luaK_getlabel(fs);
  BlockCnt bl1, bl2;
  enterblock(fs, &bl1, 1);  /* loop block */
  enterblock(fs, &bl2, 0);  /* scope block */
  luaX_next(ls);  /* skip REPEAT */
  statlist(ls);
  check_match(ls, TK_UNTIL, TK_REPEAT, line);
  expdesc c;
  cond(ls,&c);
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
  block(ls);
  leaveblock(fs);  /* end of scope for declared variables */
}


static void fornum (LexState *ls, TString *varname, int line) {
  /* fornum -> NAME = exp1,exp1[,exp1] forbody */
  FuncState *fs = ls->fs;

  checknext(ls, '=');
  expdesc a,b,c;
  exp1(ls,&a);  /* initial value */
  checknext(ls, ',');
  exp1(ls,&b);  /* limit */
  if (testnext(ls, ','))
    exp1(ls,&c);  /* optional step */
  else {  /* default step = 1 */

  }
  BlockCnt bl;
  bl.local_variables.push_back(varname);
  forbody(ls, line, 1, 1, &bl);
}


static void forlist (LexState *ls, TString *indexname) {
  /* forlist -> NAME {,NAME} IN explist forbody */
  FuncState *fs = ls->fs;
  expdesc e;
  int nvars = 4;  /* gen, state, control, plus at least one declared var */
  int line;

  /* create declared variables */
  BlockCnt bl;
  bl.local_variables.push_back(indexname);
  while (testnext(ls, ',')) {
    TString * name = str_checkname(ls);
    bl.local_variables.push_back(name);
    nvars++;
  }
  checknext(ls, TK_IN);
  line = ls->linenumber;
  explist(ls, &e);
  forbody(ls, line, nvars - 3, 0, &bl);
}

static void forstat (LexState *ls, int line) {
  /* forstat -> FOR (fornum | forlist) END */
  FuncState *fs = ls->fs;
  TString *varname;
  BlockCnt bl;
  enterblock(fs, &bl, 1);  /* scope for loop and control variables */
  luaX_next(ls);  /* skip `for' */
  varname = str_checkname(ls);  /* first variable name */
  switch (ls->t.token) {
    case '=': fornum(ls, varname, line); break;
    case ',': case TK_IN: forlist(ls, varname); break;
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
  expr(ls, &v);  /* read condition */
  checknext(ls, TK_THEN);
  if (ls->t.token == TK_GOTO || ls->t.token == TK_BREAK) {
    enterblock(fs, &bl, 0);  /* must enter block before 'goto' */
    gotostat(ls);  /* handle goto/break */
    if (block_follow(ls, 0)) {  /* 'goto' is the entire block? */
      leaveblock(fs);
      return;  /* and that is it */
    }
    else {  /* must skip over 'then' part if condition is false */
    }
  }
  else {  /* regular case (not goto/break) */
    enterblock(fs, &bl, 0);
  }
  statlist(ls);  /* `then' part */
  leaveblock(fs);
}

static void ifstat (LexState *ls, int line) {
  /* ifstat -> IF cond THEN block {ELSEIF cond THEN block} [ELSE block] END */
  FuncState *fs = ls->fs;
  test_then_block(ls);  /* IF cond THEN block */
  while (ls->t.token == TK_ELSEIF)
    test_then_block(ls);  /* ELSEIF cond THEN block */
  if (testnext(ls, TK_ELSE))
    block(ls);  /* `else' part */
  check_match(ls, TK_END, TK_IF, line);
}

static void localfunc (LexState *ls) {
  expdesc b;
  FuncState *fs = ls->fs;
  TString * name = str_checkname(ls);
  body(ls, &b, 0, ls->linenumber);  /* function created in next register */
  /* debug information will only see the variable after this point! */
  fs->bl->local_variables.push_back(name);
}

static void localstat (LexState *ls) {
  /* stat -> LOCAL NAME {`,' NAME} [`=' explist] */
  int nvars = 0;
  int nexps;
  expdesc e;
  do {
	TString * name = str_checkname(ls);
    ls->fs->bl->local_variables.push_back(name);
	nvars++;
  } while (testnext(ls, ','));
  if (testnext(ls, '='))
    nexps = explist(ls, &e);
  else {
    nexps = 0;
  }
}

static int funcname (LexState *ls, expdesc *v) {
  /* funcname -> NAME {fieldsel} [`:' NAME] */
  int ismethod = 0;
  singlevar(ls, v);
  while (ls->t.token == '.')
    fieldsel(ls, v);
  if (ls->t.token == ':') {
    ismethod = 1;
    fieldsel(ls, v);
  }
  return ismethod;
}


static void funcstat (LexState *ls, int line) {
  /* funcstat -> FUNCTION funcname body */
  int ismethod;
  expdesc v, b;
  luaX_next(ls);  /* skip FUNCTION */
  ismethod = funcname(ls, &v);
  body(ls, &b, ismethod, line);
  if(ls->in_terra) {
	  lua_pushstring(ls->L,"this is terra");
  }
}

static void terrastat(LexState * ls, int line) {
	ls->in_terra++;
	Token t = ls->t;
	int obj_id = ls->n_lua_objects++;
	lua_pushinteger(ls->L,obj_id);
	RETURNS_1(funcstat(ls,line));
	lua_settable(ls->L,TA_FUNCTION_TABLE);
	luaX_patchbegin(ls,&t);
	OutputBuffer_printf(&ls->output_buffer,"terra.newfunction(_G._terra_globals[%d])",obj_id);
	luaX_patchend(ls,&t);
	ls->in_terra--;
}


static void exprstat (LexState *ls) {
  /* stat -> func | assignment */
  FuncState *fs = ls->fs;
  struct LHS_assign v;
  primaryexp(ls, &v.v);
  //TODO: audit. v.v.k is probably not set correctly, can check to see if '=' or ',' follows, must make sure VCALL gets propaged back here
  if (v.v.k == ECALL || (ls->t.token != '=' && ls->t.token != ','))  { /* stat -> func */

  } else {  /* stat -> assignment */
    v.prev = NULL;
    assignment(ls, &v, 1);
  }
}


static void retstat (LexState *ls) {
  /* stat -> RETURN [explist] [';'] */
  FuncState *fs = ls->fs;
  expdesc e;
  int first, nret;  /* registers with returned values */
  if (block_follow(ls, 1) || ls->t.token == ';')
    first = nret = 0;  /* return no values */
  else {
    nret = explist(ls, &e);  /* optional return values */
  }
  testnext(ls, ';');  /* skip optional semicolon */
}


static void statement (LexState *ls) {
  int line = ls->linenumber;  /* may be needed for error messages */
  enterlevel(ls);
  switch (ls->t.token) {
    case ';': {  /* stat -> ';' (empty statement) */
      luaX_next(ls);  /* skip ';' */
      break;
    }
    case TK_IF: {  /* stat -> ifstat */
      ifstat(ls, line);
      break;
    }
    case TK_WHILE: {  /* stat -> whilestat */
      whilestat(ls, line);
      break;
    }
    case TK_DO: {  /* stat -> DO block END */
      luaX_next(ls);  /* skip DO */
      block(ls);
      check_match(ls, TK_END, TK_DO, line);
      break;
    }
    case TK_FOR: {  /* stat -> forstat */
      forstat(ls, line);
      break;
    }
    case TK_REPEAT: {  /* stat -> repeatstat */
      repeatstat(ls, line);
      break;
    }
    case TK_FUNCTION: {  /* stat -> funcstat */
      funcstat(ls, line);
      break;
    }
    case TK_TERRA: {
      terrastat(ls,line);
    } break;
    case TK_LOCAL: {  /* stat -> localstat */
      luaX_next(ls);  /* skip LOCAL */
      if (testnext(ls, TK_FUNCTION))  /* local function? */
        localfunc(ls);
      else
        localstat(ls);
      break;
    }
    case TK_DBCOLON: {  /* stat -> label */
      luaX_next(ls);  /* skip double colon */
      labelstat(ls, str_checkname(ls), line);
      break;
    }
    case TK_RETURN: {  /* stat -> retstat */
      luaX_next(ls);  /* skip RETURN */
      retstat(ls);
      break;
    }
    case TK_BREAK:   /* stat -> breakstat */
    case TK_GOTO: {  /* stat -> 'goto' NAME */
      gotostat(ls);
      break;
    }
    default: {  /* stat -> func | assignment */
      exprstat(ls);
      break;
    }
  }
  leavelevel(ls);
}

/* }====================================================================== */

void luaY_parser (lua_State * L, luaP_State *lp,ZIO *z, Mbuffer *buff,
                    const char *name, int firstchar) {
  LexState lexstate;
  FuncState funcstate;
  BlockCnt bl;
  lexstate.L = L;
  TString *tname = luaS_new(lp, name);
  lexstate.buff = buff;
  OutputBuffer_init(&lexstate.output_buffer);
  if(!lua_checkstack(L,TA_LAST_TOKEN + LUAI_MAXCCALLS)) {
	  abort();
  }
  for(int i = 0; i < TA_NUM_TOKENS; i++) {
	  lua_pushstring(L,token_to_string[i+1]);
  }
  lua_newtable(L);//TA_FUNCTION_TABLE
  lua_pushvalue(L,-1);
  lua_setfield(L,LUA_GLOBALSINDEX,"_terra_globals");

  luaX_setinput(lp, &lexstate, z, tname, firstchar);
  open_mainfunc(&lexstate, &funcstate, &bl);
  luaX_next(&lexstate);  /* read first token */
  statlist(&lexstate);  /* main body */
  check(&lexstate, TK_EOS);
  close_func(&lexstate);
  assert(!funcstate.prev && !lexstate.fs);
  lua_pop(L,TA_NUM_TOKENS + 1);

  assert(lua_gettop(L) == 0);
  /* all scopes should be correctly finished */
  OutputBuffer_putc(&lexstate.output_buffer,'\0');
  printf("%s",lexstate.output_buffer.data);
  printf("\n\n");
  if(luaL_dostring(L,lexstate.output_buffer.data)) {
	  printf("error: %s\n",luaL_checkstring(L,-1));
  }
}

