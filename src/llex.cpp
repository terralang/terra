/*
** $Id: llex.c,v 2.59 2011/11/30 12:43:51 roberto Exp $
** Lexical Analyzer
** See Copyright Notice in lua.h
*/

#include <locale.h>
#include <string.h>
#include <assert.h>
#include <stdint.h>
#include <stdarg.h>

#define llex_c
#define LUA_CORE

#include "llex.h"
//#include "lua.h"
#include "lctype.h"
//#include "ldo.h"
#include "llex.h"
#include "lobject.h"
//#include "lparser.h"
//#include "lstate.h"
#include "lstring.h"
//#include "ltable.h"
#include "lzio.h"
#include "treadnumber.h"

extern "C" {
#include "lua.h"
}

int next(LexState *ls) {
    ls->current = zgetc(ls->z);
    if (ls->current != EOZ) {
        ls->currentoffset++;
        OutputBuffer_putc(&ls->output_buffer, ls->current == EOZ ? '\0' : ls->current);
    }
    return ls->current;
}
#define currIsNewline(ls) (ls->current == '\n' || ls->current == '\r')

/* ORDER RESERVED */
static const char *const luaX_tokens[] = {
        "and",    "break",    "do",       "else",   "elseif", "end",   "false",
        "for",    "function", "goto",     "if",     "in",     "local", "nil",
        "not",    "or",       "repeat",   "return", "then",   "true",  "until",
        "while",  "terra",    "var",      "struct", "union",  "quote", "import",
        "defer",  "escape",   "..",       "...",    "==",     ">=",    "<=",
        "~=",     "::",       "->",       "<<",     ">>",     "<eof>", "<number>",
        "<name>", "<string>", "<special>"};

#define save_and_next(ls) (save(ls, ls->current), next(ls))

static l_noret lexerror(LexState *ls, const char *msg, int token);

static void save(LexState *ls, int c) {
    Mbuffer *b = ls->buff;
    if (luaZ_bufflen(b) + 1 > luaZ_sizebuffer(b)) {
        size_t newsize;
        if (luaZ_sizebuffer(b) >= MAX_SIZET / 2)
            lexerror(ls, "lexical element too long", 0);
        newsize = luaZ_sizebuffer(b) * 2;
        luaZ_resizebuffer(ls->L, b, newsize);
    }
    b->buffer[luaZ_bufflen(b)++] = cast(char, c);
}

void luaX_init(terra_State *L) {
    // initialize the base tstring_table that will hold reserved keywords
    int stk = lua_gettop(L->L);
    lua_newtable(L->L);
    lua_pushlightuserdata(L->L, &L->tstring_table);
    lua_pushvalue(L->L, -2);
    lua_rawset(L->L, LUA_REGISTRYINDEX);

    // stack is: <tstring_table>

    int i;
    for (i = 0; i < NUM_RESERVED; i++) {
        TString *ts = luaS_new(L, luaX_tokens[i]);
        ts->reserved = cast_byte(i + 1); /* reserved word */
    }

    lua_pop(L->L, 1);  //<tstring_table>
    assert(stk == lua_gettop(L->L));
}

void luaX_pushtstringtable(terra_State *L) {
    int stk = lua_gettop(L->L);
    lua_pushlightuserdata(L->L, &L->tstring_table);
    lua_pushvalue(L->L, -1);
    lua_rawget(L->L, LUA_REGISTRYINDEX);
    assert(!lua_isnil(L->L, -1));

    lua_newtable(L->L);  // new tstring table
    lua_newtable(L->L);  // metatable to link to old table
    lua_pushvalue(L->L, -3);
    lua_setfield(L->L, -2, "__index");
    lua_setmetatable(L->L, -2);

    lua_remove(L->L,
               -2);  // stack is: <userdata> <originaltable(need to remove)> <newtable>
    lua_rawset(L->L, LUA_REGISTRYINDEX);

    assert(stk == lua_gettop(L->L));
}

void luaX_poptstringtable(terra_State *L) {
    int stk = lua_gettop(L->L);
    lua_pushlightuserdata(L->L, &L->tstring_table);
    lua_pushvalue(L->L, -1);

    lua_rawget(L->L, LUA_REGISTRYINDEX);
    lua_getmetatable(L->L, -1);
    lua_getfield(L->L, -1, "__index");
    lua_remove(L->L, -2);  //<metatable>
    lua_remove(L->L, -2);  //<oldtable>

    lua_rawset(L->L, LUA_REGISTRYINDEX);
    assert(stk == lua_gettop(L->L));
}

