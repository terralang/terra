/* vim: ts=4 sw=4 sts=4 et tw=78
 * Copyright (c) 2011 James R. McKaskill. See license in tffi.h
 */
#include "tffi.h"

#define IS_CONST(tok)                                          \
    (IS_LITERAL(tok, "const") || IS_LITERAL(tok, "__const") || \
     IS_LITERAL(tok, "__const__"))
#define IS_VOLATILE(tok)                                             \
    (IS_LITERAL(tok, "volatile") || IS_LITERAL(tok, "__volatile") || \
     IS_LITERAL(tok, "__volatile__"))
#define IS_RESTRICT(tok)                                             \
    (IS_LITERAL(tok, "restrict") || IS_LITERAL(tok, "__restrict") || \
     IS_LITERAL(tok, "__restrict__"))

enum etoken {
    TOK_NIL,
    TOK_NUMBER,
    TOK_STRING,
    TOK_TOKEN,

    /* the order of these values must match the token strings in lex.c */

    TOK_3_BEGIN,
    TOK_VA_ARG,

    TOK_2_BEGIN,
    TOK_LEFT_SHIFT,
    TOK_RIGHT_SHIFT,
    TOK_LOGICAL_AND,
    TOK_LOGICAL_OR,
    TOK_LESS_EQUAL,
    TOK_GREATER_EQUAL,
    TOK_EQUAL,
    TOK_NOT_EQUAL,

    TOK_1_BEGIN,
    TOK_OPEN_CURLY,
    TOK_CLOSE_CURLY,
    TOK_SEMICOLON,
    TOK_COMMA,
    TOK_COLON,
    TOK_ASSIGN,
    TOK_OPEN_PAREN,
    TOK_CLOSE_PAREN,
    TOK_OPEN_SQUARE,
    TOK_CLOSE_SQUARE,
    TOK_DOT,
    TOK_AMPERSAND,
    TOK_LOGICAL_NOT,
    TOK_BITWISE_NOT,
    TOK_MINUS,
    TOK_PLUS,
    TOK_STAR,
    TOK_DIVIDE,
    TOK_MODULUS,
    TOK_LESS,
    TOK_GREATER,
    TOK_BITWISE_XOR,
    TOK_BITWISE_OR,
    TOK_QUESTION,
    TOK_POUND,

    TOK_REFERENCE = TOK_AMPERSAND,
    TOK_MULTIPLY = TOK_STAR,
    TOK_BITWISE_AND = TOK_AMPERSAND,
};

struct token {
    enum etoken type;
    int64_t integer;
    const char* str;
    size_t size;
};

#define IS_LITERAL(TOK, STR) \
    (((TOK).size == sizeof(STR) - 1) && 0 == memcmp((TOK).str, STR, sizeof(STR) - 1))

/* the order of tokens _must_ match the order of the enum etoken enum */

static char tok3[][4] = {
        "...", /* unused ">>=", "<<=", */
};

static char tok2[][3] = {
        "<<", ">>", "&&", "||", "<=", ">=", "==", "!=",
        /* unused "+=", "-=", "*=", "/=", "%=", "&=", "^=", "|=", "++", "--", "->", "::",
         */
};

static char tok1[] = {'{', '}', ';', ',', ':', '=', '(', ')', '[', ']', '.', '&', '!',
                      '~', '-', '+', '*', '/', '%', '<', '>', '^', '|', '?', '#'};

static int next_token(lua_State* L, struct parser* P, struct token* tok) {
    size_t i;
    const char* s = P->next;

    /* UTF8 BOM */
    if (s[0] == '\xEF' && s[1] == '\xBB' && s[2] == '\xBF') {
        s += 3;
    }

    /* consume whitespace and comments */
    for (;;) {
        /* consume whitespace */
        while (*s == '\t' || *s == '\n' || *s == ' ' || *s == '\v' || *s == '\r') {
            if (*s == '\n') {
                P->line++;
            }
            s++;
        }

        /* consume comments */
        if (*s == '/' && *(s + 1) == '/') {
            s = strchr(s, '\n');
            if (!s) {
                luaL_error(L, "non-terminated comment");
            }

        } else if (*s == '/' && *(s + 1) == '*') {
            s += 2;

            for (;;) {
                if (s[0] == '\0') {
                    luaL_error(L, "non-terminated comment");
                } else if (s[0] == '*' && s[1] == '/') {
                    s += 2;
                    break;
                } else if (s[0] == '\n') {
                    P->line++;
                }
                s++;
            }

        } else if (*s == '\0') {
            tok->type = TOK_NIL;
            return 0;

        } else {
            break;
        }
    }

    P->prev = s;

    for (i = 0; i < sizeof(tok3) / sizeof(tok3[0]); i++) {
        if (s[0] == tok3[i][0] && s[1] == tok3[i][1] && s[2] == tok3[i][2]) {
            tok->type = (enum etoken)(TOK_3_BEGIN + 1 + i);
            P->next = s + 3;
            goto end;
        }
    }

    for (i = 0; i < sizeof(tok2) / sizeof(tok2[0]); i++) {
        if (s[0] == tok2[i][0] && s[1] == tok2[i][1]) {
            tok->type = (enum etoken)(TOK_2_BEGIN + 1 + i);
            P->next = s + 2;
            goto end;
        }
    }

    for (i = 0; i < sizeof(tok1) / sizeof(tok1[0]); i++) {
        if (s[0] == tok1[i]) {
            tok->type = (enum etoken)(TOK_1_BEGIN + 1 + i);
            P->next = s + 1;
            goto end;
        }
    }

    if (*s == '.' || *s == '-' || ('0' <= *s && *s <= '9')) {
        /* number */
        tok->type = TOK_NUMBER;

        /* split out the negative case so we get the full range of bits for
         * unsigned (eg to support 0xFFFFFFFF where sizeof(long) == 4)
         */
        if (*s == '-') {
            tok->integer = strtol(s, (char**)&s, 0);
        } else {
            tok->integer = strtoul(s, (char**)&s, 0);
        }

        while (*s == 'u' || *s == 'U' || *s == 'l' || *s == 'L') {
            s++;
        }

        P->next = s;
        goto end;

    } else if (*s == '\'' || *s == '\"') {
        /* "..." or '...' */
        char quote = *s;
        s++; /* jump over " */

        tok->type = TOK_STRING;
        tok->str = s;

        while (*s != quote) {
            if (*s == '\0' || (*s == '\\' && *(s + 1) == '\0')) {
                return luaL_error(L, "string not finished");
            }

            if (*s == '\\') {
                s++;
            }

            s++;
        }

        tok->size = s - tok->str;
        s++; /* jump over " */
        P->next = s;
        goto end;

    } else if (('a' <= *s && *s <= 'z') || ('A' <= *s && *s <= 'Z') || *s == '_') {
        /* tokens */
        tok->type = TOK_TOKEN;
        tok->str = s;

        while (('a' <= *s && *s <= 'z') || ('A' <= *s && *s <= 'Z') || *s == '_' ||
               ('0' <= *s && *s <= '9')) {
            s++;
        }

        tok->size = s - tok->str;
        P->next = s;
        goto end;

    } else {
        return luaL_error(L, "invalid character %d", P->line);
    }

end:
    /*fprintf(stderr, "token %d %d %.*s %.10s\n", tok->type, (int) tok->size, (tok->type
     * == TOK_TOKEN || tok->type == TOK_STRING) ? (int) tok->size : 0, tok->str,
     * P->next);*/
    return 1;
}

static void require_token(lua_State* L, struct parser* P, struct token* tok) {
    if (!next_token(L, P, tok)) {
        luaL_error(L, "unexpected end");
    }
}

static void check_token(lua_State* L, struct parser* P, int type, const char* str,
                        const char* err, ...) {
    struct token tok;
    if (!next_token(L, P, &tok) || tok.type != type ||
        (tok.type == TOK_TOKEN &&
         (tok.size != strlen(str) || memcmp(tok.str, str, tok.size) != 0))) {
        va_list ap;
        va_start(ap, err);
        lua_pushvfstring(L, err, ap);
        lua_error(L);
    }
}

static void put_back(struct parser* P) { P->next = P->prev; }

int64_t calculate_constant(lua_State* L, struct parser* P);

static int g_name_key;
static int g_front_name_key;
static int g_back_name_key;

#ifndef max
#define max(a, b) ((a) < (b) ? (b) : (a))
#endif

#ifndef min
#define min(a, b) ((a) < (b) ? (a) : (b))
#endif

enum test { TEST };

/* Parses an enum definition from after the open curly through to the close
 * curly. Expects the user table to be on the top of the stack
 */
static int parse_enum(lua_State* L, struct parser* P, struct ctype* type) {
    struct token tok;
    int value = -1;
    int ct_usr = lua_gettop(L);

    for (;;) {
        require_token(L, P, &tok);

        assert(lua_gettop(L) == ct_usr);

        if (tok.type == TOK_CLOSE_CURLY) {
            break;
        } else if (tok.type != TOK_TOKEN) {
            return luaL_error(L, "unexpected token in enum at line %d", P->line);
        }

        lua_pushlstring(L, tok.str, tok.size);

        require_token(L, P, &tok);

        if (tok.type == TOK_COMMA || tok.type == TOK_CLOSE_CURLY) {
            /* we have an auto calculated enum value */
            value++;
        } else if (tok.type == TOK_ASSIGN) {
            /* we have an explicit enum value */
            value = (int)calculate_constant(L, P);
            require_token(L, P, &tok);
        } else {
            return luaL_error(L, "unexpected token in enum at line %d", P->line);
        }

        assert(lua_gettop(L) == ct_usr + 1);

        /* add the enum value to the constants table */
        push_upval(L, &constants_key);
        lua_pushvalue(L, -2);
        lua_pushnumber(L, value);
        lua_rawset(L, -3);
        lua_pop(L, 1);

        assert(lua_gettop(L) == ct_usr + 1);

        /* add the enum value to the enum usr value table */
        lua_pushnumber(L, value);
        lua_rawset(L, ct_usr);

        if (tok.type == TOK_CLOSE_CURLY) {
            break;
        } else if (tok.type != TOK_COMMA) {
            return luaL_error(L, "unexpected token in enum at line %d", P->line);
        }
    }

    type->base_size = sizeof(enum test);
    type->align_mask = sizeof(enum test) - 1;

    assert(lua_gettop(L) == ct_usr);
    return 0;
}

