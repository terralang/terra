-- This is an attempt to be more systematic about checking Terra's
-- calling convention support, particularly against C.
--
-- The test covers:
--
--  * Pass/return void/no arguments.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass 1..N values as separate arguments to a function, and return the
--        same type.
--
--  * Pass/return an empty struct.
--
--  * For each type in {int8, int16, int32, int64, float, double}:
--      * Pass (and return) a struct with 1..N fields of that type.
--
--  * Same, but with fields of rotating types (int8, int16, int32, int64,
--    double).
--
-- A couple notable features (especially compared to cconv.t):
--
--  * The tests verify that structs are passed by value, by modifying the
--    arguments within the called functions.
--
--  * As compared to cconv.t, this test verifies that Terra can call both
--    itself and C. The latter is particularly important for ensuring we match
--    the ABI of the system C compiler.
--
--  * As a bonus, the use of C allows quick comparisons between Clang's and
--    Terra's output. A command to generate the LLVM IR is shown (commented)
--    at the bottom of the file.

local test = require("test")

local c = terralib.includecstring [[
#include <stdint.h>

typedef struct p0 {} p0;

typedef struct q1 { int8_t f1; } q1;
typedef struct q2 { int8_t f1; int8_t f2; } q2;
typedef struct q3 { int8_t f1; int8_t f2; int8_t f3; } q3;
typedef struct q4 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; } q4;
typedef struct q5 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; int8_t f5; } q5;
typedef struct q6 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; int8_t f5; int8_t f6; } q6;
typedef struct q7 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; int8_t f5; int8_t f6; int8_t f7; } q7;
typedef struct q8 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; int8_t f5; int8_t f6; int8_t f7; int8_t f8; } q8;
typedef struct q9 { int8_t f1; int8_t f2; int8_t f3; int8_t f4; int8_t f5; int8_t f6; int8_t f7; int8_t f8; int8_t f9; } q9;

typedef struct r1 { int16_t f1; } r1;
typedef struct r2 { int16_t f1; int16_t f2; } r2;
typedef struct r3 { int16_t f1; int16_t f2; int16_t f3; } r3;
typedef struct r4 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; } r4;
typedef struct r5 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; int16_t f5; } r5;
typedef struct r6 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; int16_t f5; int16_t f6; } r6;
typedef struct r7 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; int16_t f5; int16_t f6; int16_t f7; } r7;
typedef struct r8 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; int16_t f5; int16_t f6; int16_t f7; int16_t f8; } r8;
typedef struct r9 { int16_t f1; int16_t f2; int16_t f3; int16_t f4; int16_t f5; int16_t f6; int16_t f7; int16_t f8; int16_t f9; } r9;

typedef struct s1 { int32_t f1; } s1;
typedef struct s2 { int32_t f1; int32_t f2; } s2;
typedef struct s3 { int32_t f1; int32_t f2; int32_t f3; } s3;
typedef struct s4 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; } s4;
typedef struct s5 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; int32_t f5; } s5;
typedef struct s6 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; int32_t f5; int32_t f6; } s6;
typedef struct s7 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; int32_t f5; int32_t f6; int32_t f7; } s7;
typedef struct s8 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; int32_t f5; int32_t f6; int32_t f7; int32_t f8; } s8;
typedef struct s9 { int32_t f1; int32_t f2; int32_t f3; int32_t f4; int32_t f5; int32_t f6; int32_t f7; int32_t f8; int32_t f9; } s9;

typedef struct t1 { int64_t f1; } t1;
typedef struct t2 { int64_t f1; int64_t f2; } t2;
typedef struct t3 { int64_t f1; int64_t f2; int64_t f3; } t3;
typedef struct t4 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; } t4;
typedef struct t5 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; int64_t f5; } t5;
typedef struct t6 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; int64_t f5; int64_t f6; } t6;
typedef struct t7 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; int64_t f5; int64_t f6; int64_t f7; } t7;
typedef struct t8 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; int64_t f5; int64_t f6; int64_t f7; int64_t f8; } t8;
typedef struct t9 { int64_t f1; int64_t f2; int64_t f3; int64_t f4; int64_t f5; int64_t f6; int64_t f7; int64_t f8; int64_t f9; } t9;