const char *luaX_token2rawstr(LexState *ls, int token) {
    if (token < FIRST_RESERVED) {
        assert(token == cast(unsigned char, token));
        return luaS_cstringf(ls->LP, "%c", token);
    } else {
        return luaX_tokens[token - FIRST_RESERVED];
    }
}
const char *luaX_token2str(LexState *ls, int token) {
    if (token < FIRST_RESERVED) {
        assert(token == cast(unsigned char, token));
        return (lisprint(token)) ? luaS_cstringf(ls->LP, LUA_QL("%c"), token)
                                 : luaS_cstringf(ls->LP, "char(%d)");
    } else {
        const char *s = luaX_tokens[token - FIRST_RESERVED];
        return luaS_cstringf(ls->LP, LUA_QS, s);
    }
}

static const char *txtToken(LexState *ls, int token) {
    switch (token) {
        case TK_NAME:
        case TK_STRING:
        case TK_NUMBER:
            save(ls, '\0');
            return luaS_cstringf(ls->LP, LUA_QS, luaZ_buffer(ls->buff));
        case TK_SPECIAL:
            save(ls, '\0');
            return luaS_cstringf(ls->LP, "%s", luaZ_buffer(ls->buff));
        default:
            return luaX_token2str(ls, token);
    }
}

l_noret luaX_reporterror(LexState *ls, const char *err) {
    lua_pushstring(ls->L, err);
    throw LUA_ERRSYNTAX;
    abort();  // quiet warnings about noret
}

static l_noret lexerror(LexState *ls, const char *msg, int token) {
    msg = luaS_cstringf(ls->LP, "%s:%d: %s", getstr(ls->source), ls->linenumber, msg);
    if (token) msg = luaS_cstringf(ls->LP, "%s near %s", msg, txtToken(ls, token));
    luaX_reporterror(ls, msg);
}

l_noret luaX_syntaxerror(LexState *ls, const char *msg) {
    lexerror(ls, msg, ls->t.token);
}

/*
** creates a new string and anchors it in function's table so that
** it will not be collected until the end of the function's compilation
** (by that time it should be anchored in function's prototype)
*/
TString *luaX_newstring(LexState *ls, const char *str, size_t l) {
    return luaS_newlstr(ls->LP, str, l); /* create new string */
}

/*
** increment line number and skips newline sequence (any of
** \n, \r, \n\r, or \r\n)
*/
static void inclinenumber(LexState *ls) {
    int old = ls->current;
    assert(currIsNewline(ls));
    next(ls);                                              /* skip `\n' or `\r' */
    if (currIsNewline(ls) && ls->current != old) next(ls); /* skip `\n\r' or `\r\n' */
    if (++ls->linenumber >= MAX_INT) luaX_syntaxerror(ls, "chunk has too many lines");
}

void luaX_setinput(terra_State *LP, LexState *ls, ZIO *z, TString *source,
                   int firstchar) {
    ls->decpoint = '.';
    ls->LP = LP;
    ls->current = firstchar;
    ls->currentoffset = 0;
    ls->lookahead.token = TK_EOS; /* no look-ahead token */
    ls->z = z;
    ls->fs = NULL;
    ls->linenumber = 1;
    ls->lastline = 1;
    ls->source = source;
    ls->envn = luaS_new(
            LP, "<terra_parser>");  // luaS_new(L, LUA_ENV);  /* create env name */
    ls->in_terra = 0;
    ls->patchinfo.N = 0;
    ls->patchinfo.space = 32;
    ls->patchinfo.buffer = (char *)malloc(32);
    if (firstchar != EOZ) OutputBuffer_putc(&ls->output_buffer, firstchar);
    luaZ_resizebuffer(ls->L, ls->buff, LUA_MINBUFFER); /* initialize buffer */
}