static void calculate_member_position(lua_State* L, struct parser* P, struct ctype* ct,
                                      struct ctype* mt, int* pbit_offset,
                                      int* pbitfield_type) {
    int bit_offset = *pbit_offset;

    if (ct->type == UNION_TYPE) {
        size_t msize;

        if (mt->is_variable_struct || mt->is_variable_array) {
            luaL_error(L, "NYI: variable sized members in unions");
            return;

        } else if (mt->is_bitfield) {
            msize = (mt->align_mask + 1);
#ifdef _WIN32
            /* MSVC has a bug where it doesn't update the alignment of
             * a union for bitfield members. */
            mt->align_mask = 0;
#endif

        } else if (mt->is_array) {
            msize = mt->array_size * (mt->pointers > 1 ? sizeof(void*) : mt->base_size);

        } else {
            msize = mt->pointers ? sizeof(void*) : mt->base_size;
        }

        ct->base_size = max(ct->base_size, msize);

    } else if (mt->is_bitfield) {
        if (mt->has_member_name && mt->bit_size == 0) {
            luaL_error(L, "zero length bitfields must be unnamed on line %d", P->line);
        }

#if defined _WIN32
        /* MSVC uses a seperate storage unit for each size. This is aligned
         * before the first bitfield. :0 finishes up the storage unit using
         * the greater alignment of the storage unit or the type used with the
         * :0. This is equivalent to the :0 always creating a new storage
         * unit, but not necesserily using it yet.
         */

        if (*pbitfield_type == -1 && mt->bit_size == 0) {
            /* :0 not after a bitfield are ignored */
            return;
        }

        {
            int different_storage = mt->align_mask != *pbitfield_type;
            int no_room_left =
                    bit_offset + mt->bit_size > (mt->align_mask + 1) * CHAR_BIT;

            if (different_storage || no_room_left || !mt->bit_size) {
                ct->base_size += (bit_offset + CHAR_BIT - 1) / CHAR_BIT;
                bit_offset = 0;
                if (*pbitfield_type >= 0) {
                    ct->base_size = ALIGN_UP(ct->base_size, *pbitfield_type);
                }
                ct->base_size = ALIGN_UP(ct->base_size, mt->align_mask);
            }
        }

        mt->bit_offset = bit_offset;
        mt->offset = ct->base_size;

        *pbitfield_type = mt->align_mask;
        bit_offset += mt->bit_size;

#elif defined OS_OSX
        /* OSX doesn't use containers and bitfields are not aligned. So
         * bitfields never add any padding, except for :0 which still forces
         * an alignment based off the type used with the :0 */
        if (mt->bit_size) {
            mt->offset = ct->base_size;
            mt->bit_offset = bit_offset;
            bit_offset += mt->bit_size;
            ct->base_size += bit_offset / CHAR_BIT;
            bit_offset = bit_offset % CHAR_BIT;
        } else {
            ct->base_size += (bit_offset + CHAR_BIT - 1) / CHAR_BIT;
            ct->base_size = ALIGN_UP(ct->base_size, mt->align_mask);
            bit_offset = 0;
        }

        if (!mt->has_member_name) {
            /* unnamed bitfields don't update the struct alignment */
            mt->align_mask = 0;
        }

#elif defined __GNUC__
        /* GCC tries to pack bitfields in as close as much as possible, but
         * still making sure that they don't cross alignment boundaries.
         * :0 forces an alignment based off the type used with the :0
         */

        int bits_used =
                (ct->base_size - ALIGN_DOWN(ct->base_size, mt->align_mask)) * CHAR_BIT +
                bit_offset;
        int need_to_realign = bits_used + mt->bit_size > mt->base_size * CHAR_BIT;

        if (!mt->is_packed && (!mt->bit_size || need_to_realign)) {
            ct->base_size += (bit_offset + CHAR_BIT - 1) / CHAR_BIT;
            ct->base_size = ALIGN_UP(ct->base_size, mt->align_mask);
            bit_offset = 0;
        }

        mt->bit_offset = bit_offset;
        mt->offset = ct->base_size;

        bit_offset += mt->bit_size;
        ct->base_size += bit_offset / CHAR_BIT;
        bit_offset = bit_offset % CHAR_BIT;

        /* unnamed bitfields don't update the struct alignment */
        if (!mt->has_member_name) {
            mt->align_mask = 0;
        }
#else
#error
#endif

    } else {
        /* finish up the current bitfield storage unit */
        ct->base_size += (bit_offset + CHAR_BIT - 1) / CHAR_BIT;
        bit_offset = 0;

        if (*pbitfield_type >= 0) {
            ct->base_size = ALIGN_UP(ct->base_size, *pbitfield_type);
        }

        *pbitfield_type = -1;

        ct->base_size = ALIGN_UP(ct->base_size, mt->align_mask);
        mt->offset = ct->base_size;

        if (mt->is_variable_array) {
            ct->is_variable_struct = 1;
            ct->variable_increment = mt->pointers > 1 ? sizeof(void*) : mt->base_size;

        } else if (mt->is_variable_struct) {
            assert(!mt->variable_size_known && !mt->is_array && !mt->pointers);
            ct->base_size += mt->base_size;
            ct->is_variable_struct = 1;
            ct->variable_increment = mt->variable_increment;

        } else if (mt->is_array) {
            ct->base_size +=
                    mt->array_size * (mt->pointers > 1 ? sizeof(void*) : mt->base_size);

        } else {
            ct->base_size += mt->pointers ? sizeof(void*) : mt->base_size;
        }
    }

    /* increase the outer struct/union alignment if needed */
    if (mt->align_mask > (int)ct->align_mask) {
        ct->align_mask = mt->align_mask;
    }

    if (mt->has_bitfield || mt->is_bitfield) {
        ct->has_bitfield = 1;
    }

    *pbit_offset = bit_offset;
}

static int copy_submembers(lua_State* L, int to_usr, int from_usr, const struct ctype* ft,
                           int* midx) {
    struct ctype ct;
    int i, sublen;

    from_usr = lua_absindex(L, from_usr);
    to_usr = lua_absindex(L, to_usr);

    /* integer keys */
    sublen = (int)lua_rawlen(L, from_usr);
    for (i = 1; i <= sublen; i++) {
        lua_rawgeti(L, from_usr, i);

        ct = *(const struct ctype*)lua_touserdata(L, -1);
        ct.offset += ft->offset;
        lua_getuservalue(L, -1);

        push_ctype(L, -1, &ct);
        lua_rawseti(L, to_usr, (*midx)++);

        lua_pop(L, 2); /* ctype, user value */
    }

    /* string keys */
    lua_pushnil(L);
    while (lua_next(L, from_usr)) {
        if (lua_type(L, -2) == LUA_TSTRING) {
            struct ctype ct = *(const struct ctype*)lua_touserdata(L, -1);
            ct.offset += ft->offset;
            lua_getuservalue(L, -1);

            /* uservalue[sub_mname] = new_sub_mtype */
            lua_pushvalue(L, -3);
            push_ctype(L, -2, &ct);
            lua_rawset(L, to_usr);

            lua_pop(L, 1); /* remove submember user value */
        }
        lua_pop(L, 1);
    }

    return 0;
}

static int add_member(lua_State* L, int ct_usr, int mname, int mbr_usr,
                      const struct ctype* mt, int* midx) {
    ct_usr = lua_absindex(L, ct_usr);
    mname = lua_absindex(L, mname);

    push_ctype(L, mbr_usr, mt);

    /* usrvalue[mbr index] = pushed mtype */
    lua_pushvalue(L, -1);
    lua_rawseti(L, ct_usr, (*midx)++);

    /* set usrvalue[mname] = pushed mtype */
    lua_pushvalue(L, mname);
    lua_pushvalue(L, -2);
    lua_rawset(L, ct_usr);

    /* set usrvalue[mtype] = mname */
    lua_pushvalue(L, -1);
    lua_pushvalue(L, mname);
    lua_rawset(L, ct_usr);

    lua_pop(L, 1);

    return 0;
}

/* Parses a struct from after the open curly through to the close curly.
 */
static int parse_struct(lua_State* L, struct parser* P, int tmp_usr,
                        const struct ctype* ct) {
    struct token tok;
    int midx = 1;
    int top = lua_gettop(L);

    tmp_usr = lua_absindex(L, tmp_usr);

    /* parse members */
    for (;;) {
        struct ctype mbase;

        assert(lua_gettop(L) == top);

        /* see if we're at the end of the struct */
        require_token(L, P, &tok);
        if (tok.type == TOK_CLOSE_CURLY) {
            break;
        } else if (ct->is_variable_struct) {
            return luaL_error(
                    L, "can't have members after a variable sized member on line %d",
                    P->line);
        } else {
            put_back(P);
        }

        /* members are of the form
         * <base type> <arg>, <arg>, <arg>;
         * eg struct foo bar, *bar2[2];
         * mbase is 'struct foo'
         * mtype is '' then '*[2]'
         * mname is 'bar' then 'bar2'
         */

        parse_type(L, P, &mbase);

        for (;;) {
            struct token mname;
            struct ctype mt = mbase;

            memset(&mname, 0, sizeof(mname));

            if (ct->is_variable_struct) {
                return luaL_error(
                        L, "can't have members after a variable sized member on line %d",
                        P->line);
            }

            assert(lua_gettop(L) == top + 1);
            parse_argument(L, P, -1, &mt, &mname, NULL);
            assert(lua_gettop(L) == top + 2);

            if (!mt.is_defined && (mt.pointers - mt.is_array) == 0) {
                return luaL_error(L, "member type is undefined on line %d", P->line);
            }

            if (mt.type == VOID_TYPE && (mt.pointers - mt.is_array) == 0) {
                return luaL_error(L, "member type can not be void on line %d", P->line);
            }

            mt.has_member_name = (mname.size > 0);
            lua_pushlstring(L, mname.str, mname.size);

            add_member(L, tmp_usr, -1, -2, &mt, &midx);

            /* pop the usr value from push_argument and the member name */
            lua_pop(L, 2);
            assert(lua_gettop(L) == top + 1);

            require_token(L, P, &tok);
            if (tok.type == TOK_SEMICOLON) {
                break;
            } else if (tok.type != TOK_COMMA) {
                luaL_error(L, "unexpected token in struct definition on line %d",
                           P->line);
            }
        }

        /* pop the usr value from push_type */
        lua_pop(L, 1);
    }

    assert(lua_gettop(L) == top);
    return 0;
}

