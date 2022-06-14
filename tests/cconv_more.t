-- Elliott: This is my attempt to me more systematic about checking Terra's
-- calling convention support, particularly against C.
--
-- This test covers:
--
--  * Passing 0..N ints as separate arguments to a function.
--  * Same with 1..N doubles.
--  * Passing (and returning) a struct with 0..N int fields.
--  * Same with 1..N double fields.
--  * Same with 1..N fields of rotating types (char, short, int, long long,
--    double), chosen to maximize padding.
--
-- A couple notable features (especially compared to cconv.t):
--
--  * The tests verify that structs are passed by value, by modifying the
--    arguments within the called functions.
--
--  * As compared to cconv.t, this test notably verifies that Terra can call
--    both itself and C. The latter is particularly important for using
--    external libraries.
--
--  * As a bonus, the use of C allows quick comparisons between Clang's and
--    Terra's output. A command to generate the LLVM IR is shown (commented)
--    at the bottom of the file.

local test = require("test")

local c = terralib.includecstring [[
#include <stdio.h>
#include <stdlib.h>

typedef struct s0 {} s0;
typedef struct s1 { int f1; } s1;
typedef struct s2 { int f1; int f2; } s2;
typedef struct s3 { int f1; int f2; int f3; } s3;
typedef struct s4 { int f1; int f2; int f3; int f4; } s4;
typedef struct s5 { int f1; int f2; int f3; int f4; int f5; } s5;
typedef struct s6 { int f1; int f2; int f3; int f4; int f5; int f6; } s6;
typedef struct s7 { int f1; int f2; int f3; int f4; int f5; int f6; int f7; } s7;
typedef struct s8 { int f1; int f2; int f3; int f4; int f5; int f6; int f7; int f8; } s8;
typedef struct s9 { int f1; int f2; int f3; int f4; int f5; int f6; int f7; int f8; int f9; } s9;

typedef struct t1 { double f1; } t1;
typedef struct t2 { double f1; double f2; } t2;
typedef struct t3 { double f1; double f2; double f3; } t3;
typedef struct t4 { double f1; double f2; double f3; double f4; } t4;
typedef struct t5 { double f1; double f2; double f3; double f4; double f5; } t5;
typedef struct t6 { double f1; double f2; double f3; double f4; double f5; double f6; } t6;
typedef struct t7 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; } t7;
typedef struct t8 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; double f8; } t8;
typedef struct t9 { double f1; double f2; double f3; double f4; double f5; double f6; double f7; double f8; double f9; } t9;

typedef struct u1 { char f1; } u1;
typedef struct u2 { char f1; short f2; } u2;
typedef struct u3 { char f1; short f2; int f3; } u3;
typedef struct u4 { char f1; short f2; int f3; long long f4; } u4;
typedef struct u5 { char f1; short f2; int f3; long long f4; double f5; } u5;
typedef struct u6 { char f1; short f2; int f3; long long f4; double f5; char f6; } u6;
typedef struct u7 { char f1; short f2; int f3; long long f4; double f5; char f6; short f7; } u7;
typedef struct u8 { char f1; short f2; int f3; long long f4; double f5; char f6; short f7; int f8; } u8;
typedef struct u9 { char f1; short f2; int f3; long long f4; double f5; char f6; short f7; int f8; long long f9; } u9;

void ca0() {}
int ca1(int x) { return x + 1; }
int ca2(int x, int y) { return x + y; }
int ca3(int x, int y, int z) { return x + y + z; }
int ca4(int x, int y, int z, int w) { return x + y + z + w; }
int ca5(int x, int y, int z, int w, int v) { return x + y + z + w + v; }
int ca6(int x, int y, int z, int w, int v, int u) { return x + y + z + w + v + u; }
int ca7(int x, int y, int z, int w, int v, int u, int t) { return x + y + z + w + v + u + t; }
int ca8(int x, int y, int z, int w, int v, int u, int t, int s) { return x + y + z + w + v + u + t + s; }
int ca9(int x, int y, int z, int w, int v, int u, int t, int s, int r) { return x + y + z + w + v + u + t + s + r; }

double cb1(double x) { return x + 1; }
double cb2(double x, double y) { return x + y; }
double cb3(double x, double y, double z) { return x + y + z; }
double cb4(double x, double y, double z, double w) { return x + y + z + w; }
double cb5(double x, double y, double z, double w, double v) { return x + y + z + w + v; }
double cb6(double x, double y, double z, double w, double v, double u) { return x + y + z + w + v + u; }
double cb7(double x, double y, double z, double w, double v, double u, double t) { return x + y + z + w + v + u + t; }
double cb8(double x, double y, double z, double w, double v, double u, double t, double s) { return x + y + z + w + v + u + t + s; }
double cb9(double x, double y, double z, double w, double v, double u, double t, double s, double r) { return x + y + z + w + v + u + t + s + r; }