void luaX_patchbegin(LexState *ls, Token *begin_token) {
    // save everything from the current token to the end of the output buffer in the patch
    // buffer
    OutputBuffer *ob = &ls->output_buffer;
    int n_bytes = ob->N - ls->t.seminfo.buffer_begin;
    if (n_bytes > ls->patchinfo.space) {
        int newsize = std::max(n_bytes, ls->patchinfo.space * 2);
        ls->patchinfo.buffer = (char *)realloc(ls->patchinfo.buffer, newsize);
        ls->patchinfo.space = newsize;
    }
    memcpy(ls->patchinfo.buffer, ob->data + ls->t.seminfo.buffer_begin, n_bytes);
    ls->patchinfo.N = n_bytes;
    // ls->patchinfo.buffer[ls->patchinfo.N] = '\0';
    // printf("buffer is %s\n",ls->patchinfo.buffer);

    // reset the output buffer to the beginning of the begin_token
    ob->N = begin_token->seminfo.buffer_begin;
    // retain the tokens leading whitespace for sanity...
    while (1) {
        switch (ob->data[ob->N]) {
            case '\n':
            case '\r':
                begin_token->seminfo.linebegin++;
                /*fallthrough*/
            case ' ':
            case '\f':
            case '\t':
            case '\v':
                begin_token->seminfo.buffer_begin++;
                ob->N++;
                break;
            default:
                goto loop_exit;
        }
    }
loop_exit:
    return;
    // code can now safely write to this buffer
}
void luaX_insertbeforecurrenttoken(LexState *ls, char c) {
    int sz = ls->output_buffer.N - ls->t.seminfo.buffer_begin;
    // make sure the buffer has enough space and the right size
    OutputBuffer_putc(&ls->output_buffer, c);
    char *begin = ls->output_buffer.data + ls->t.seminfo.buffer_begin;
    memmove(begin + 1, begin, sz);
    *begin = c;
    // adjust offsets of current tokens
    ls->t.seminfo.buffer_begin++;
    ls->lookahead.seminfo.buffer_begin++;
}
void luaX_getoutput(LexState *ls, Token *begin_token, const char **output, int *N) {
    OutputBuffer *ob = &ls->output_buffer;

    int buffer_begin = ls->t.seminfo.buffer_begin;
    int n_bytes = buffer_begin - begin_token->seminfo.buffer_begin;
    *output = ob->data + begin_token->seminfo.buffer_begin;
    *N = n_bytes;
}

const char *luaX_saveoutput(LexState *ls, Token *begin_token) {
    int n_bytes;
    const char *output;
    luaX_getoutput(ls, begin_token, &output, &n_bytes);
    TString *tstring = luaS_newlstr(ls->LP, output,
                                    n_bytes);  // save this to the string table, which
                                               // gets collected when this function exits
    return getstr(tstring);
}

void luaX_patchend(LexState *ls, Token *begin_token) {
    // first we need to pad with newlines, until we reach the original line count
    OutputBuffer *ob = &ls->output_buffer;
    // count the number of newlines in the patched in data
    int nlines = 0;
    for (int i = begin_token->seminfo.buffer_begin; i < ob->N; i++) {
        if (ob->data[i] == '\n') nlines++;
    }

    for (int line = begin_token->seminfo.linebegin + nlines;
         line < ls->t.seminfo.linebegin; line++) {
        OutputBuffer_putc(ob, '\n');
    }
    int offset = ob->N - ls->t.seminfo.buffer_begin;
    // restore patch data
    OutputBuffer_puts(ob, ls->patchinfo.N, ls->patchinfo.buffer);
    // adjust to current tokens to have correct information
    ls->t.seminfo.buffer_begin += offset;
    ls->lookahead.seminfo.buffer_begin += offset;
}

/*
** =======================================================
** LEXICAL ANALYZER
** =======================================================
*/

static int check_next(LexState *ls, const char *set) {
    if (ls->current == '\0' || !strchr(set, ls->current)) return 0;
    save_and_next(ls);
    return 1;
}

/* LUA_NUMBER */

