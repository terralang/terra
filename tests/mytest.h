#include <stdio.h>

int myfoobarthing(int a, double b, int c, int* d) {
    FILE* foo = fopen("what", "r");
    printf("my foobar thing is alive %d %f %d\n", a, b, c);
    *d = 8;
    return 7;
}
int myotherthing(int a, int b) { return a + b; }
int myfnptr(int (*foobar)(void)) { return foobar(); }

typedef struct MyStruct {
    int a;
    double b;
} MyStruct;
typedef struct MyStruct2 {
    int a;
    union {
        int b;
        int c;
    };
} MyStruct2;