s0 cs0(s0 x) { return x; }
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

]]

terra ta0()
end

terra ta1(x : int) : int
  return x + 1
end

terra ta2(x : int, y : int) : int
  return x + y
end

terra ta3(x : int, y : int, z : int) : int
  return x + y + z
end

terra ta4(x : int, y : int, z : int, w : int) : int
  return x + y + z + w
end

terra ta5(x : int, y : int, z : int, w : int, v : int) : int
  return x + y + z + w + v
end

terra ta6(x : int, y : int, z : int, w : int, v : int, u : int) : int
  return x + y + z + w + v + u
end

terra ta7(x : int, y : int, z : int, w : int, v : int, u : int, t : int) : int
  return x + y + z + w + v + u + t
end

terra ta8(x : int, y : int, z : int, w : int, v : int, u : int, t : int, s : int) : int
  return x + y + z + w + v + u + t + s
end

terra ta9(x : int, y : int, z : int, w : int, v : int, u : int, t : int, s : int, r : int) : int
  return x + y + z + w + v + u + t + s + r
end

terra tb1(x : double) : double
  return x + 1
end

terra tb2(x : double, y : double) : double
  return x + y
end

terra tb3(x : double, y : double, z : double) : double
  return x + y + z
end

terra tb4(x : double, y : double, z : double, w : double) : double
  return x + y + z + w
end

terra tb5(x : double, y : double, z : double, w : double, v : double) : double
  return x + y + z + w + v
end

terra tb6(x : double, y : double, z : double, w : double, v : double, u : double) : double
  return x + y + z + w + v + u
end

terra tb7(x : double, y : double, z : double, w : double, v : double, u : double, t : double) : double
  return x + y + z + w + v + u + t
end

terra tb8(x : double, y : double, z : double, w : double, v : double, u : double, t : double, s : double) : double
  return x + y + z + w + v + u + t + s
end

terra tb9(x : double, y : double, z : double, w : double, v : double, u : double, t : double, s : double, r : double) : double
  return x + y + z + w + v + u + t + s + r
end

local s0, s1, s2, s3, s4, s5, s6, s7, s8, s9 = c.s0, c.s1, c.s2, c.s3, c.s4, c.s5, c.s6, c.s7, c.s8, c.s9

terra ts0(x : s0) : s0
  return x
end

terra ts1(x : s1) : s1
  x.f1 = x.f1 + 1
  return x
end

terra ts2(x : s2) : s2
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  return x
end

terra ts3(x : s3) : s3
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  return x
end

terra ts4(x : s4) : s4
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  return x
end

terra ts5(x : s5) : s5
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  return x
end

terra ts6(x : s6) : s6
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  return x
end

terra ts7(x : s7) : s7
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  return x
end

terra ts8(x : s8) : s8
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  return x
end

terra ts9(x : s9) : s9
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  x.f9 = x.f9 + 9
  return x
end

local t1, t2, t3, t4, t5, t6, t7, t8, t9 = c.t1, c.t2, c.t3, c.t4, c.t5, c.t6, c.t7, c.t8, c.t9

terra tt1(x : t1) : t1
  x.f1 = x.f1 + 1
  return x
end

terra tt2(x : t2) : t2
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  return x
end

terra tt3(x : t3) : t3
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  return x
end

terra tt4(x : t4) : t4
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  return x
end

terra tt5(x : t5) : t5
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  return x
end

terra tt6(x : t6) : t6
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  return x
end

terra tt7(x : t7) : t7
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  return x
end

terra tt8(x : t8) : t8
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  return x
end

terra tt9(x : t9) : t9
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  x.f9 = x.f9 + 9
  return x
end

local u1, u2, u3, u4, u5, u6, u7, u8, u9 = c.u1, c.u2, c.u3, c.u4, c.u5, c.u6, c.u7, c.u8, c.u9

terra tu1(x : u1) : u1
  x.f1 = x.f1 + 1
  return x
end

terra tu2(x : u2) : u2
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  return x
end

terra tu3(x : u3) : u3
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  return x
end

terra tu4(x : u4) : u4
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  return x
end

terra tu5(x : u5) : u5
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  return x
end

