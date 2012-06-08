/*
** $Id: lzio.h,v 1.26 2011/07/15 12:48:03 roberto Exp $
** Buffered streams
** See Copyright Notice in lua.h
*/


#ifndef lzio_h
#define lzio_h

#include "lutil.h"
#include <stdlib.h>

#define EOZ (-1)            /* end of stream */

typedef struct Zio ZIO;

#define zgetc(z)  (((z)->n--)>0 ?  cast_uchar(*(z)->p++) : luaZ_fill(z))


typedef struct Mbuffer {
  char *buffer;
  size_t n;
  size_t buffsize;
} Mbuffer;

#define luaZ_initbuffer(L, buff) ((buff)->buffer = NULL, (buff)->buffsize = 0)

#define luaZ_buffer(buff)   ((buff)->buffer)
#define luaZ_sizebuffer(buff)   ((buff)->buffsize)
#define luaZ_bufflen(buff)  ((buff)->n)

#define luaZ_resetbuffer(buff) ((buff)->n = 0)

static inline size_t luaZ_resizebuffer(void * state, Mbuffer * buf, size_t size) {
    if(buf->buffer)
        buf->buffer = (char*) realloc(buf->buffer,size);
    else
        buf->buffer = (char*) malloc(size);
    buf->buffsize = size;
    return size;
}

LUAI_FUNC char *luaZ_openspace (terra_State *L, Mbuffer *buff, size_t n);
LUAI_FUNC void luaZ_init (terra_State *L, ZIO *z, luaP_Reader reader,
                                        void *data);
LUAI_FUNC size_t luaZ_read (ZIO* z, void* b, size_t n); /* read next n bytes */



/* --------- Private Part ------------------ */

struct Zio {
  size_t n;         /* bytes still unread */
  const char *p;        /* current position in buffer */
  luaP_Reader reader;       /* reader function */
  void* data;           /* additional data */
  terra_State *L;           /* Lua state (for reader) */
};


LUAI_FUNC int luaZ_fill (ZIO *z);

#endif