static void read_numeral(LexState *ls, SemInfo *seminfo) {
    assert(lisdigit(ls->current));
    bool hasdecpoint = false;

    int c, xp = 'e';
    assert(lisdigit(ls->current));
    if ((c = ls->current) == '0') {
        save_and_next(ls);
        if ((ls->current | 0x20) == 'x') xp = 'p';
    }
    while (lislalnum(ls->current) || ls->current == '.' ||
           ((ls->current == '-' || ls->current == '+') && (c | 0x20) == xp)) {
        if (ls->current == '.') hasdecpoint = true;
        c = ls->current;
        save_and_next(ls);
    }
    save(ls, '\0');

    /* string ends in 'f' but is not hexidecimal.
          this means that we have a single precision float */
    bool issinglefloat = ls->in_terra && c == 'f' && xp != 'p';

    if (issinglefloat) {
        /* clear the 'f' so that treadnumber succeeds */
        ls->buff->buffer[luaZ_bufflen(ls->buff) - 2] = '\0';
    }

    ReadNumber num;
    if (treadnumber(ls->buff->buffer, &num, ls->in_terra && !issinglefloat))
        lexerror(ls, "malformed number", TK_NUMBER);

    /* Terra handles 2 things differently from LuaJIT:
       1. if the number had a decimal place, it is always a floating point number. In
       constrast, treadnumber will convert it to an int if it can be represented as an
       int.
       2. if the number ends in an 'f' and isn't a hexidecimal number, it is treated as a
       single-precision floating point number
    */
    seminfo->flags = num.flags;
    if (num.flags & F_ISINTEGER) {
        seminfo->i = num.i;
        seminfo->r = seminfo->i;
        if (issinglefloat) {
            seminfo->flags = 0;
        } else if (hasdecpoint) {
            seminfo->flags = F_IS8BYTES;
        }
    } else {
        seminfo->r = num.d;
        if (!issinglefloat) seminfo->flags = F_IS8BYTES;
    }
}

/*
** skip a sequence '[=*[' or ']=*]' and return its number of '='s or
** -1 if sequence is malformed
*/
static int skip_sep(LexState *ls) {
    int count = 0;
    int s = ls->current;
    assert(s == '[' || s == ']');
    save_and_next(ls);
    while (ls->current == '=') {
        save_and_next(ls);
        count++;
    }
    return (ls->current == s) ? count : (-count) - 1;
}

static void read_long_string(LexState *ls, SemInfo *seminfo, int sep) {
    save_and_next(ls);     /* skip 2nd `[' */
    if (currIsNewline(ls)) /* string starts with a newline? */
        inclinenumber(ls); /* skip it */
    for (;;) {
        switch (ls->current) {
            case EOZ:
                lexerror(ls,
                         (seminfo) ? "unfinished long string" : "unfinished long comment",
                         TK_EOS);
                break; /* to avoid warnings */
            case ']': {
                if (skip_sep(ls) == sep) {
                    save_and_next(ls); /* skip 2nd `]' */
                    goto endloop;
                }
                break;
            }
            case '\n':
            case '\r': {
                save(ls, '\n');
                inclinenumber(ls);
                if (!seminfo) luaZ_resetbuffer(ls->buff); /* avoid wasting space */
                break;
            }
            default: {
                if (seminfo)
                    save_and_next(ls);
                else
                    next(ls);
            }
        }
    }
endloop:
    if (seminfo)
        seminfo->ts = luaX_newstring(ls, luaZ_buffer(ls->buff) + (2 + sep),
                                     luaZ_bufflen(ls->buff) - 2 * (2 + sep));
}

static void escerror(LexState *ls, int *c, int n, const char *msg) {
    int i;
    luaZ_resetbuffer(ls->buff); /* prepare error message */
    save(ls, '\\');
    for (i = 0; i < n && c[i] != EOZ; i++) save(ls, c[i]);
    lexerror(ls, msg, TK_STRING);
}

static int readhexaesc(LexState *ls) {
    int c[3], i;              /* keep input for error message */
    int r = 0;                /* result accumulator */
    c[0] = 'x';               /* for error message */
    for (i = 1; i < 3; i++) { /* read two hexa digits */
        c[i] = next(ls);
        if (!lisxdigit(c[i])) escerror(ls, c, i + 1, "hexadecimal digit expected");
        r = (r << 4) + luaO_hexavalue(c[i]);
    }
    return r;
}

static int readdecesc(LexState *ls) {
    int c[3], i;
    int r = 0;                                         /* result accumulator */
    for (i = 0; i < 3 && lisdigit(ls->current); i++) { /* read up to 3 digits */
        c[i] = ls->current;
        r = 10 * r + c[i] - '0';
        next(ls);
    }
    if (r > UCHAR_MAX) escerror(ls, c, i, "decimal escape too large");
    return r;
}

