#ifndef t_kind_h
#define t_kind_h

struct terra_State;
//a list of strings that the C++ code in tcompiler.cpp needs to examine for code emission
//a table terra.kinds maps these strings to enum values that are defined here.

#define T_KIND_LIST(_) \
_(add, "+") \
_(addressof,"&") \
_(allocvar, "allocvar") \
_(and,"and") \
_(apply,"apply") \
_(array, "array") \
_(arrayconstructor,"arrayconstructor") \
_(assignment,"assignment") \
_(attrload,"attrload") \
_(attrstore,"attrstore") \
_(block,"block") \
_(breakstat,"breakstat") \
_(cast,"cast") \
_(constant,"constant") \
_(constructor,"constructor") \
_(debuginfo,"debuginfo") \
_(defer, "defer") \
_(dereference,"@") \
_(div, "/") \
_(eq,"==") \
_(float,"float") \
_(fornum,"fornum") \
_(functype,"functype") \
_(ge,">=") \
_(globalvalueref, "globalvalueref") \
_(gotostat,"gotostat") \
_(gt,">") \
_(ifstat,"ifstat") \
_(index,"index") \
_(inlineasm,"inlineasm") \
_(integer,"integer") \
_(label,"label") \
_(le,"<=") \
_(letin,"letin") \
_(literal,"literal") \
_(logical,"logical") \
_(lshift, "<<") \
_(lt,"<") \
_(mod, "%") \
_(mul, "*") \
_(ne,"~=") \
_(niltype, "niltype") \
_(not,"not") \
_(opaque, "opaque") \
_(operator,"operator") \
_(or, "or") \
_(pointer,"pointer") \
_(pow, "^") \
_(primitive,"primitive") \
_(repeatstat,"repeatstat") \
_(returnstat,"returnstat") \
_(rshift, ">>") \
_(select,"select") \
_(setter,"setter") \
_(sizeof, "sizeof") \
_(struct, "struct") \
_(structcast, "structcast") \
_(sub, "-") \
_(var,"var") \
_(vector, "vector") \
_(vectorconstructor,"vectorconstructor") \
_(whilestat,"whilestat") \
_(globalvariable,"globalvariable") \
_(terrafunction,"terrafunction") \
_(functiondef, "functiondef") \
_(functionextern, "functionextern")

enum T_Kind {
    #define T_KIND_ENUM(a,str) T_##a,
    T_KIND_LIST(T_KIND_ENUM)
    T_NUM_KINDS
};

const char * tkindtostr(T_Kind k);
void terra_kindsinit(terra_State * T);

#endif