typedef struct u1 { float f1; } u1;
typedef struct u2 { float f1; float f2; } u2;
typedef struct u3 { float f1; float f2; float f3; } u3;
typedef struct u4 { float f1; float f2; float f3; float f4; } u4;
typedef struct u5 { float f1; float f2; float f3; float f4; float f5; } u5;
typedef struct u6 { float f1; float f2; float f3; float f4; float f5; float f6; } u6;
typedef struct u7 { float f1; float f2; float f3; float f4; float f5; float f6; float f7; } u7;
typedef struct u8 { float f1; float f2; float f3; float f4; float f5; float f6; float f7; float f8; } u8;
typedef struct u9 { float f1; float f2; float f3; float f4; float f5; float f6; float f7; float f8; float f9; } u9;

typedef struct v1 { double f1; } v1;
typedef struct v2 { double f1; double f2; } v2;
typedef struct v3 { double f1; double f2; double f3; } v3;
typedef struct v4 { double f1; double f2; double f3; double f4; } v4;
typedef struct v5 { double f1; double f2; double f3; double f4; double f5; } v5;
typedef struct v6 { double f1; double f2; double f3; double f4; double f5; double f6; } v6;
typedef struct v7 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; } v7;
typedef struct v8 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; double f8; } v8;
typedef struct v9 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; double f8; double f9; } v9;

typedef struct w1 { int8_t f1; } w1;
typedef struct w2 { int8_t f1; int16_t f2; } w2;
typedef struct w3 { int8_t f1; int16_t f2; int32_t f3; } w3;
typedef struct w4 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; } w4;
typedef struct w5 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; double f5; } w5;
typedef struct w6 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; double f5; int8_t f6; } w6;
typedef struct w7 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; double f5; int8_t f6; int16_t f7; } w7;
typedef struct w8 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; double f5; int8_t f6; int16_t f7; int32_t f8; } w8;
typedef struct w9 { int8_t f1; int16_t f2; int32_t f3; int64_t f4; double f5; int8_t f6; int16_t f7; int32_t f8; int64_t f9; } w9;

void ca0() {}

int8_t cb1(int8_t x) { return x + 1; }
int8_t cb2(int8_t x, int8_t y) { return x + y; }
int8_t cb3(int8_t x, int8_t y, int8_t z) { return x + y + z; }
int8_t cb4(int8_t x, int8_t y, int8_t z, int8_t w) { return x + y + z + w; }
int8_t cb5(int8_t x, int8_t y, int8_t z, int8_t w, int8_t v) { return x + y + z + w + v; }
int8_t cb6(int8_t x, int8_t y, int8_t z, int8_t w, int8_t v, int8_t u) { return x + y + z + w + v + u; }
int8_t cb7(int8_t x, int8_t y, int8_t z, int8_t w, int8_t v, int8_t u, int8_t t) { return x + y + z + w + v + u + t; }
int8_t cb8(int8_t x, int8_t y, int8_t z, int8_t w, int8_t v, int8_t u, int8_t t, int8_t s) { return x + y + z + w + v + u + t + s; }
int8_t cb9(int8_t x, int8_t y, int8_t z, int8_t w, int8_t v, int8_t u, int8_t t, int8_t s, int8_t r) { return x + y + z + w + v + u + t + s + r; }

int16_t cc1(int16_t x) { return x + 1; }
int16_t cc2(int16_t x, int16_t y) { return x + y; }
int16_t cc3(int16_t x, int16_t y, int16_t z) { return x + y + z; }
int16_t cc4(int16_t x, int16_t y, int16_t z, int16_t w) { return x + y + z + w; }
int16_t cc5(int16_t x, int16_t y, int16_t z, int16_t w, int16_t v) { return x + y + z + w + v; }
int16_t cc6(int16_t x, int16_t y, int16_t z, int16_t w, int16_t v, int16_t u) { return x + y + z + w + v + u; }
int16_t cc7(int16_t x, int16_t y, int16_t z, int16_t w, int16_t v, int16_t u, int16_t t) { return x + y + z + w + v + u + t; }
int16_t cc8(int16_t x, int16_t y, int16_t z, int16_t w, int16_t v, int16_t u, int16_t t, int16_t s) { return x + y + z + w + v + u + t + s; }
int16_t cc9(int16_t x, int16_t y, int16_t z, int16_t w, int16_t v, int16_t u, int16_t t, int16_t s, int16_t r) { return x + y + z + w + v + u + t + s + r; }