static int calculate_struct_offsets(lua_State* L, struct parser* P, int ct_usr,
                                    struct ctype* ct, int tmp_usr) {
    int i;
    int midx = 1;
    int sz = (int)lua_rawlen(L, tmp_usr);
    int bit_offset = 0;
    int bitfield_type = -1;

    ct_usr = lua_absindex(L, ct_usr);
    tmp_usr = lua_absindex(L, tmp_usr);

    for (i = 1; i <= sz; i++) {
        struct ctype mt;

        /* get the member type */
        lua_rawgeti(L, tmp_usr, i);
        mt = *(const struct ctype*)lua_touserdata(L, -1);

        /* get the member user table */
        lua_getuservalue(L, -1);

        /* get the member name */
        lua_pushvalue(L, -2);
        lua_rawget(L, tmp_usr);

        calculate_member_position(L, P, ct, &mt, &bit_offset, &bitfield_type);

        if (mt.has_member_name) {
            assert(!lua_isnil(L, -1));
            add_member(L, ct_usr, -1, -2, &mt, &midx);

        } else if (mt.type == STRUCT_TYPE || mt.type == UNION_TYPE) {
            /* With an unnamed member we copy all of the submembers into our
             * usr value adjusting the offset as necessary. Note ctypes are
             * immutable so need to push a new ctype to update the offset.
             */
            copy_submembers(L, ct_usr, -2, &mt, &midx);

        } else {
            /* We ignore unnamed members that aren't structs or unions. These
             * are there just to change the padding */
        }

        lua_pop(L, 3);
    }

    /* finish up the current bitfield storage unit */
    ct->base_size += (bit_offset + CHAR_BIT - 1) / CHAR_BIT;

    /* only void is allowed 0 size */
    if (ct->base_size == 0) {
        ct->base_size = 1;
    }

    ct->base_size = ALIGN_UP(ct->base_size, ct->align_mask);
    return 0;
}

/* copy over attributes that could be specified before the typedef eg
 * __attribute__(packed) const type_t */
static void instantiate_typedef(struct parser* P, struct ctype* tt,
                                const struct ctype* ft) {
    struct ctype pt = *tt;
    *tt = *ft;

    tt->const_mask |= pt.const_mask;
    tt->is_packed = pt.is_packed;

    if (tt->is_packed) {
        tt->align_mask = 0;
    } else {
        /* Instantiate the typedef in the current packing. This may be
         * further updated if a pointer is added or another alignment
         * attribute is applied. If pt.align_mask is already non-zero than an
         * increased alignment via __declspec(aligned(#)) has been set. */
        tt->align_mask = max(min(P->align_mask, tt->align_mask), pt.align_mask);
    }
}

/* this parses a struct or union starting with the optional
 * name before the opening brace
 * leaves the type usr value on the stack
 */
static int parse_record(lua_State* L, struct parser* P, struct ctype* ct) {
    struct token tok;
    int top = lua_gettop(L);

    require_token(L, P, &tok);

    /* name is optional */
    if (tok.type == TOK_TOKEN) {
        /* declaration */
        lua_pushlstring(L, tok.str, tok.size);

        assert(lua_gettop(L) == top + 1);

        /* lookup the name to see if we've seen this type before */
        push_upval(L, &types_key);
        lua_pushvalue(L, -2);
        lua_rawget(L, top + 2);

        assert(lua_gettop(L) == top + 3);

        if (lua_isnil(L, -1)) {
            lua_pop(L, 1);   /* pop the nil usr value */
            lua_newtable(L); /* the new usr table */

            /* stack layout is:
             * top+1: record name
             * top+2: types table
             * top+3: new usr table
             */

            lua_pushlightuserdata(L, &g_name_key);
            lua_pushvalue(L, top + 1);
            lua_rawset(L, top + 3); /* usr[name_key] = name */

            lua_pushvalue(L, top + 1);
            push_ctype(L, top + 3, ct);
            lua_rawset(L, top + 2); /* types[name] = new_ctype */

        } else {
            /* get the exsting declared type */
            const struct ctype* prevt = (const struct ctype*)lua_touserdata(L, top + 3);

            if (prevt->type != ct->type) {
                lua_getuservalue(L, top + 3);
                push_type_name(L, -1, ct);
                push_type_name(L, top + 3, prevt);
                luaL_error(L, "type '%s' previously declared as '%s'",
                           lua_tostring(L, -2), lua_tostring(L, -1));
            }

            instantiate_typedef(P, ct, prevt);

            /* replace the ctype with its usr value */
            lua_getuservalue(L, -1);
            lua_replace(L, -2);
        }

        /* remove the extra name and types table */
        lua_replace(L, -3);
        lua_pop(L, 1);

        assert(lua_gettop(L) == top + 1 && lua_istable(L, -1));

        /* if a name is given then we may be at the end of the string
         * eg for ffi.new('struct foo')
         */
        if (!next_token(L, P, &tok)) {
            return 0;
        }

    } else {
        /* create a new unnamed record */
        int num;

        /* get the next unnamed number */
        push_upval(L, &next_unnamed_key);
        num = lua_tointeger(L, -1);
        lua_pop(L, 1);

        /* increment the unnamed upval */
        lua_pushinteger(L, num + 1);
        set_upval(L, &next_unnamed_key);

        lua_newtable(L); /* the new usr table - leave on stack */

        /* usr[name_key] = num */
        lua_pushlightuserdata(L, &g_name_key);
        lua_pushfstring(L, "%d", num);
        lua_rawset(L, -3);
    }

    if (tok.type != TOK_OPEN_CURLY) {
        /* this may just be a declaration or use of the type as an argument or
         * member */
        put_back(P);
        return 0;
    }

    if (ct->is_defined) {
        return luaL_error(L, "redefinition in line %d", P->line);
    }

    assert(lua_gettop(L) == top + 1 && lua_istable(L, -1));

    if (ct->type == ENUM_TYPE) {
        parse_enum(L, P, ct);
    } else {
        /* we do a two stage parse, where we parse the content first and build up
         * the temp user table. We then iterate over that to calculate the offsets
         * and fill out ct_usr. This is so we can handle out of order members
         * (eg vtable) and attributes specified at the end of the struct.
         */
        lua_newtable(L);
        parse_struct(L, P, -1, ct);
        calculate_struct_offsets(L, P, -2, ct, -1);
        assert(lua_gettop(L) == top + 2 && lua_istable(L, -1));
        lua_pop(L, 1);
    }

    assert(lua_gettop(L) == top + 1 && lua_istable(L, -1));
    set_defined(L, -1, ct);
    assert(lua_gettop(L) == top + 1);
    return 0;
}

/* parses single or multi work built in types, and pushes it onto the stack */
static int parse_type_name(lua_State* L, struct parser* P) {
    struct token tok;
    int flags = 0;

    enum {
        UNSIGNED = 0x01,
        SIGNED = 0x02,
        LONG = 0x04,
        SHORT = 0x08,
        INT = 0x10,
        CHAR = 0x20,
        LONG_LONG = 0x40,
        INT8 = 0x80,
        INT16 = 0x100,
        INT32 = 0x200,
        INT64 = 0x400,
        DOUBLE = 0x800,
        FLOAT = 0x1000,
        COMPLEX = 0x2000,
    };

    require_token(L, P, &tok);

    /* we have to manually decode the builtin types since they can take up
     * more then one token
     */
    for (;;) {
        if (tok.type != TOK_TOKEN) {
            break;
        } else if (IS_LITERAL(tok, "unsigned")) {
            flags |= UNSIGNED;
        } else if (IS_LITERAL(tok, "signed")) {
            flags |= SIGNED;
        } else if (IS_LITERAL(tok, "short")) {
            flags |= SHORT;
        } else if (IS_LITERAL(tok, "char")) {
            flags |= CHAR;
        } else if (IS_LITERAL(tok, "long")) {
            flags |= (flags & LONG) ? LONG_LONG : LONG;
        } else if (IS_LITERAL(tok, "int")) {
            flags |= INT;
        } else if (IS_LITERAL(tok, "__int8")) {
            flags |= INT8;
        } else if (IS_LITERAL(tok, "__int16")) {
            flags |= INT16;
        } else if (IS_LITERAL(tok, "__int32")) {
            flags |= INT32;
        } else if (IS_LITERAL(tok, "__int64")) {
            flags |= INT64;
        } else if (IS_LITERAL(tok, "double")) {
            flags |= DOUBLE;
        } else if (IS_LITERAL(tok, "float")) {
            flags |= FLOAT;
        } else if (IS_LITERAL(tok, "complex") || IS_LITERAL(tok, "_Complex")) {
            flags |= COMPLEX;
        } else if (IS_LITERAL(tok, "register")) {
            /* ignore */
        } else {
            break;
        }

        if (!next_token(L, P, &tok)) {
            break;
        }
    }

    if (flags) {
        put_back(P);
    }

    if (flags & CHAR) {
        if (flags & SIGNED) {
            lua_pushliteral(L, "int8_t");
        } else if (flags & UNSIGNED) {
            lua_pushliteral(L, "uint8_t");
        } else {
            lua_pushstring(L, (((char)-1) > 0) ? "uint8_t" : "int8_t");
        }

    } else if (flags & INT8) {
        lua_pushstring(L, (flags & UNSIGNED) ? "uint8_t" : "int8_t");
    } else if (flags & INT16) {
        lua_pushstring(L, (flags & UNSIGNED) ? "uint16_t" : "int16_t");
    } else if (flags & INT32) {
        lua_pushstring(L, (flags & UNSIGNED) ? "uint32_t" : "int32_t");
    } else if (flags & (INT64 | LONG_LONG)) {
        lua_pushstring(L, (flags & UNSIGNED) ? "uint64_t" : "int64_t");

    } else if (flags & COMPLEX) {
        if (flags & LONG) {
            lua_pushliteral(L, "complex long double");
        } else if (flags & FLOAT) {
            lua_pushliteral(L, "complex float");
        } else {
            lua_pushliteral(L, "complex double");
        }

    } else if (flags & DOUBLE) {
        if (flags & LONG) {
            lua_pushliteral(L, "long double");
        } else {
            lua_pushliteral(L, "double");
        }

    } else if (flags & FLOAT) {
        lua_pushliteral(L, "float");

    } else if (flags & SHORT) {
#define SHORT_TYPE(u)                 \
    (sizeof(short) == sizeof(int64_t) \
             ? u "int64_t"            \
             : sizeof(short) == sizeof(int32_t) ? u "int32_t" : u "int16_t")
        if (flags & UNSIGNED) {
            lua_pushstring(L, SHORT_TYPE("u"));
        } else {
            lua_pushstring(L, SHORT_TYPE(""));
        }
#undef SHORT_TYPE

    } else if (flags & LONG) {
#define LONG_TYPE(u) (sizeof(long) == sizeof(int64_t) ? u "int64_t" : u "int32_t")
        if (flags & UNSIGNED) {
            lua_pushstring(L, LONG_TYPE("u"));
        } else {
            lua_pushstring(L, LONG_TYPE(""));
        }
#undef LONG_TYPE

    } else if (flags) {
#define INT_TYPE(u)                 \
    (sizeof(int) == sizeof(int64_t) \
             ? u "int64_t"          \
             : sizeof(int) == sizeof(int32_t) ? u "int32_t" : u "int16_t")
        if (flags & UNSIGNED) {
            lua_pushstring(L, INT_TYPE("u"));
        } else {
            lua_pushstring(L, INT_TYPE(""));
        }
#undef INT_TYPE

    } else {
        lua_pushlstring(L, tok.str, tok.size);
    }

    return 0;
}

