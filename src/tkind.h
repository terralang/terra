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
_(minus,"-") \
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
_(builtin,"builtin") \
_(error, "error") \
_(functype,"functype") \
_(float,"float") \
_(integer,"integer") \
_(logical,"logical") \
_(ltor,"ltor")

enum T_Kind {
	#define T_KIND_ENUM(a,str) T_##a,
	T_KIND_LIST(T_KIND_ENUM)
	T_NUM_KINDS
};

const char * tkindtostr(T_Kind k);
void terra_kindsinit(terra_State * T);



#endif