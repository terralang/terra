#ifndef t_kind_h
#define t_kind_h

struct terra_State;
//all value that can go into the terra AST's kind field, and the functions to initialize the terra.kinds table in the lua state


#define T_KIND_LIST(_) \
_(add, "+") \
_(addressof,"&") \
_(and,"and") \
_(apply,"apply") \
_(assignment,"assignment") \
_(block,"block") \
_(break,"break") \
_(concat,"..") \
_(constructor,"constructor") \
_(defvar,"defvar") \
_(dereference,"@") \
_(div, "/") \
_(entry,"entry") \
_(eq,"==") \
_(forlist,"forlist") \
_(fornum,"fornum") \
_(funcptr,"->") \
_(function,"function") \
_(ge,">=") \
_(goto,"goto") \
_(gt,">") \
_(if,"if") \
_(ifbranch,"ifbranch") \
_(index,"index") \
_(label,"label") \
_(le,"<=") \
_(listfield,"listfield") \
_(literal,"literal") \
_(lt,"<") \
_(method,"method") \
_(mod, "%") \
_(mul, "*") \
_(ne,"~=") \
_(not,"not") \
_(operator,"operator") \
_(or, "or") \
_(pow, "^") \
_(recfield,"recfield") \
_(repeat,"repeat") \
_(return,"return") \
_(select,"select") \
_(sub, "-") \
_(var,"var") \
_(while,"while") \
_(pointer,"pointer") \
_(primitive,"primitive") \
_(error, "error") \
_(functype,"functype") \
_(float,"float") \
_(integer,"integer") \
_(logical,"logical") \
_(cast,"cast") \
_(extractreturn,"extractreturn") \
_(globalvar, "globalvar") \
_(struct, "struct") \
_(structentry, "structentry") \
_(type, "type") \
_(proxy, "proxy") \
_(array, "array") \
_(explicitcast, "explicitcast") \
_(sizeof, "sizeof") \
_(niltype, "niltype") \
_(union, "union") \
_(lshift, "<<") \
_(rshift, ">>") \
_(luafunction, "luafunction") \
_(luatable, "luaobject") \
_(quote, "quote") \
_(vector, "vector") \
_(vectorconstructor,"vectorconstructor") \
_(arrayconstructor,"arrayconstructor") \
_(luaexpression,"luaexpression") \
_(symbol, "symbol") \
_(selectconst, "selectconst") \
_(treelist, "treelist") \
_(typedexpression, "typedexpression") \
_(intrinsic, "intrinsic") \
_(nametoken, "<name>") \
_(numbertoken, "<number>") \
_(stringtoken, "<string>") \
_(eostoken, "<eof>") \
_(constant,"constant") \
_(truncate, "truncate") \
_(attrload,"attrload") \
_(attrstore,"attrstore")

enum T_Kind {
    #define T_KIND_ENUM(a,str) T_##a,
    T_KIND_LIST(T_KIND_ENUM)
    T_NUM_KINDS
};

const char * tkindtostr(T_Kind k);
void terra_kindsinit(terra_State * T);



#endif