int32_t cd1(int32_t x) { return x + 1; }
int32_t cd2(int32_t x, int32_t y) { return x + y; }
int32_t cd3(int32_t x, int32_t y, int32_t z) { return x + y + z; }
int32_t cd4(int32_t x, int32_t y, int32_t z, int32_t w) { return x + y + z + w; }
int32_t cd5(int32_t x, int32_t y, int32_t z, int32_t w, int32_t v) { return x + y + z + w + v; }
int32_t cd6(int32_t x, int32_t y, int32_t z, int32_t w, int32_t v, int32_t u) { return x + y + z + w + v + u; }
int32_t cd7(int32_t x, int32_t y, int32_t z, int32_t w, int32_t v, int32_t u, int32_t t) { return x + y + z + w + v + u + t; }
int32_t cd8(int32_t x, int32_t y, int32_t z, int32_t w, int32_t v, int32_t u, int32_t t, int32_t s) { return x + y + z + w + v + u + t + s; }
int32_t cd9(int32_t x, int32_t y, int32_t z, int32_t w, int32_t v, int32_t u, int32_t t, int32_t s, int32_t r) { return x + y + z + w + v + u + t + s + r; }

int64_t ce1(int64_t x) { return x + 1; }
int64_t ce2(int64_t x, int64_t y) { return x + y; }
int64_t ce3(int64_t x, int64_t y, int64_t z) { return x + y + z; }
int64_t ce4(int64_t x, int64_t y, int64_t z, int64_t w) { return x + y + z + w; }
int64_t ce5(int64_t x, int64_t y, int64_t z, int64_t w, int64_t v) { return x + y + z + w + v; }
int64_t ce6(int64_t x, int64_t y, int64_t z, int64_t w, int64_t v, int64_t u) { return x + y + z + w + v + u; }
int64_t ce7(int64_t x, int64_t y, int64_t z, int64_t w, int64_t v, int64_t u, int64_t t) { return x + y + z + w + v + u + t; }
int64_t ce8(int64_t x, int64_t y, int64_t z, int64_t w, int64_t v, int64_t u, int64_t t, int64_t s) { return x + y + z + w + v + u + t + s; }
int64_t ce9(int64_t x, int64_t y, int64_t z, int64_t w, int64_t v, int64_t u, int64_t t, int64_t s, int64_t r) { return x + y + z + w + v + u + t + s + r; }

float cf1(float x) { return x + 1; }
float cf2(float x, float y) { return x + y; }
float cf3(float x, float y, float z) { return x + y + z; }
float cf4(float x, float y, float z, float w) { return x + y + z + w; }
float cf5(float x, float y, float z, float w, float v) { return x + y + z + w + v; }
float cf6(float x, float y, float z, float w, float v, float u) { return x + y + z + w + v + u; }
float cf7(float x, float y, float z, float w, float v, float u, float t) { return x + y + z + w + v + u + t; }
float cf8(float x, float y, float z, float w, float v, float u, float t, float s) { return x + y + z + w + v + u + t + s; }
float cf9(float x, float y, float z, float w, float v, float u, float t, float s, float r) { return x + y + z + w + v + u + t + s + r; }

double cg1(double x) { return x + 1; }
double cg2(double x, double y) { return x + y; }
double cg3(double x, double y, double z) { return x + y + z; }
double cg4(double x, double y, double z, double w) { return x + y + z + w; }
double cg5(double x, double y, double z, double w, double v) { return x + y + z + w + v; }
double cg6(double x, double y, double z, double w, double v, double u) { return x + y + z + w + v + u; }
double cg7(double x, double y, double z, double w, double v, double u, double t) { return x + y + z + w + v + u + t; }
double cg8(double x, double y, double z, double w, double v, double u, double t, double s) { return x + y + z + w + v + u + t + s; }
double cg9(double x, double y, double z, double w, double v, double u, double t, double s, double r) { return x + y + z + w + v + u + t + s + r; }

p0 cp0(p0 x) { return x; }