/* parse_attribute parses a token to see if it is an attribute. It may then
 * parse some following tokens to decode the attribute setting the appropriate
 * fields in ct. It will return 1 if the token was used (and possibly some
 * more following it) or 0 if not. If the token was used, the next token must
 * be retrieved using next_token/require_token.
 */
static int parse_attribute(lua_State* L, struct parser* P, struct token* tok,
                           struct ctype* ct, struct parser* asmname) {
    if (tok->type != TOK_TOKEN) {
        return 0;

    } else if (asmname && (IS_LITERAL(*tok, "__asm__") || IS_LITERAL(*tok, "__asm"))) {
        check_token(L, P, TOK_OPEN_PAREN, NULL,
                    "unexpected token after __asm__ on line %d", P->line);
        *asmname = *P;

        require_token(L, P, tok);
        while (tok->type == TOK_STRING) {
            require_token(L, P, tok);
        }

        if (tok->type != TOK_CLOSE_PAREN) {
            luaL_error(L, "unexpected token after __asm__ on line %d", P->line);
        }
        return 1;

    } else if (IS_LITERAL(*tok, "__attribute__") || IS_LITERAL(*tok, "__declspec")) {
        int parens = 1;
        check_token(L, P, TOK_OPEN_PAREN, NULL,
                    "expected parenthesis after __attribute__ or __declspec on line %d",
                    P->line);

        for (;;) {
            require_token(L, P, tok);
            if (tok->type == TOK_OPEN_PAREN) {
                parens++;
            } else if (tok->type == TOK_CLOSE_PAREN) {
                if (--parens == 0) {
                    break;
                }

            } else if (tok->type != TOK_TOKEN) {
                /* ignore unknown symbols within parentheses */

            } else if (IS_LITERAL(*tok, "align") || IS_LITERAL(*tok, "aligned") ||
                       IS_LITERAL(*tok, "__aligned__")) {
                unsigned align = 0;
                require_token(L, P, tok);

                switch (tok->type) {
                    case TOK_CLOSE_PAREN:
                        align = ALIGNED_DEFAULT;
                        put_back(P);
                        break;

                    case TOK_OPEN_PAREN:
                        require_token(L, P, tok);

                        if (tok->type != TOK_NUMBER) {
                            luaL_error(L, "expected align(#) on line %d", P->line);
                        }

                        switch (tok->integer) {
                            case 1:
                                align = 0;
                                break;
                            case 2:
                                align = 1;
                                break;
                            case 4:
                                align = 3;
                                break;
                            case 8:
                                align = 7;
                                break;
                            case 16:
                                align = 15;
                                break;
                            default:
                                luaL_error(L, "unsupported align size on line %d",
                                           P->line);
                        }

                        check_token(L, P, TOK_CLOSE_PAREN, NULL,
                                    "expected align(#) on line %d", P->line);
                        break;

                    default:
                        luaL_error(L, "expected align(#) on line %d", P->line);
                }

                /* __attribute__(aligned(#)) is only supposed to increase alignment */
                ct->align_mask = max(align, ct->align_mask);

            } else if (IS_LITERAL(*tok, "packed") || IS_LITERAL(*tok, "__packed__")) {
                ct->align_mask = 0;
                ct->is_packed = 1;

            } else if (IS_LITERAL(*tok, "mode") || IS_LITERAL(*tok, "__mode__")) {
                check_token(L, P, TOK_OPEN_PAREN, NULL, "expected mode(MODE) on line %d",
                            P->line);

                require_token(L, P, tok);
                if (tok->type != TOK_TOKEN) {
                    luaL_error(L, "expected mode(MODE) on line %d", P->line);
                }

                if (ct->type == FLOAT_TYPE || ct->type == DOUBLE_TYPE) {
                    struct {
                        char ch;
                        float v;
                    } af;
                    struct {
                        char ch;
                        double v;
                    } ad;

                    if (IS_LITERAL(*tok, "SF") || IS_LITERAL(*tok, "__SF__")) {
                        ct->type = FLOAT_TYPE;
                        ct->base_size = sizeof(float);
                        ct->align_mask = ALIGNOF(af);

                    } else if (IS_LITERAL(*tok, "DF") || IS_LITERAL(*tok, "__DF__")) {
                        ct->type = DOUBLE_TYPE;
                        ct->base_size = sizeof(double);
                        ct->align_mask = ALIGNOF(ad);

                    } else {
                        luaL_error(L, "unexpected mode on line %d", P->line);
                    }

                } else {
                    struct {
                        char ch;
                        uint16_t v;
                    } a16;
                    struct {
                        char ch;
                        uint32_t v;
                    } a32;
                    struct {
                        char ch;
                        uint64_t v;
                    } a64;

                    if (IS_LITERAL(*tok, "QI") || IS_LITERAL(*tok, "__QI__") ||
                        IS_LITERAL(*tok, "byte") || IS_LITERAL(*tok, "__byte__")) {
                        ct->type = INT8_TYPE;
                        ct->base_size = sizeof(uint8_t);
                        ct->align_mask = 0;

                    } else if (IS_LITERAL(*tok, "HI") || IS_LITERAL(*tok, "__HI__")) {
                        ct->type = INT16_TYPE;
                        ct->base_size = sizeof(uint16_t);
                        ct->align_mask = ALIGNOF(a16);

                    } else if (IS_LITERAL(*tok, "SI") || IS_LITERAL(*tok, "__SI__")) {
                        ct->type = INT32_TYPE;
                        ct->base_size = sizeof(uint32_t);
                        ct->align_mask = ALIGNOF(a32);

                    } else if (IS_LITERAL(*tok, "DI") || IS_LITERAL(*tok, "__DI__")) {
                        ct->type = INT64_TYPE;
                        ct->base_size = sizeof(uint64_t);
                        ct->align_mask = ALIGNOF(a64);

                    } else {
                        luaL_error(L, "unexpected mode on line %d", P->line);
                    }
                }

                check_token(L, P, TOK_CLOSE_PAREN, NULL, "expected mode(MODE) on line %d",
                            P->line);

            } else if (IS_LITERAL(*tok, "cdecl") || IS_LITERAL(*tok, "__cdecl__")) {
                ct->calling_convention = C_CALL;

            } else if (IS_LITERAL(*tok, "fastcall") || IS_LITERAL(*tok, "__fastcall__")) {
                ct->calling_convention = FAST_CALL;

            } else if (IS_LITERAL(*tok, "stdcall") || IS_LITERAL(*tok, "__stdcall__")) {
                ct->calling_convention = STD_CALL;
            }
            /* ignore unknown tokens within parentheses */
        }
        return 1;

    } else if (IS_LITERAL(*tok, "__cdecl")) {
        ct->calling_convention = C_CALL;
        return 1;

    } else if (IS_LITERAL(*tok, "__fastcall")) {
        ct->calling_convention = FAST_CALL;
        return 1;

    } else if (IS_LITERAL(*tok, "__stdcall")) {
        ct->calling_convention = STD_CALL;
        return 1;

    } else if (IS_LITERAL(*tok, "__extension__") || IS_LITERAL(*tok, "extern")) {
        /* ignore */
        return 1;

    } else {
        return 0;
    }
}

/* parses out the base type of a type expression in a function declaration,
 * struct definition, typedef etc
 *
 * leaves the usr value of the type on the stack
 */