terra tu6(x : u6) : u6
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  return x
end

terra tu7(x : u7) : u7
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  return x
end

terra tu8(x : u8) : u8
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  return x
end

terra tu9(x : u9) : u9
  x.f1 = x.f1 + 1
  x.f2 = x.f2 + 2
  x.f3 = x.f3 + 3
  x.f4 = x.f4 + 4
  x.f5 = x.f5 + 5
  x.f6 = x.f6 + 6
  x.f7 = x.f7 + 7
  x.f8 = x.f8 + 8
  x.f9 = x.f9 + 9
  return x
end

local ss = {s0, s1, s2, s3, s4, s5, s6, s7, s8, s9}
local css = {c.cs0, c.cs1, c.cs2, c.cs3, c.cs4, c.cs5, c.cs6, c.cs7, c.cs8, c.cs9}
local tss = {ts0, ts1, ts2, ts3, ts4, ts5, ts6, ts7, ts8, ts9}

local ts = {t1, t2, t3, t4, t5, t6, t7, t8, t9}
local cts = {c.ct1, c.ct2, c.ct3, c.ct4, c.ct5, c.ct6, c.ct7, c.ct8, c.ct9}
local tts = {tt1, tt2, tt3, tt4, tt5, tt6, tt7, tt8, tt9}

local us = {u1, u2, u3, u4, u5, u6, u7, u8, u9}
local cus = {c.cu1, c.cu2, c.cu3, c.cu4, c.cu5, c.cu6, c.cu7, c.cu8, c.cu9}
local tus = {tu1, tu2, tu3, tu4, tu5, tu6, tu7, tu8, tu9}

-- Generate a unique exit condition for each test site.
local exit_condition = 1
local teq = macro(
  function(arg, value)
    exit_condition = exit_condition + 1
    return quote
      if arg ~= value then
        return exit_condition -- failure
        -- var stderr = c.fdopen(2, "w")
        -- c.fprintf(stderr, "assertion failed\n")
        -- c.fflush(stderr)
        -- c.abort()
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

terra main()
  c.ca0()
  ta0()
  teq(c.ca1(1), 2)
  teq(ta1(1), 2)
  teq(c.ca2(10, 2), 12)
  teq(ta2(10, 2), 12)
  teq(c.ca3(100, 20, 3), 123)
  teq(ta3(100, 20, 3), 123)
  teq(c.ca4(1000, 200, 30, 4), 1234)
  teq(ta4(1000, 200, 30, 4), 1234)
  teq(c.ca5(10000, 2000, 300, 40, 5), 12345)
  teq(ta5(10000, 2000, 300, 40, 5), 12345)
  teq(c.ca6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(ta6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.ca7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(ta7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.ca8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(ta8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.ca9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(ta9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  teq(c.cb1(1), 2)
  teq(tb1(1), 2)
  teq(c.cb2(10, 2), 12)
  teq(tb2(10, 2), 12)
  teq(c.cb3(100, 20, 3), 123)
  teq(tb3(100, 20, 3), 123)
  teq(c.cb4(1000, 200, 30, 4), 1234)
  teq(tb4(1000, 200, 30, 4), 1234)
  teq(c.cb5(10000, 2000, 300, 40, 5), 12345)
  teq(tb5(10000, 2000, 300, 40, 5), 12345)
  teq(c.cb6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(tb6(100000, 20000, 3000, 400, 50, 6), 123456)
  teq(c.cb7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(tb7(1000000, 200000, 30000, 4000, 500, 60, 7), 1234567)
  teq(c.cb8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(tb8(10000000, 2000000, 300000, 40000, 5000, 600, 70, 8), 12345678)
  teq(c.cb9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)
  teq(tb9(100000000, 20000000, 3000000, 400000, 50000, 6000, 700, 80, 9), 123456789)

  escape
    for i, si in ipairs(ss) do
      local csi = css[i]
      local tsi = tss[i]
      emit quote
        var xi : si
        init_fields(xi, 10, i-1)
        var cxi = csi(xi)
        check_fields(xi, 10, i-1)
        check_fields(cxi, 11, i-1)
        var txi = tsi(xi)
        check_fields(xi, 10, i-1)
        check_fields(txi, 11, i-1)
      end
    end
  end

  -- FIXME: PPC: double limit is 8 (at 9+ they switch over to sret/byval structs)
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
  return 0
end
-- Useful for debugging:
-- print(terralib.saveobj(nil, "llvmir", {main=main}, nil, nil, false))
test.eq(main(), 0)