static void read_string(LexState *ls, int del, SemInfo *seminfo) {
    save_and_next(ls); /* keep delimiter (for error messages) */
    while (ls->current != del) {
        switch (ls->current) {
            case EOZ:
                lexerror(ls, "unfinished string", TK_EOS);
                break; /* to avoid warnings */
            case '\n':
            case '\r':
                lexerror(ls, "unfinished string", TK_STRING);
                break;    /* to avoid warnings */
            case '\\': {  /* escape sequences */
                int c;    /* final character to be saved */
                next(ls); /* do not save the `\' */
                switch (ls->current) {
                    case 'a':
                        c = '\a';
                        goto read_save;
                    case 'b':
                        c = '\b';
                        goto read_save;
                    case 'f':
                        c = '\f';
                        goto read_save;
                    case 'n':
                        c = '\n';
                        goto read_save;
                    case 'r':
                        c = '\r';
                        goto read_save;
                    case 't':
                        c = '\t';
                        goto read_save;
                    case 'v':
                        c = '\v';
                        goto read_save;
                    case 'x':
                        c = readhexaesc(ls);
                        goto read_save;
                    case '\n':
                    case '\r':
                        inclinenumber(ls);
                        c = '\n';
                        goto only_save;
                    case '\\':
                    case '\"':
                    case '\'':
                        c = ls->current;
                        goto read_save;
                    case EOZ:
                        goto no_save; /* will raise an error next loop */
                    case 'z': {       /* zap following span of spaces */
                        next(ls);     /* skip the 'z' */
                        while (lisspace(ls->current)) {
                            if (currIsNewline(ls))
                                inclinenumber(ls);
                            else
                                next(ls);
                        }
                        goto no_save;
                    }
                    default: {
                        if (!lisdigit(ls->current))
                            escerror(ls, &ls->current, 1, "invalid escape sequence");
                        /* digital escape \ddd */
                        c = readdecesc(ls);
                        goto only_save;
                    }
                }
            read_save:
                next(ls); /* read next character */
            only_save:
                save(ls, c); /* save 'c' */
            no_save:
                break;
            }
            default:
                save_and_next(ls);
        }
    }
    save_and_next(ls); /* skip delimiter */
    seminfo->ts =
            luaX_newstring(ls, luaZ_buffer(ls->buff) + 1, luaZ_bufflen(ls->buff) - 2);
}

static void dump_stack(lua_State *L, int elem) {
    lua_pushvalue(L, elem);
    lua_getfield(L, LUA_GLOBALSINDEX, "terra");
    lua_getfield(L, -1, "tree");
    lua_getfield(L, -1, "printraw");
    lua_pushvalue(L, -4);
    lua_call(L, 1, 0);

    lua_pop(L, 3);
}