int parse_type(lua_State* L, struct parser* P, struct ctype* ct) {
    struct token tok;
    int top = lua_gettop(L);

    memset(ct, 0, sizeof(*ct));

    require_token(L, P, &tok);

    /* get function attributes before the return type */
    while (parse_attribute(L, P, &tok, ct, NULL)) {
        require_token(L, P, &tok);
    }

    /* get const/volatile before the base type */
    for (;;) {
        if (tok.type != TOK_TOKEN) {
            return luaL_error(L, "unexpected value before type name on line %d", P->line);

        } else if (IS_CONST(tok)) {
            ct->const_mask = 1;
            require_token(L, P, &tok);

        } else if (IS_VOLATILE(tok) || IS_RESTRICT(tok)) {
            /* ignored for now */
            require_token(L, P, &tok);

        } else {
            break;
        }
    }

    /* get base type */
    if (tok.type != TOK_TOKEN) {
        return luaL_error(L, "unexpected value before type name on line %d", P->line);

    } else if (IS_LITERAL(tok, "struct")) {
        ct->type = STRUCT_TYPE;
        parse_record(L, P, ct);

    } else if (IS_LITERAL(tok, "union")) {
        ct->type = UNION_TYPE;
        parse_record(L, P, ct);

    } else if (IS_LITERAL(tok, "enum")) {
        ct->type = ENUM_TYPE;
        parse_record(L, P, ct);

    } else {
        put_back(P);

        /* lookup type */
        push_upval(L, &types_key);
        parse_type_name(L, P);
        lua_rawget(L, -2);
        lua_remove(L, -2);

        if (lua_isnil(L, -1)) {
            lua_pushlstring(L, tok.str, tok.size);
            return luaL_error(L, "unknown type %s on line %d", lua_tostring(L, -1),
                              P->line);
        }

        instantiate_typedef(P, ct, (const struct ctype*)lua_touserdata(L, -1));

        /* we only want the usr tbl from the ctype in the types tbl */
        lua_getuservalue(L, -1);
        lua_replace(L, -2);
    }

    while (next_token(L, P, &tok)) {
        if (tok.type != TOK_TOKEN) {
            put_back(P);
            break;

        } else if (IS_CONST(tok) || IS_VOLATILE(tok)) {
            /* ignore for now */

        } else {
            put_back(P);
            break;
        }
    }

    assert(lua_gettop(L) == top + 1 && (lua_istable(L, -1) || lua_isnil(L, -1)));
    return 0;
}

enum name_type {
    BOTH,
    FRONT,
    BACK,
};

static void append_type_name(luaL_Buffer* B, int usr, const struct ctype* ct,
                             enum name_type type) {
    size_t i;
    lua_State* L = B->L;

    usr = lua_absindex(L, usr);

    if (type == FRONT || type == BOTH) {
        if (ct->type != FUNCTION_PTR_TYPE && (ct->const_mask & (1 << ct->pointers))) {
            luaL_addstring(B, "const ");
        }

        if (ct->is_unsigned) {
            luaL_addstring(B, "unsigned ");
        }

        switch (ct->type) {
            case ENUM_TYPE:
                luaL_addstring(B, "enum ");
                goto get_name;

            case STRUCT_TYPE:
                luaL_addstring(B, "struct ");
                goto get_name;

            case UNION_TYPE:
                luaL_addstring(B, "union ");
                goto get_name;

            get_name:
                lua_pushlightuserdata(L, &g_name_key);
                lua_rawget(L, usr);
                luaL_addvalue(B);
                break;

            case FUNCTION_TYPE:
            case FUNCTION_PTR_TYPE:
                lua_pushlightuserdata(L, &g_front_name_key);
                lua_rawget(L, usr);
                luaL_addvalue(B);
                break;

            case VOID_TYPE:
                luaL_addstring(B, "void");
                break;
            case BOOL_TYPE:
                luaL_addstring(B, "bool");
                break;
            case DOUBLE_TYPE:
                luaL_addstring(B, "double");
                break;
            case LONG_DOUBLE_TYPE:
                luaL_addstring(B, "long double");
                break;
            case FLOAT_TYPE:
                luaL_addstring(B, "float");
                break;
            case COMPLEX_LONG_DOUBLE_TYPE:
                luaL_addstring(B, "long complex double");
                break;
            case COMPLEX_DOUBLE_TYPE:
                luaL_addstring(B, "complex double");
                break;
            case COMPLEX_FLOAT_TYPE:
                luaL_addstring(B, "complex float");
                break;
            case INT8_TYPE:
                luaL_addstring(B, "char");
                break;
            case INT16_TYPE:
                luaL_addstring(B, "short");
                break;
            case INT32_TYPE:
                luaL_addstring(B, "int");
                break;
            case INT64_TYPE:
                luaL_addstring(B, "long long");
                break;

            case INTPTR_TYPE:
                if (sizeof(intptr_t) == sizeof(int32_t)) {
                    luaL_addstring(B, "long");
                } else if (sizeof(intptr_t) == sizeof(int64_t)) {
                    luaL_addstring(B, "long long");
                } else {
                    luaL_error(L, "internal error - bad type");
                }
                break;

            default:
                luaL_error(L, "internal error - bad type %d", ct->type);
        }

        for (i = 0; i < ct->pointers - ct->is_array; i++) {
            luaL_addchar(B, '*');
            if (ct->const_mask & (1 << (ct->pointers - i - 1))) {
                luaL_addstring(B, " const");
            }
        }
    }

    if (type == BOTH || type == BACK) {
        if (ct->is_reference) {
            luaL_addstring(B, "(&)");
        }

        if (ct->is_variable_array && !ct->variable_size_known) {
            luaL_addstring(B, "[?]");
        } else if (ct->is_array) {
            lua_pushfstring(L, "[%d]", (int)ct->array_size);
            luaL_addvalue(B);
        }

        if (ct->type == FUNCTION_PTR_TYPE || ct->type == FUNCTION_TYPE) {
            lua_pushlightuserdata(L, &g_back_name_key);
            lua_rawget(L, usr);
            luaL_addvalue(B);
        }

        if (ct->is_bitfield) {
            lua_pushfstring(L, " : %d", (int)ct->bit_size);
            luaL_addvalue(B);
        }
    }
}

void push_type_name(lua_State* L, int usr, const struct ctype* ct) {
    luaL_Buffer B;
    usr = lua_absindex(L, usr);
    luaL_buffinit(L, &B);
    append_type_name(&B, usr, ct, BOTH);
    luaL_pushresult(&B);
}

static void push_function_type_strings(lua_State* L, int usr, const struct ctype* ct) {
    size_t i, args;
    luaL_Buffer B;
    int top = lua_gettop(L);
    const struct ctype* ret_ct;

    int arg_ct = top + 3;
    int arg_usr = top + 4;
    int ret_usr = top + 6;

    usr = lua_absindex(L, usr);

    /* return type */
    lua_settop(L, top + 4); /* room for two returns and two temp positions */
    lua_rawgeti(L, usr, 0);
    lua_getuservalue(L, -1);
    ret_ct = (const struct ctype*)lua_touserdata(L, -2);

    luaL_buffinit(L, &B);
    append_type_name(&B, ret_usr, ret_ct, FRONT);

    if (ret_ct->type != FUNCTION_TYPE && ret_ct->type != FUNCTION_PTR_TYPE) {
        luaL_addchar(&B, ' ');
    }

    switch (ct->calling_convention) {
        case STD_CALL:
            luaL_addstring(&B, "(__stdcall *");
            break;
        case FAST_CALL:
            luaL_addstring(&B, "(__fastcall *");
            break;
        case C_CALL:
            luaL_addstring(&B, "(*");
            break;
        default:
            luaL_error(L, "internal error - unknown calling convention");
    }

    luaL_pushresult(&B);
    lua_replace(L, top + 1);

    luaL_buffinit(L, &B);
    luaL_addstring(&B, ")(");

    /* arguments */
    args = lua_rawlen(L, usr);
    for (i = 1; i <= args; i++) {
        if (i > 1) {
            luaL_addstring(&B, ", ");
        }

        /* note push the arg and user value below the indexes used by the buffer
         * and use indexes relative to top to avoid problems due to the buffer
         * system pushing a variable number of arguments onto the stack */
        lua_rawgeti(L, usr, (int)i);
        lua_replace(L, arg_ct);
        lua_getuservalue(L, arg_ct);
        lua_replace(L, arg_usr);
        append_type_name(&B, arg_usr, (const struct ctype*)lua_touserdata(L, arg_ct),
                         BOTH);
    }

    luaL_addstring(&B, ")");
    append_type_name(&B, ret_usr, ret_ct, BACK);
    luaL_pushresult(&B);
    lua_replace(L, top + 2);

    lua_settop(L, top + 2);
    assert(lua_isstring(L, top + 1) && lua_isstring(L, top + 2));
}

/* parses from after the opening paranthesis to after the closing parenthesis */
static void parse_function_arguments(lua_State* L, struct parser* P, int ct_usr,
                                     struct ctype* ct) {
    struct token tok;
    int args = 0;
    int top = lua_gettop(L);

    ct_usr = lua_absindex(L, ct_usr);

    for (;;) {
        require_token(L, P, &tok);

        if (tok.type == TOK_CLOSE_PAREN) {
            break;
        }

        if (args) {
            if (tok.type != TOK_COMMA) {
                luaL_error(L, "unexpected token in function argument %d on line %d", args,
                           P->line);
            }

            require_token(L, P, &tok);
        }

        if (tok.type == TOK_VA_ARG) {
            ct->has_var_arg = true;
            check_token(L, P, TOK_CLOSE_PAREN, "",
                        "unexpected token after ... in function on line %d", P->line);
            break;

        } else if (tok.type == TOK_TOKEN) {
            struct ctype at;

            put_back(P);
            parse_type(L, P, &at);
            parse_argument(L, P, -1, &at, NULL, NULL);

            assert(lua_gettop(L) == top + 2);

            /* array arguments are just treated as their base pointer type */
            at.is_array = 0;

            /* check for the c style int func(void) and error on other uses of arguments
             * of type void */
            if (at.type == VOID_TYPE && at.pointers == 0) {
                if (args) {
                    luaL_error(L, "can't have argument of type void on line %d", P->line);
                }

                check_token(L, P, TOK_CLOSE_PAREN, "",
                            "unexpected void in function on line %d", P->line);
                lua_pop(L, 2);
                break;
            }

            push_ctype(L, -1, &at);
            lua_rawseti(L, ct_usr, ++args);

            lua_pop(L, 2); /* parse_type and parse_argument at_usr */

        } else {
            luaL_error(L, "unexpected token in function argument %d on line %d", args + 1,
                       P->line);
        }
    }

    assert(lua_gettop(L) == top);
}

