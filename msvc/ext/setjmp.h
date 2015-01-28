#include <setjmp.h>

#define sigsetjmp(jb,ssmf) setjmp(jb)
#define siglongjmp(jb,v) longjmp(jb,v)
#define sigjmp_buf jmp_buf