static int llex(LexState *ls, SemInfo *seminfo) {
    (void)dump_stack;  // suppress unused warning for debugging function
    luaZ_resetbuffer(ls->buff);
    seminfo->buffer_begin =
            ls->output_buffer.N - 1;  //- 1 because we already recorded the first token
    seminfo->linebegin = ls->linenumber;  // no -1 because we haven't incremented line
                                          // info for this token yet
    for (;;) {
        switch (ls->current) {
            case '\n':
            case '\r': { /* line breaks */
                inclinenumber(ls);
                break;
            }
            case ' ':
            case '\f':
            case '\t':
            case '\v': { /* spaces */
                next(ls);
                break;
            }
            case '-': { /* '-' or '--' (comment) */
                next(ls);
                if (ls->current == '>') {
                    next(ls);
                    return TK_FUNC_PTR;
                }
                if (ls->current != '-') return '-';
                /* else is a comment */
                next(ls);
                if (ls->current == '[') { /* long comment? */
                    int sep = skip_sep(ls);
                    luaZ_resetbuffer(ls->buff); /* `skip_sep' may dirty the buffer */
                    if (sep >= 0) {
                        read_long_string(ls, NULL, sep); /* skip long comment */
                        luaZ_resetbuffer(
                                ls->buff); /* previous call may dirty the buff. */
                        break;
                    }
                }
                /* else short comment */
                while (!currIsNewline(ls) && ls->current != EOZ)
                    next(ls); /* skip until end of line (or end of file) */
                break;
            }
            case '[': { /* long string or simply '[' */
                int sep = skip_sep(ls);
                if (sep >= 0) {
                    read_long_string(ls, seminfo, sep);
                    return TK_STRING;
                } else if (sep == -1)
                    return '[';
                else
                    lexerror(ls, "invalid long string delimiter", TK_STRING);
            }
            case '=': {
                next(ls);
                if (ls->current != '=')
                    return '=';
                else {
                    next(ls);
                    return TK_EQ;
                }
            }
            case '<': {
                next(ls);
                if (ls->current == '=') {
                    next(ls);
                    return TK_LE;
                } else if (ls->current == '<') {
                    next(ls);
                    return TK_LSHIFT;
                } else
                    return '<';
            }
            case '>': {
                next(ls);
                if (ls->current == '=') {
                    next(ls);
                    return TK_GE;
                } else if (ls->current == '>') {
                    next(ls);
                    return TK_RSHIFT;
                } else
                    return '>';
            }
            case '~': {
                next(ls);
                if (ls->current != '=')
                    return '~';
                else {
                    next(ls);
                    return TK_NE;
                }
            }
            case ':': {
                next(ls);
                if (ls->current != ':')
                    return ':';
                else {
                    next(ls);
                    return TK_DBCOLON;
                }
            }
            case '"':
            case '\'': { /* short literal strings */
                read_string(ls, ls->current, seminfo);
                return TK_STRING;
            }
            case '.': { /* '.', '..', '...', or number */
                save_and_next(ls);
                if (check_next(ls, ".")) {
                    if (check_next(ls, "."))
                        return TK_DOTS; /* '...' */
                    else
                        return TK_CONCAT; /* '..' */
                } else if (!lisdigit(ls->current))
                    return '.';
                /* else go through */
            }
            case '0':
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
            case '7':
            case '8':
            case '9': {
                read_numeral(ls, seminfo);
                return TK_NUMBER;
            }
            case EOZ: {
                seminfo->buffer_begin =
                        ls->output_buffer.N;  // EOS is not counted as a character, so we
                                              // need to make sure the beginning of this
                                              // token points to the end of the tokens
                return TK_EOS;
            }
            default: {
                if (lislalpha(ls->current)) { /* identifier or reserved word? */
                    TString *ts;
                    do {
                        save_and_next(ls);
                    } while (lislalnum(ls->current));
                    ts = luaX_newstring(ls, luaZ_buffer(ls->buff),
                                        luaZ_bufflen(ls->buff));
                    seminfo->ts = ts;
                    if (ts->reserved > 0) /* reserved word? */
                        return ts->reserved - 1 + FIRST_RESERVED;
                    else {
                        if (ls->languageextensionsenabled) {
                            luaX_globalgetfield(ls, TA_ENTRY_POINT_TABLE, getstr(ts));
                            int special = lua_istable(ls->L, -1);
                            lua_pop(ls->L, 1); /* remove lookup value */
                            if (special) return TK_SPECIAL;
                        }
                        return TK_NAME;
                    }
                } else { /* single-char tokens (+ - / ...) */
                    int c = ls->current;
                    next(ls);
                    return c;
                }
            }
        }
    }
}

void luaX_next(LexState *ls) {
    ls->lastline = ls->linenumber;
    if (ls->lookahead.token != TK_EOS) { /* is there a look-ahead token? */
        ls->t = ls->lookahead;           /* use this one */
        ls->lookahead.token = TK_EOS;    /* and discharge it */
    } else
        ls->t.token = llex(ls, &ls->t.seminfo); /* read next token */
}

int luaX_lookahead(LexState *ls) {
    assert(ls->lookahead.token == TK_EOS);
    ls->lookahead.token = llex(ls, &ls->lookahead.seminfo);
    return ls->lookahead.token;
}

void luaX_globalpush(LexState *ls, TA_Globals k) {
    lua_pushlightuserdata(ls->L, &ls->lextable);
    lua_rawget(ls->L, LUA_REGISTRYINDEX);
    lua_rawgeti(ls->L, -1, k);
    lua_remove(ls->L, -2); /*remove lexstate table*/
}
void luaX_globalgettable(LexState *ls, TA_Globals k) {
    luaX_globalpush(ls, k);
    lua_insert(ls->L, -2);
    lua_gettable(ls->L, -2);
    lua_remove(ls->L, -2); /*remove the global table*/
}
void luaX_globalgetfield(LexState *ls, TA_Globals k, const char *field) {
    luaX_globalpush(ls, k);
    lua_getfield(ls->L, -1, field);
    lua_remove(ls->L, -2);
}
void luaX_globalset(LexState *ls, TA_Globals k) {
    lua_pushlightuserdata(ls->L, &ls->lextable);
    lua_rawget(ls->L, LUA_REGISTRYINDEX);
    lua_insert(ls->L, -2);
    lua_rawseti(ls->L, -2, k);
    lua_pop(ls->L, 1);
}