static int max_bitfield_size(int type) {
    switch (type) {
        case BOOL_TYPE:
            return 1;
        case INT8_TYPE:
            return 8;
        case INT16_TYPE:
            return 16;
        case INT32_TYPE:
        case ENUM_TYPE:
            return 32;
        case INT64_TYPE:
            return 64;
        default:
            return -1;
    }
}

static struct ctype* parse_argument2(lua_State* L, struct parser* P, int ct_usr,
                                     struct ctype* ct, struct token* name,
                                     struct parser* asmname);

/* parses from after the first ( in a function declaration or function pointer
 * can be one of:
 * void foo(...) before ...
 * void (foo)(...) before foo
 * void (* <>)(...) before <> which is the inner type
 */
static struct ctype* parse_function(lua_State* L, struct parser* P, int ct_usr,
                                    struct ctype* ct, struct token* name,
                                    struct parser* asmname) {
    /* We have a function pointer or a function. The usr table will
     * get replaced by the canonical one (if there is one) in
     * find_canonical_usr after all the arguments and returns have
     * been parsed. */
    struct token tok;
    int top = lua_gettop(L);
    struct ctype* ret;

    lua_newtable(L);
    ret = push_ctype(L, ct_usr, ct);
    lua_rawseti(L, -2, 0);
    ct_usr = lua_gettop(L);

    memset(ct, 0, sizeof(*ct));
    ct->base_size = sizeof(void (*)());
    ct->align_mask = min(FUNCTION_ALIGN_MASK, P->align_mask);
    ct->type = FUNCTION_TYPE;
    ct->is_defined = 1;

    if (name->type == TOK_NIL) {
        for (;;) {
            require_token(L, P, &tok);

            if (tok.type == TOK_STAR) {
                if (ct->type == FUNCTION_TYPE) {
                    ct->type = FUNCTION_PTR_TYPE;
                } else if (ct->pointers == POINTER_MAX) {
                    luaL_error(L,
                               "maximum number of pointer derefs reached - use a struct "
                               "to break up the pointers on line %d",
                               P->line);
                } else {
                    ct->pointers++;
                    ct->const_mask <<= 1;
                }

            } else if (parse_attribute(L, P, &tok, ct, asmname)) {
                /* parse_attribute sets the appropriate fields */

            } else {
                /* call parse_argument to handle the inner contents
                 * e.g. the <> in "void (* <>) (...)". Note that the
                 * inner contents can itself be a function, a function
                 * ptr, array, etc (e.g. "void (*signal(int sig, void
                 * (*func)(int)))(int)" ).
                 */
                put_back(P);
                ct = parse_argument2(L, P, ct_usr, ct, name, asmname);
                break;
            }
        }

        check_token(L, P, TOK_CLOSE_PAREN, NULL,
                    "unexpected token in function on line %d", P->line);
        check_token(L, P, TOK_OPEN_PAREN, NULL, "unexpected token in function on line %d",
                    P->line);
    }

    parse_function_arguments(L, P, ct_usr, ct);

    /* if we have an inner function then set the outer function ptr as its
     * return type and return the inner function
     * e.g. for void (* <signal(int, void (*)(int))> )(int) inner is
     * surrounded by <>, return type is void (*)(int)
     */
    if (lua_gettop(L) == ct_usr + 1) {
        lua_replace(L, ct_usr);
    }

    assert(lua_gettop(L) == top + 1 && lua_istable(L, -1));
    return ret;
}

static struct ctype* parse_argument2(lua_State* L, struct parser* P, int ct_usr,
                                     struct ctype* ct, struct token* name,
                                     struct parser* asmname) {
    struct token tok;
    int top = lua_gettop(L);
    int ft_usr = 0;

    luaL_checkstack(L, 10, "function too complex");
    ct_usr = lua_absindex(L, ct_usr);

    for (;;) {
        if (!next_token(L, P, &tok)) {
            /* we've reached the end of the string */
            break;

        } else if (tok.type == TOK_STAR) {
            if (ct->pointers == POINTER_MAX) {
                luaL_error(L,
                           "maximum number of pointer derefs reached - use a struct to "
                           "break up the pointers on line %d",
                           P->line);
            }

            ct->pointers++;
            ct->const_mask <<= 1;

            /* __declspec(align(#)) may come before the type in a member */
            if (!ct->is_packed) {
                ct->align_mask = max(min(PTR_ALIGN_MASK, P->align_mask), ct->align_mask);
            }

        } else if (tok.type == TOK_REFERENCE) {
            luaL_error(L, "NYI: c++ reference types");

        } else if (parse_attribute(L, P, &tok, ct, asmname)) {
            /* parse attribute has filled out appropriate fields in type */

        } else if (tok.type == TOK_OPEN_PAREN) {
            ct = parse_function(L, P, ct_usr, ct, name, asmname);
            ft_usr = lua_gettop(L);

        } else if (tok.type == TOK_OPEN_SQUARE) {
            /* array */
            if (ct->pointers == POINTER_MAX) {
                luaL_error(L,
                           "maximum number of pointer derefs reached - use a struct to "
                           "break up the pointers");
            }
            ct->is_array = 1;
            ct->pointers++;
            ct->const_mask <<= 1;
            require_token(L, P, &tok);

            if (ct->pointers == 1 && !ct->is_defined) {
                luaL_error(L, "array of undefined type on line %d", P->line);
            }

            if (ct->is_variable_struct || ct->is_variable_array) {
                luaL_error(L, "can't have an array of a variably sized type on line %d",
                           P->line);
            }

            if (tok.type == TOK_QUESTION) {
                ct->is_variable_array = 1;
                ct->variable_increment =
                        (ct->pointers > 1) ? sizeof(void*) : ct->base_size;
                check_token(L, P, TOK_CLOSE_SQUARE, "",
                            "invalid character in array on line %d", P->line);

            } else if (tok.type == TOK_CLOSE_SQUARE) {
                ct->array_size = 0;

            } else if (tok.type == TOK_TOKEN && IS_RESTRICT(tok)) {
                /* odd gcc extension foo[__restrict] for arguments */
                ct->array_size = 0;
                check_token(L, P, TOK_CLOSE_SQUARE, "",
                            "invalid character in array on line %d", P->line);

            } else {
                int64_t asize;
                put_back(P);
                asize = calculate_constant(L, P);
                if (asize < 0) {
                    luaL_error(L, "array size can not be negative on line %d", P->line);
                }
                ct->array_size = (size_t)asize;
                check_token(L, P, TOK_CLOSE_SQUARE, "",
                            "invalid character in array on line %d", P->line);
            }

        } else if (tok.type == TOK_COLON) {
            int64_t bsize = calculate_constant(L, P);

            if (ct->pointers || bsize < 0 || bsize > max_bitfield_size(ct->type)) {
                luaL_error(L, "invalid bitfield on line %d", P->line);
            }

            ct->is_bitfield = 1;
            ct->bit_size = (unsigned)bsize;

        } else if (tok.type != TOK_TOKEN) {
            /* we've reached the end of the declaration */
            put_back(P);
            break;

        } else if (IS_CONST(tok)) {
            ct->const_mask |= 1;

        } else if (IS_VOLATILE(tok) || IS_RESTRICT(tok)) {
            /* ignored for now */

        } else {
            *name = tok;
        }
    }

    assert((ft_usr == 0 && lua_gettop(L) == top) ||
           (lua_gettop(L) == top + 1 && ft_usr == top + 1 &&
            (lua_istable(L, -1) || lua_isnil(L, -1))));
    return ct;
}

static void find_canonical_usr(lua_State* L, int ct_usr, const struct ctype* ct) {
    struct ctype rt;
    int top = lua_gettop(L);
    int types;

    if (ct->type != FUNCTION_PTR_TYPE && ct->type != FUNCTION_TYPE) {
        return;
    }

    luaL_checkstack(L, 10, "function too complex");
    ct_usr = lua_absindex(L, ct_usr);

    /* check to see if we already have the canonical usr table */
    lua_pushlightuserdata(L, &g_name_key);
    lua_rawget(L, ct_usr);
    if (!lua_isnil(L, -1)) {
        lua_pop(L, 1);
        assert(top == lua_gettop(L));
        return;
    }
    lua_pop(L, 1);

    assert(top == lua_gettop(L));

    /* first canonize the return type */
    lua_rawgeti(L, ct_usr, 0);
    rt = *(struct ctype*)lua_touserdata(L, -1);
    lua_getuservalue(L, -1);
    find_canonical_usr(L, -1, &rt);
    push_ctype(L, -1, &rt);
    lua_rawseti(L, ct_usr, 0);
    lua_pop(L, 2); /* return ctype and usr */

    assert(top == lua_gettop(L));

    /* look up the type string in the types table */
    push_upval(L, &types_key);
    types = lua_gettop(L);

    push_function_type_strings(L, ct_usr, ct);
    lua_pushvalue(L, -2);
    lua_pushvalue(L, -2);
    lua_concat(L, 2);

    lua_pushvalue(L, -1);
    lua_rawget(L, types);

    assert(lua_gettop(L) == types + 4 && types == top + 1);
    /* stack: types, front, back, both, looked up value */

    if (lua_isnil(L, -1)) {
        lua_pop(L, 1);

        lua_pushlightuserdata(L, &g_front_name_key);
        lua_pushvalue(L, -4);
        lua_rawset(L, ct_usr);

        lua_pushlightuserdata(L, &g_back_name_key);
        lua_pushvalue(L, -3);
        lua_rawset(L, ct_usr);

        lua_pushlightuserdata(L, &g_name_key);
        lua_pushvalue(L, -2);
        lua_rawset(L, ct_usr);

        lua_pushvalue(L, -1);
        push_ctype(L, ct_usr, ct);
        lua_rawset(L, types);
    } else {
        lua_getuservalue(L, -1);
        lua_replace(L, ct_usr);
        lua_pop(L, 1);
    }

    lua_pop(L, 4);
    assert(top == lua_gettop(L) && types == top + 1);
}

