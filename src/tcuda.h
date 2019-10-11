#ifndef tcuda_h
#define tcuda_h

struct terra_State;
int terra_cudainit(struct terra_State* T);
int terra_cudafree(struct terra_State* T);

#endif