q1 cq1(q1 x) { x.f1 += 1; return x; }
q2 cq2(q2 x) { x.f1 += 1; x.f2 += 2; return x; }
q3 cq3(q3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
q4 cq4(q4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
q5 cq5(q5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
q6 cq6(q6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
q7 cq7(q7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
q8 cq8(q8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
q9 cq9(q9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

r1 cr1(r1 x) { x.f1 += 1; return x; }
r2 cr2(r2 x) { x.f1 += 1; x.f2 += 2; return x; }
r3 cr3(r3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
r4 cr4(r4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
r5 cr5(r5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
r6 cr6(r6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
r7 cr7(r7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
r8 cr8(r8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
r9 cr9(r9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

s1 cs1(s1 x) { x.f1 += 1; return x; }
s2 cs2(s2 x) { x.f1 += 1; x.f2 += 2; return x; }
s3 cs3(s3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
s4 cs4(s4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
s5 cs5(s5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
s6 cs6(s6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
s7 cs7(s7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
s8 cs8(s8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
s9 cs9(s9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

t1 ct1(t1 x) { x.f1 += 1; return x; }
t2 ct2(t2 x) { x.f1 += 1; x.f2 += 2; return x; }
t3 ct3(t3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
t4 ct4(t4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
t5 ct5(t5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
t6 ct6(t6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
t7 ct7(t7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
t8 ct8(t8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
t9 ct9(t9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

u1 cu1(u1 x) { x.f1 += 1; return x; }
u2 cu2(u2 x) { x.f1 += 1; x.f2 += 2; return x; }
u3 cu3(u3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
u4 cu4(u4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
u5 cu5(u5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
u6 cu6(u6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
u7 cu7(u7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
u8 cu8(u8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
u9 cu9(u9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

v1 cv1(v1 x) { x.f1 += 1; return x; }
v2 cv2(v2 x) { x.f1 += 1; x.f2 += 2; return x; }
v3 cv3(v3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
v4 cv4(v4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
v5 cv5(v5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
v6 cv6(v6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
v7 cv7(v7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
v8 cv8(v8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
v9 cv9(v9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

w1 cw1(w1 x) { x.f1 += 1; return x; }
w2 cw2(w2 x) { x.f1 += 1; x.f2 += 2; return x; }
w3 cw3(w3 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; return x; }
w4 cw4(w4 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; return x; }
w5 cw5(w5 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; return x; }
w6 cw6(w6 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; return x; }
w7 cw7(w7 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; return x; }
w8 cw8(w8 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; return x; }
w9 cw9(w9 x) { x.f1 += 1; x.f2 += 2; x.f3 += 3; x.f4 += 4; x.f5 += 5; x.f6 += 6; x.f7 += 7; x.f8 += 8; x.f9 += 9; return x; }

]]

local ca0 = c.ca0
local cb1, cb2, cb3, cb4, cb5, cb6, cb7, cb8, cb9 = c.cb1, c.cb2, c.cb3, c.cb4, c.cb5, c.cb6, c.cb7, c.cb8, c.cb9
local cc1, cc2, cc3, cc4, cc5, cc6, cc7, cc8, cc9 = c.cc1, c.cc2, c.cc3, c.cc4, c.cc5, c.cc6, c.cc7, c.cc8, c.cc9
local cd1, cd2, cd3, cd4, cd5, cd6, cd7, cd8, cd9 = c.cd1, c.cd2, c.cd3, c.cd4, c.cd5, c.cd6, c.cd7, c.cd8, c.cd9
local ce1, ce2, ce3, ce4, ce5, ce6, ce7, ce8, ce9 = c.ce1, c.ce2, c.ce3, c.ce4, c.ce5, c.ce6, c.ce7, c.ce8, c.ce9
local cf1, cf2, cf3, cf4, cf5, cf6, cf7, cf8, cf9 = c.cf1, c.cf2, c.cf3, c.cf4, c.cf5, c.cf6, c.cf7, c.cf8, c.cf9
local cg1, cg2, cg3, cg4, cg5, cg6, cg7, cg8, cg9 = c.cg1, c.cg2, c.cg3, c.cg4, c.cg5, c.cg6, c.cg7, c.cg8, c.cg9

terra ta0() end

terra tb1(x : int8) return x + 1 end
terra tb2(x : int8, y : int8) return x + y end
terra tb3(x : int8, y : int8, z : int8) return x + y + z end
terra tb4(x : int8, y : int8, z : int8, w : int8) return x + y + z + w end
terra tb5(x : int8, y : int8, z : int8, w : int8, v : int8) return x + y + z + w + v end
terra tb6(x : int8, y : int8, z : int8, w : int8, v : int8, u : int8) return x + y + z + w + v + u end
terra tb7(x : int8, y : int8, z : int8, w : int8, v : int8, u : int8, t : int8) return x + y + z + w + v + u + t end
terra tb8(x : int8, y : int8, z : int8, w : int8, v : int8, u : int8, t : int8, s : int8) return x + y + z + w + v + u + t + s end
terra tb9(x : int8, y : int8, z : int8, w : int8, v : int8, u : int8, t : int8, s : int8, r : int8) return x + y + z + w + v + u + t + s + r end

terra tc1(x : int16) return x + 1 end
terra tc2(x : int16, y : int16) return x + y end
terra tc3(x : int16, y : int16, z : int16) return x + y + z end
terra tc4(x : int16, y : int16, z : int16, w : int16) return x + y + z + w end
terra tc5(x : int16, y : int16, z : int16, w : int16, v : int16) return x + y + z + w + v end
terra tc6(x : int16, y : int16, z : int16, w : int16, v : int16, u : int16) return x + y + z + w + v + u end
terra tc7(x : int16, y : int16, z : int16, w : int16, v : int16, u : int16, t : int16) return x + y + z + w + v + u + t end
terra tc8(x : int16, y : int16, z : int16, w : int16, v : int16, u : int16, t : int16, s : int16) return x + y + z + w + v + u + t + s end
terra tc9(x : int16, y : int16, z : int16, w : int16, v : int16, u : int16, t : int16, s : int16, r : int16) return x + y + z + w + v + u + t + s + r end

terra td1(x : int32) return x + 1 end
terra td2(x : int32, y : int32) return x + y end
terra td3(x : int32, y : int32, z : int32) return x + y + z end
terra td4(x : int32, y : int32, z : int32, w : int32) return x + y + z + w end
terra td5(x : int32, y : int32, z : int32, w : int32, v : int32) return x + y + z + w + v end
terra td6(x : int32, y : int32, z : int32, w : int32, v : int32, u : int32) return x + y + z + w + v + u end
terra td7(x : int32, y : int32, z : int32, w : int32, v : int32, u : int32, t : int32) return x + y + z + w + v + u + t end
terra td8(x : int32, y : int32, z : int32, w : int32, v : int32, u : int32, t : int32, s : int32) return x + y + z + w + v + u + t + s end
terra td9(x : int32, y : int32, z : int32, w : int32, v : int32, u : int32, t : int32, s : int32, r : int32) return x + y + z + w + v + u + t + s + r end

terra te1(x : int64) return x + 1 end
terra te2(x : int64, y : int64) return x + y end
terra te3(x : int64, y : int64, z : int64) return x + y + z end
terra te4(x : int64, y : int64, z : int64, w : int64) return x + y + z + w end
terra te5(x : int64, y : int64, z : int64, w : int64, v : int64) return x + y + z + w + v end
terra te6(x : int64, y : int64, z : int64, w : int64, v : int64, u : int64) return x + y + z + w + v + u end
terra te7(x : int64, y : int64, z : int64, w : int64, v : int64, u : int64, t : int64) return x + y + z + w + v + u + t end
terra te8(x : int64, y : int64, z : int64, w : int64, v : int64, u : int64, t : int64, s : int64) return x + y + z + w + v + u + t + s end
terra te9(x : int64, y : int64, z : int64, w : int64, v : int64, u : int64, t : int64, s : int64, r : int64) return x + y + z + w + v + u + t + s + r end

terra tf1(x : float) return x + 1 end
terra tf2(x : float, y : float) return x + y end
terra tf3(x : float, y : float, z : float) return x + y + z end
terra tf4(x : float, y : float, z : float, w : float) return x + y + z + w end
terra tf5(x : float, y : float, z : float, w : float, v : float) return x + y + z + w + v end
terra tf6(x : float, y : float, z : float, w : float, v : float, u : float) return x + y + z + w + v + u end
terra tf7(x : float, y : float, z : float, w : float, v : float, u : float, t : float) return x + y + z + w + v + u + t end
terra tf8(x : float, y : float, z : float, w : float, v : float, u : float, t : float, s : float) return x + y + z + w + v + u + t + s end
terra tf9(x : float, y : float, z : float, w : float, v : float, u : float, t : float, s : float, r : float) return x + y + z + w + v + u + t + s + r end

terra tg1(x : double) return x + 1 end
terra tg2(x : double, y : double) return x + y end
terra tg3(x : double, y : double, z : double) return x + y + z end
terra tg4(x : double, y : double, z : double, w : double) return x + y + z + w end
terra tg5(x : double, y : double, z : double, w : double, v : double) return x + y + z + w + v end
terra tg6(x : double, y : double, z : double, w : double, v : double, u : double) return x + y + z + w + v + u end
terra tg7(x : double, y : double, z : double, w : double, v : double, u : double, t : double) return x + y + z + w + v + u + t end
terra tg8(x : double, y : double, z : double, w : double, v : double, u : double, t : double, s : double) return x + y + z + w + v + u + t + s end
terra tg9(x : double, y : double, z : double, w : double, v : double, u : double, t : double, s : double, r : double) return x + y + z + w + v + u + t + s + r end

local p0 = c.p0

terra tp0(x : p0) return x; end

local q1, q2, q3, q4, q5, q6, q7, q8, q9 = c.q1, c.q2, c.q3, c.q4, c.q5, c.q6, c.q7, c.q8, c.q9

terra tq1(x : q1) x.f1 = x.f1 + 1; return x; end
terra tq2(x : q2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tq3(x : q3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tq4(x : q4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tq5(x : q5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tq6(x : q6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tq7(x : q7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tq8(x : q8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tq9(x : q9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local r1, r2, r3, r4, r5, r6, r7, r8, r9 = c.r1, c.r2, c.r3, c.r4, c.r5, c.r6, c.r7, c.r8, c.r9

terra tr1(x : r1) x.f1 = x.f1 + 1; return x; end
terra tr2(x : r2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tr3(x : r3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tr4(x : r4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tr5(x : r5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tr6(x : r6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tr7(x : r7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tr8(x : r8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tr9(x : r9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local s1, s2, s3, s4, s5, s6, s7, s8, s9 = c.s1, c.s2, c.s3, c.s4, c.s5, c.s6, c.s7, c.s8, c.s9

terra ts1(x : s1) x.f1 = x.f1 + 1; return x; end
terra ts2(x : s2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra ts3(x : s3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra ts4(x : s4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra ts5(x : s5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra ts6(x : s6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra ts7(x : s7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra ts8(x : s8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra ts9(x : s9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local t1, t2, t3, t4, t5, t6, t7, t8, t9 = c.t1, c.t2, c.t3, c.t4, c.t5, c.t6, c.t7, c.t8, c.t9

terra tt1(x : t1) x.f1 = x.f1 + 1; return x; end
terra tt2(x : t2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tt3(x : t3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tt4(x : t4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tt5(x : t5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tt6(x : t6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tt7(x : t7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tt8(x : t8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tt9(x : t9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local u1, u2, u3, u4, u5, u6, u7, u8, u9 = c.u1, c.u2, c.u3, c.u4, c.u5, c.u6, c.u7, c.u8, c.u9

terra tu1(x : u1) x.f1 = x.f1 + 1; return x; end
terra tu2(x : u2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tu3(x : u3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tu4(x : u4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tu5(x : u5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tu6(x : u6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tu7(x : u7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tu8(x : u8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tu9(x : u9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local v1, v2, v3, v4, v5, v6, v7, v8, v9 = c.v1, c.v2, c.v3, c.v4, c.v5, c.v6, c.v7, c.v8, c.v9

terra tv1(x : v1) x.f1 = x.f1 + 1; return x; end
terra tv2(x : v2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tv3(x : v3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tv4(x : v4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tv5(x : v5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tv6(x : v6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tv7(x : v7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tv8(x : v8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tv9(x : v9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local w1, w2, w3, w4, w5, w6, w7, w8, w9 = c.w1, c.w2, c.w3, c.w4, c.w5, c.w6, c.w7, c.w8, c.w9

terra tw1(x : w1) x.f1 = x.f1 + 1; return x; end
terra tw2(x : w2) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; return x; end
terra tw3(x : w3) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; return x; end
terra tw4(x : w4) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; return x; end
terra tw5(x : w5) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; return x; end
terra tw6(x : w6) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; return x; end
terra tw7(x : w7) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; return x; end
terra tw8(x : w8) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; return x; end
terra tw9(x : w9) x.f1 = x.f1 + 1; x.f2 = x.f2 + 2; x.f3 = x.f3 + 3; x.f4 = x.f4 + 4; x.f5 = x.f5 + 5; x.f6 = x.f6 + 6; x.f7 = x.f7 + 7; x.f8 = x.f8 + 8; x.f9 = x.f9 + 9; return x; end

local qs = {q1, q2, q3, q4, q5, q6, q7, q8, q9}
local cqs = {c.cq1, c.cq2, c.cq3, c.cq4, c.cq5, c.cq6, c.cq7, c.cq8, c.cq9}
local tqs = {tq1, tq2, tq3, tq4, tq5, tq6, tq7, tq8, tq9}

local rs = {r1, r2, r3, r4, r5, r6, r7, r8, r9}
local crs = {c.cr1, c.cr2, c.cr3, c.cr4, c.cr5, c.cr6, c.cr7, c.cr8, c.cr9}
local trs = {tr1, tr2, tr3, tr4, tr5, tr6, tr7, tr8, tr9}

local ss = {s1, s2, s3, s4, s5, s6, s7, s8, s9}
local css = {c.cs1, c.cs2, c.cs3, c.cs4, c.cs5, c.cs6, c.cs7, c.cs8, c.cs9}
local tss = {ts1, ts2, ts3, ts4, ts5, ts6, ts7, ts8, ts9}

local ts = {t1, t2, t3, t4, t5, t6, t7, t8, t9}
local cts = {c.ct1, c.ct2, c.ct3, c.ct4, c.ct5, c.ct6, c.ct7, c.ct8, c.ct9}
local tts = {tt1, tt2, tt3, tt4, tt5, tt6, tt7, tt8, tt9}

local us = {u1, u2, u3, u4, u5, u6, u7, u8, u9}
local cus = {c.cu1, c.cu2, c.cu3, c.cu4, c.cu5, c.cu6, c.cu7, c.cu8, c.cu9}
local tus = {tu1, tu2, tu3, tu4, tu5, tu6, tu7, tu8, tu9}

local vs = {v1, v2, v3, v4, v5, v6, v7, v8, v9}
local cvs = {c.cv1, c.cv2, c.cv3, c.cv4, c.cv5, c.cv6, c.cv7, c.cv8, c.cv9}
local tvs = {tv1, tv2, tv3, tv4, tv5, tv6, tv7, tv8, tv9}

local ws = {w1, w2, w3, w4, w5, w6, w7, w8, w9}
local cws = {c.cw1, c.cw2, c.cw3, c.cw4, c.cw5, c.cw6, c.cw7, c.cw8, c.cw9}
local tws = {tw1, tw2, tw3, tw4, tw5, tw6, tw7, tw8, tw9}

-- Generate a unique exit condition for each test site.
local exit_condition = 1
local teq = macro(
  function(arg, value)
    exit_condition = exit_condition + 1
    return quote
      if arg ~= value then
        return exit_condition -- failure
      end
    end
  end)

local init_fields = macro(
  function(arg, value, num_fields)
    return quote
      escape
        for i = 1, num_fields:asvalue() do
          emit quote
            arg.["f"..i] = value*i
          end
        end
      end
    end
  end)

local check_fields = macro(
  function(arg, value, num_fields)
    return quote
      escape
        for i = 1, num_fields:asvalue() do
          emit quote
            teq(arg.["f"..i], value*i)
          end
        end
      end
    end
  end)

terra part1()
  ca0()
  ta0()

  teq(cb1(1), 2)
  teq(tb1(1), 2)
  teq(cb2(1, 2), 3)
  teq(tb2(1, 2), 3)
  teq(cb3(1, 2, 3), 6)
  teq(tb3(1, 2, 3), 6)
  teq(cb4(1, 2, 3, 4), 10)
  teq(tb4(1, 2, 3, 4), 10)
  teq(cb5(1, 2, 3, 4, 5), 15)
  teq(tb5(1, 2, 3, 4, 5), 15)
  teq(cb6(1, 2, 3, 4, 5, 6), 21)
  teq(tb6(1, 2, 3, 4, 5, 6), 21)
  teq(cb7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(tb7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(cb8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(tb8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(cb9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(tb9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  teq(cc1(1), 2)
  teq(tc1(1), 2)
  teq(cc2(1, 2), 3)
  teq(tc2(1, 2), 3)
  teq(cc3(1, 2, 3), 6)
  teq(tc3(1, 2, 3), 6)
  teq(cc4(1, 2, 3, 4), 10)
  teq(tc4(1, 2, 3, 4), 10)
  teq(cc5(1, 2, 3, 4, 5), 15)
  teq(tc5(1, 2, 3, 4, 5), 15)
  teq(cc6(1, 2, 3, 4, 5, 6), 21)
  teq(tc6(1, 2, 3, 4, 5, 6), 21)
  teq(cc7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(tc7(1, 2, 3, 4, 5, 6, 7), 28)
  teq(cc8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(tc8(1, 2, 3, 4, 5, 6, 7, 8), 36)
  teq(cc9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)
  teq(tc9(1, 2, 3, 4, 5, 6, 7, 8, 9), 45)

  teq(cd1(1), 2)
  teq(td1(1), 2)
  teq(cd2(10, 2), 12)
  teq(td2(10, 2), 12)
  teq(cd3(100, 20, 3), 123)
  teq(td3(100, 20, 3), 123)
  teq(cd4(1000, 200, 30, 4), 1234)
  teq(td4(1000, 200, 30, 4), 1234)
  teq(cd5(10000, 2000, 300, 40, 5), 12345)
  teq(td5(10000, 2000, 300, 40, 5), 12345)
  teq(cd6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(td6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(cd7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(td7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(cd8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(td8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(cd9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(td9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(ce1(1), 2)
  teq(te1(1), 2)
  teq(ce2(10, 2), 12)
  teq(te2(10, 2), 12)
  teq(ce3(100, 20, 3), 123)
  teq(te3(100, 20, 3), 123)
  teq(ce4(1000, 200, 30, 4), 1234)
  teq(te4(1000, 200, 30, 4), 1234)
  teq(ce5(10000, 2000, 300, 40, 5), 12345)
  teq(te5(10000, 2000, 300, 40, 5), 12345)
  teq(ce6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(te6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(ce7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(te7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(ce8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(te8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(ce9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(te9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(cf1(1), 2)
  teq(tf1(1), 2)
  teq(cf2(10, 2), 12)
  teq(tf2(10, 2), 12)
  teq(cf3(100, 20, 3), 123)
  teq(tf3(100, 20, 3), 123)
  teq(cf4(1000, 200, 30, 4), 1234)
  teq(tf4(1000, 200, 30, 4), 1234)
  teq(cf5(10000, 2000, 300, 40, 5), 12345)
  teq(tf5(10000, 2000, 300, 40, 5), 12345)
  teq(cf6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(tf6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(cf7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(tf7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(cf8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(tf8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(cf9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(tf9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(cg1(1), 2)
  teq(tg1(1), 2)
  teq(cg2(10, 2), 12)
  teq(tg2(10, 2), 12)
  teq(cg3(100, 20, 3), 123)
  teq(tg3(100, 20, 3), 123)
  teq(cg4(1000, 200, 30, 4), 1234)
  teq(tg4(1000, 200, 30, 4), 1234)
  teq(cg5(10000, 2000, 300, 40, 5), 12345)
  teq(tg5(10000, 2000, 300, 40, 5), 12345)
  teq(cg6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(tg6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(cg7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(tg7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(cg8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(tg8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(cg9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(tg9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  return 0
end
part1:compile() -- workaround: function at line 620 has more than 60 upvalues
-- part1:printpretty(false)

terra part2()
  var x0 : p0
  var cx0 = c.cp0(x0)
  var tx0 = tp0(x0)

  escape
    for i, qi in ipairs(qs) do
      local cqi = cqs[i]
      local tqi = tqs[i]
      emit quote
        var xi : qi
        init_fields(xi, 10, i)
        var cxi = cqi(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tqi(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, ri in ipairs(rs) do
      local cri = crs[i]
      local tri = trs[i]
      emit quote
        var xi : ri
        init_fields(xi, 10, i)
        var cxi = cri(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tri(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, si in ipairs(ss) do
      local csi = css[i]
      local tsi = tss[i]
      emit quote
        var xi : si
        init_fields(xi, 10, i)
        var cxi = csi(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tsi(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, ti in ipairs(ts) do
      local cti = cts[i]
      local tti = tts[i]
      emit quote
        var xi : ti
        init_fields(xi, 10, i)
        var cxi = cti(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tti(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, ui in ipairs(us) do
      local cui = cus[i]
      local tui = tus[i]
      emit quote
        var xi : ui
        init_fields(xi, 10, i)
        var cxi = cui(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tui(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, vi in ipairs(vs) do
      local cvi = cvs[i]
      local tvi = tvs[i]
      emit quote
        var xi : vi
        init_fields(xi, 10, i)
        var cxi = cvi(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = tvi(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  escape
    for i, wi in ipairs(ws) do
      local cwi = cws[i]
      local twi = tws[i]
      emit quote
        var xi : wi
        init_fields(xi, 10, i)
        var cxi = cwi(xi)
        check_fields(xi, 10, i)
        check_fields(cxi, 11, i)
        var txi = twi(xi)
        check_fields(xi, 10, i)
        check_fields(txi, 11, i)
      end
    end
  end

  return 0
end
-- part2:printpretty(false)

terra main()
  var err = part1()
  if err ~= 0 then
    return err
  end

  err = part2()
  if err ~= 0 then
    return err
  end
  return 0
end

-- Useful for debugging:
-- print(terralib.saveobj(nil, "llvmir", {main=main}, nil, nil, false))
test.eq(main(), 0)