/* parses after the main base type of a typedef, function argument or
 * struct/union member
 * eg for const void* bar[3] the base type is void with the subtype so far of
 * const, this parses the "* bar[3]" and updates the type argument
 *
 * ct_usr and type must be as filled out by parse_type
 *
 * pushes the updated user value on the top of the stack
 */
void parse_argument(lua_State* L, struct parser* P, int ct_usr, struct ctype* ct,
                    struct token* pname, struct parser* asmname) {
    struct token tok, name;
    int top = lua_gettop(L);

    memset(&name, 0, sizeof(name));
    parse_argument2(L, P, ct_usr, ct, &name, asmname);

    for (;;) {
        if (!next_token(L, P, &tok)) {
            break;
        } else if (parse_attribute(L, P, &tok, ct, asmname)) {
            /* parse_attribute sets the appropriate fields */
        } else {
            put_back(P);
            break;
        }
    }

    if (lua_gettop(L) == top) {
        lua_pushvalue(L, ct_usr);
    }

    find_canonical_usr(L, -1, ct);

    if (pname) {
        *pname = name;
    }
}

static void parse_typedef(lua_State* L, struct parser* P) {
    struct token tok;
    struct ctype base_type;
    int top = lua_gettop(L);

    parse_type(L, P, &base_type);

    for (;;) {
        struct ctype arg_type = base_type;
        struct token name;

        memset(&name, 0, sizeof(name));

        assert(lua_gettop(L) == top + 1);
        parse_argument(L, P, -1, &arg_type, &name, NULL);
        assert(lua_gettop(L) == top + 2);

        if (!name.size) {
            luaL_error(L, "Can't have a typedef without a name on line %d", P->line);
        } else if (arg_type.is_variable_array) {
            luaL_error(L, "Can't typedef a variable length array on line %d", P->line);
        }

        push_upval(L, &types_key);
        lua_pushlstring(L, name.str, name.size);
        push_ctype(L, -3, &arg_type);
        lua_rawset(L, -3);
        lua_pop(L, 2); /* types and parse_argument usr tbl */

        require_token(L, P, &tok);

        if (tok.type == TOK_SEMICOLON) {
            break;
        } else if (tok.type != TOK_COMMA) {
            luaL_error(L, "Unexpected character in typedef on line %d", P->line);
        }
    }

    lua_pop(L, 1); /* parse_type usr tbl */
    assert(lua_gettop(L) == top);
}

static bool is_hex(char ch) {
    return ('0' <= ch && ch <= '9') || ('a' <= ch && ch <= 'f') ||
           ('A' <= ch && ch <= 'F');
}

static bool is_digit(char ch) { return '0' <= ch && ch <= '9'; }

static int from_hex(char ch) {
    if (ch >= 'a') {
        return ch - 'a' + 10;
    } else if (ch >= 'A') {
        return ch - 'A' + 10;
    } else {
        return ch - '0';
    }
}

static void push_strings(lua_State* L, struct parser* P) {
    luaL_Buffer B;
    luaL_buffinit(L, &B);

    for (;;) {
        const char *p, *e;
        char *t, *s;
        struct token tok;

        require_token(L, P, &tok);
        if (tok.type != TOK_STRING) {
            break;
        }

        p = tok.str;
        e = p + tok.size;

        t = luaL_prepbuffsize(&B, tok.size);
        s = t;

        while (p < e) {
            if (*p == '\\') {
                if (++p == e) {
                    luaL_error(L, "parse error in string");
                }
                switch (*p) {
                    case '\\':
                        *(t++) = '\\';
                        p++;
                        break;
                    case '\"':
                        *(t++) = '\"';
                        p++;
                        break;
                    case '\'':
                        *(t++) = '\'';
                        p++;
                        break;
                    case 'n':
                        *(t++) = '\n';
                        p++;
                        break;
                    case 'r':
                        *(t++) = '\r';
                        p++;
                        break;
                    case 'b':
                        *(t++) = '\b';
                        p++;
                        break;
                    case 't':
                        *(t++) = '\t';
                        p++;
                        break;
                    case 'f':
                        *(t++) = '\f';
                        p++;
                        break;
                    case 'a':
                        *(t++) = '\a';
                        p++;
                        break;
                    case 'v':
                        *(t++) = '\v';
                        p++;
                        break;
                    case 'e':
                        *(t++) = 0x1B;
                        p++;
                        break;
                    case 'x': {
                        uint8_t u;
                        p++;
                        if (p + 2 > e || !is_hex(p[0]) || !is_hex(p[1])) {
                            luaL_error(L, "parse error in string");
                        }
                        u = (from_hex(p[0]) << 4) | from_hex(p[1]);
                        *(t++) = *(char*)&u;
                        p += 2;
                        break;
                    }
                    default: {
                        uint8_t u;
                        const char* e2 = min(p + 3, e);
                        if (!is_digit(*p)) {
                            luaL_error(L, "parse error in string");
                        }
                        u = *p - '0';
                        p++;
                        while (is_digit(*p) && p < e2) {
                            u = 10 * u + *p - '0';
                            p++;
                        }
                        *(t++) = *(char*)&u;
                        break;
                    }
                }
            } else {
                *(t++) = *(p++);
            }
        }

        luaL_addsize(&B, t - s);
    }

    luaL_pushresult(&B);
}

#define END 0
#define PRAGMA_POP 1

static int parse_root(lua_State* L, struct parser* P) {
    int top = lua_gettop(L);
    struct token tok;

    while (next_token(L, P, &tok)) {
        /* we can have:
         * struct definition
         * enum definition
         * union definition
         * struct/enum/union declaration
         * typedef
         * function declaration
         * pragma pack
         */

        assert(lua_gettop(L) == top);

        if (tok.type == TOK_SEMICOLON) {
            /* empty semicolon in root continue on */

        } else if (tok.type == TOK_POUND) {
            check_token(L, P, TOK_TOKEN, "pragma",
                        "unexpected pre processor directive on line %d", P->line);
            check_token(L, P, TOK_TOKEN, "pack",
                        "unexpected pre processor directive on line %d", P->line);
            check_token(L, P, TOK_OPEN_PAREN, "", "invalid pack directive on line %d",
                        P->line);

            require_token(L, P, &tok);

            if (tok.type == TOK_NUMBER) {
                if (tok.integer != 1 && tok.integer != 2 && tok.integer != 4 &&
                    tok.integer != 8 && tok.integer != 16) {
                    luaL_error(L, "pack directive with invalid pack size on line %d",
                               P->line);
                }

                P->align_mask = (unsigned)(tok.integer - 1);
                check_token(L, P, TOK_CLOSE_PAREN, "",
                            "invalid pack directive on line %d", P->line);

            } else if (tok.type == TOK_TOKEN && IS_LITERAL(tok, "push")) {
                int line = P->line;
                unsigned previous_alignment = P->align_mask;

                check_token(L, P, TOK_CLOSE_PAREN, "",
                            "invalid pack directive on line %d", P->line);

                if (parse_root(L, P) != PRAGMA_POP) {
                    luaL_error(L,
                               "reached end of string without a pragma pop to match the "
                               "push on line %d",
                               line);
                }

                P->align_mask = previous_alignment;

            } else if (tok.type == TOK_TOKEN && IS_LITERAL(tok, "pop")) {
                check_token(L, P, TOK_CLOSE_PAREN, "",
                            "invalid pack directive on line %d", P->line);
                return PRAGMA_POP;

            } else {
                luaL_error(L, "invalid pack directive on line %d", P->line);
            }

        } else if (tok.type != TOK_TOKEN) {
            return luaL_error(L, "unexpected character on line %d", P->line);

        } else if (IS_LITERAL(tok, "__extension__")) {
            /* ignore */
            continue;

        } else if (IS_LITERAL(tok, "extern")) {
            /* ignore extern as data and functions can only be extern */
            continue;

        } else if (IS_LITERAL(tok, "typedef")) {
            parse_typedef(L, P);

        } else if (IS_LITERAL(tok, "static")) {
            struct ctype at;

            int64_t val;
            require_token(L, P, &tok);
            if (!IS_CONST(tok)) {
                luaL_error(L, "expected 'static const int' on line %d", P->line);
            }

            parse_type(L, P, &at);

            require_token(L, P, &tok);
            if (tok.type != TOK_TOKEN) {
                luaL_error(L,
                           "expected constant name after 'static const int' on line %d",
                           P->line);
            }

            check_token(L, P, TOK_ASSIGN, "",
                        "expected = after 'static const int <name>' on line %d", P->line);

            val = calculate_constant(L, P);

            check_token(L, P, TOK_SEMICOLON, "",
                        "expected ; after 'static const int' definition on line %d",
                        P->line);

            push_upval(L, &constants_key);
            lua_pushlstring(L, tok.str, tok.size);

            switch (at.type) {
                case INT8_TYPE:
                case INT16_TYPE:
                case INT32_TYPE:
                    if (at.is_unsigned)
                        lua_pushnumber(L, (unsigned int)val);
                    else
                        lua_pushnumber(L, (int)val);
                    break;

                default:
                    luaL_error(L,
                               "expected a valid 8-, 16-, or 32-bit signed or unsigned "
                               "integer type after 'static const' on line %d",
                               P->line);
            }

            lua_rawset(L, -3);
            lua_pop(L, 2); /*constants and type*/

        } else {
            /* type declaration, type definition, or function declaration */
            struct ctype type;
            struct token name;
            struct parser asmname;

            memset(&name, 0, sizeof(name));
            memset(&asmname, 0, sizeof(asmname));

            put_back(P);
            parse_type(L, P, &type);

            for (;;) {
                parse_argument(L, P, -1, &type, &name, &asmname);

                if (name.size) {
                    /* global/function declaration */

                    /* set asmname_tbl[name] = asmname */
                    if (asmname.next) {
                        push_upval(L, &asmname_key);
                        lua_pushlstring(L, name.str, name.size);
                        push_strings(L, &asmname);
                        lua_rawset(L, -3);
                        lua_pop(L, 1); /* asmname upval */
                    }

                    push_upval(L, &functions_key);
                    lua_pushlstring(L, name.str, name.size);
                    push_ctype(L, -3, &type);
                    lua_rawset(L, -3);
                    lua_pop(L, 1); /* functions upval */
                } else {
                    /* type declaration/definition - already been processed */
                }

                lua_pop(L, 1);

                require_token(L, P, &tok);

                if (tok.type == TOK_SEMICOLON) {
                    break;
                } else if (tok.type != TOK_COMMA) {
                    luaL_error(L, "missing semicolon on line %d", P->line);
                }
            }

            lua_pop(L, 1);
        }
    }

    return END;
}

