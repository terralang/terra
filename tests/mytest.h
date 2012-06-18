#include <stdio.h>

int myfoobarthing(int a, double b, int c,int * d) {
    printf("my foobar thing is alive %d %f %d\n",a,b,c);
    *d = 8;
    return 7;
}
int myotherthing(int a, int b) { return a + b; }