int ffi_cdef(lua_State* L) {
    struct parser P;

    P.line = 1;
    P.prev = P.next = luaL_checkstring(L, 1);
    P.align_mask = DEFAULT_ALIGN_MASK;

    if (parse_root(L, &P) == PRAGMA_POP) {
        luaL_error(L, "pragma pop without an associated push on line %d", P.line);
    }

    return 0;
}

/* calculate_constant handles operator precedence by having a number of
 * recursive commands each of which computes the result at that level of
 * precedence and above. calculate_constant1 is the highest precedence
 */

static int try_cast(lua_State* L) {
    struct parser* P = (struct parser*)lua_touserdata(L, 1);
    struct ctype ct;
    struct token name, tok;
    memset(&name, 0, sizeof(name));

    parse_type(L, P, &ct);
    parse_argument(L, P, -1, &ct, &name, NULL);

    require_token(L, P, &tok);
    if (tok.type != TOK_CLOSE_PAREN || name.size) {
        return luaL_error(L, "invalid cast");
    }

    if (ct.pointers || ct.type != INT32_TYPE) {
        return luaL_error(L, "unsupported cast on line %d", P->line);
    }

    return 0;
}

static int64_t calculate_constant2(lua_State* L, struct parser* P, struct token* tok);

/* () */
static int64_t calculate_constant1(lua_State* L, struct parser* P, struct token* tok) {
    int64_t ret;

    if (tok->type == TOK_NUMBER) {
        ret = tok->integer;
        next_token(L, P, tok);
        return ret;

    } else if (tok->type == TOK_TOKEN) {
        /* look up name in constants table */
        push_upval(L, &constants_key);
        lua_pushlstring(L, tok->str, tok->size);
        lua_rawget(L, -2);
        lua_remove(L, -2); /* constants table */

        if (!lua_isnumber(L, -1)) {
            lua_pushlstring(L, tok->str, tok->size);
            luaL_error(L, "use of undefined constant %s on line %d", lua_tostring(L, -1),
                       P->line);
        }

        ret = (int64_t)lua_tonumber(L, -1);
        lua_pop(L, 1);
        next_token(L, P, tok);
        return ret;

    } else if (tok->type == TOK_OPEN_PAREN) {
        struct parser before_cast = *P;
        int top = lua_gettop(L);

        /* see if this is a numeric cast, which we ignore */
        lua_pushcfunction(L, &try_cast);
        lua_pushlightuserdata(L, P);
        if (!lua_pcall(L, 1, 0, 0)) {
            next_token(L, P, tok);
            return calculate_constant2(L, P, tok);
        }
        lua_settop(L, top);

        *P = before_cast;
        ret = calculate_constant(L, P);

        require_token(L, P, tok);
        if (tok->type != TOK_CLOSE_PAREN) {
            luaL_error(L, "error whilst parsing constant at line %d", P->line);
        }

        next_token(L, P, tok);
        return ret;

    } else {
        return luaL_error(L, "unexpected token whilst parsing constant at line %d",
                          P->line);
    }
}

/* ! and ~, unary + and -, and sizeof */
static int64_t calculate_constant2(lua_State* L, struct parser* P, struct token* tok) {
    if (tok->type == TOK_LOGICAL_NOT) {
        require_token(L, P, tok);
        return !calculate_constant2(L, P, tok);

    } else if (tok->type == TOK_BITWISE_NOT) {
        require_token(L, P, tok);
        return ~calculate_constant2(L, P, tok);

    } else if (tok->type == TOK_PLUS) {
        require_token(L, P, tok);
        return calculate_constant2(L, P, tok);

    } else if (tok->type == TOK_MINUS) {
        require_token(L, P, tok);
        return -calculate_constant2(L, P, tok);

    } else if (tok->type == TOK_TOKEN &&
               (IS_LITERAL(*tok, "sizeof") || IS_LITERAL(*tok, "alignof") ||
                IS_LITERAL(*tok, "__alignof__") || IS_LITERAL(*tok, "__alignof"))) {
        bool issize = IS_LITERAL(*tok, "sizeof");
        struct ctype type;

        require_token(L, P, tok);
        if (tok->type != TOK_OPEN_PAREN) {
            luaL_error(L, "invalid sizeof at line %d", P->line);
        }

        parse_type(L, P, &type);
        parse_argument(L, P, -1, &type, NULL, NULL);
        lua_pop(L, 2);

        require_token(L, P, tok);
        if (tok->type != TOK_CLOSE_PAREN) {
            luaL_error(L, "invalid sizeof at line %d", P->line);
        }

        next_token(L, P, tok);

        return issize ? ctype_size(L, &type) : type.align_mask + 1;

    } else {
        return calculate_constant1(L, P, tok);
    }
}

/* binary * / and % (left associative) */
static int64_t calculate_constant3(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant2(L, P, tok);

    for (;;) {
        if (tok->type == TOK_MULTIPLY) {
            require_token(L, P, tok);
            left *= calculate_constant2(L, P, tok);

        } else if (tok->type == TOK_DIVIDE) {
            require_token(L, P, tok);
            left /= calculate_constant2(L, P, tok);

        } else if (tok->type == TOK_MODULUS) {
            require_token(L, P, tok);
            left %= calculate_constant2(L, P, tok);

        } else {
            return left;
        }
    }
}

/* binary + and - (left associative) */
static int64_t calculate_constant4(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant3(L, P, tok);

    for (;;) {
        if (tok->type == TOK_PLUS) {
            require_token(L, P, tok);
            left += calculate_constant3(L, P, tok);

        } else if (tok->type == TOK_MINUS) {
            require_token(L, P, tok);
            left -= calculate_constant3(L, P, tok);

        } else {
            return left;
        }
    }
}

/* binary << and >> (left associative) */
static int64_t calculate_constant5(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant4(L, P, tok);

    for (;;) {
        if (tok->type == TOK_LEFT_SHIFT) {
            require_token(L, P, tok);
            left <<= calculate_constant4(L, P, tok);

        } else if (tok->type == TOK_RIGHT_SHIFT) {
            require_token(L, P, tok);
            left >>= calculate_constant4(L, P, tok);

        } else {
            return left;
        }
    }
}

/* binary <, <=, >, and >= (left associative) */
static int64_t calculate_constant6(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant5(L, P, tok);

    for (;;) {
        if (tok->type == TOK_LESS) {
            require_token(L, P, tok);
            left = (left < calculate_constant5(L, P, tok));

        } else if (tok->type == TOK_LESS_EQUAL) {
            require_token(L, P, tok);
            left = (left <= calculate_constant5(L, P, tok));

        } else if (tok->type == TOK_GREATER) {
            require_token(L, P, tok);
            left = (left > calculate_constant5(L, P, tok));

        } else if (tok->type == TOK_GREATER_EQUAL) {
            require_token(L, P, tok);
            left = (left >= calculate_constant5(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary ==, != (left associative) */
static int64_t calculate_constant7(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant6(L, P, tok);

    for (;;) {
        if (tok->type == TOK_EQUAL) {
            require_token(L, P, tok);
            left = (left == calculate_constant6(L, P, tok));

        } else if (tok->type == TOK_NOT_EQUAL) {
            require_token(L, P, tok);
            left = (left != calculate_constant6(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary & (left associative) */
static int64_t calculate_constant8(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant7(L, P, tok);

    for (;;) {
        if (tok->type == TOK_BITWISE_AND) {
            require_token(L, P, tok);
            left = (left & calculate_constant7(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary ^ (left associative) */
static int64_t calculate_constant9(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant8(L, P, tok);

    for (;;) {
        if (tok->type == TOK_BITWISE_XOR) {
            require_token(L, P, tok);
            left = (left ^ calculate_constant8(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary | (left associative) */
static int64_t calculate_constant10(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant9(L, P, tok);

    for (;;) {
        if (tok->type == TOK_BITWISE_OR) {
            require_token(L, P, tok);
            left = (left | calculate_constant9(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary && (left associative) */
static int64_t calculate_constant11(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant10(L, P, tok);

    for (;;) {
        if (tok->type == TOK_LOGICAL_AND) {
            require_token(L, P, tok);
            left = (left && calculate_constant10(L, P, tok));

        } else {
            return left;
        }
    }
}

/* binary || (left associative) */
static int64_t calculate_constant12(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant11(L, P, tok);

    for (;;) {
        if (tok->type == TOK_LOGICAL_OR) {
            require_token(L, P, tok);
            left = (left || calculate_constant11(L, P, tok));

        } else {
            return left;
        }
    }
}

/* ternary ?: (right associative) */
static int64_t calculate_constant13(lua_State* L, struct parser* P, struct token* tok) {
    int64_t left = calculate_constant12(L, P, tok);

    if (tok->type == TOK_QUESTION) {
        int64_t middle, right;
        require_token(L, P, tok);
        middle = calculate_constant13(L, P, tok);
        if (tok->type != TOK_COLON) {
            luaL_error(L, "invalid ternery (? :) in constant on line %d", P->line);
        }
        require_token(L, P, tok);
        right = calculate_constant13(L, P, tok);
        return left ? middle : right;

    } else {
        return left;
    }
}

int64_t calculate_constant(lua_State* L, struct parser* P) {
    struct token tok;
    int64_t ret;
    require_token(L, P, &tok);
    ret = calculate_constant13(L, P, &tok);

    if (tok.type != TOK_NIL) {
        put_back(P);
    }

    return ret;
}
