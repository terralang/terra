
local test = require("test")

terra f1(a : int)
	return a
end

terra c1()
	return 1 + f1(4),f1(4)
end

terra f2(a : int, b : float)
	return a + b
end

terra c2()
	return f2(3,4) + 1, f2(3,4)
end


terra f3()
	return 3,4
end

terra c3()
    var r = f3()
	return f3()._0 + 1,unpackstruct(r) 
end

terra f4() : {float,float}
	return 3.25,4.25
end

terra c4()
    var r = f4()
	return f4()._0 + 1, unpackstruct(r) 
end


terra f5(a : int) : {uint8,uint8,uint8,uint8}
	return 0,1,a,3
end

terra c5()
    var r = f5(8)
	return f5(8)._0 + 1, unpackstruct(r)
end

terra f6() : {double, double, int}
	return 3.25, 4.25, 3
end

terra c6()
    var r = f6()
	return f6()._0 + 1, unpackstruct(r)
end
test.meq({4.25, 3.25,4.25,3},c6())

terra f7(a : int) : {double, double, int}
	return 3.25, 4.25, a
end

terra c7()
    var r = f7(4)
	return f7(4)._0 + 1, unpackstruct(r)
end
test.meq({4.25,3.25,4.25,4},c7())

terra f8() : {double, double}
	return 3.25, 4.25
end

terra c8()
    var r= f8()
	return f8()._0 + 1, unpackstruct(r)
end

test.meq({4.25,3.25,4.25},c8())

struct S1 {
	a : int;
	b : int;
}

terra f9(a : S1)
	return a.a+1,a.b+2
end

terra c9()
	var a = S1 { 4, 5}
	var r = f9(a)
	return f9(a)._0 + 1, unpackstruct(r)
end
test.meq({6,5,7},c9())

struct S2 {
	a : int;
	b : double;
	c : double;
}

terra f10(a : S2)
	return a.a, a.b, a.c
end

terra c10()
	var s2 = S2 { 4,5,6 }
	var r = f10(s2)
	return f10(s2)._0 + 1, unpackstruct(r) 
end

test.meq({5,4,5,6},c10())

C = terralib.includec("stdio.h")

terra f11(a : int)
	C.printf("f11 %d\n",a)
end


terra c11()
	f11(7)
end
c11()

struct S3 {
	a : vector(float,2);
	b : double;
}

struct S4 {
	b : double;
	a : vector(float,2);
}

struct S5 {
	a : vector(uint8,4);
	b : int;
}

terra f12a(a : S3) 
	return a.a[0] + a.a[1], a.b
end

terra c12a()
	var a = S3 { vector(2.25f, 3.25f), 4 }
	var r = f12a(a)
	return f12a(a)._0 + 1, unpackstruct(r)
end
test.meq({6.5,5.5,4},c12a())

terra f12b(a : S4) 
	return a.a[0] + a.a[1], a.b
end

terra c12b()
	var a = S4 { 4, vector(2.25f, 3.25f) }
	var r = f12b(a)
	return f12b(a)._0 + 1, unpackstruct(r)
end
test.meq({6.5,5.5,4},c12b())


terra f12()
	var a = S3 { vector(8.f,2.f), 3.0 }
	var b = S4 {  3.0, vector(8.f,2.f) }
	var c,d = f12a(a)
	var e,f = f12b(b)
	return c,d,e,f
end

terra f13a(a : S5)
	return a.a[0] + a.a[1] + a.a[2] + a.a[3], a.b
end

terra f13()
	var a = S5 { vectorof(int8, 1,2,3,4), 5 }
	return f13a(a)
end


struct S6 {
	a : float;
	aa : float;
	b : float
}

struct S7a {
	a : int;
	b : int;
}
struct S7 {
	a : int;
	b : S7a;
	c : int;
}

terra f14(a : S6)
	return a.a,a.aa,a.b
end

terra c14()
	var a = S6 { 4,2,3}
	var r = f14(a)
	return f14(a)._0 + 1, unpackstruct(r)
end
test.meq({5,4,2,3},c14())

terra f15(a : S7)
	return a.a, a.b.a, a.b.b, a.c
end

terra c15()
	var a = S7 {1, S7a { 2,3 }, 4}
	var r = f15(a)
	return f15(a)._0 + 1, unpackstruct(r)
end

test.meq({2,1,2,3,4}, c15())

struct S8 {
	a : uint8[7];
}

terra f16(a : S8)
	return a.a[0],a.a[6]
end

terra c16()
	var a = S8 { arrayof(uint8, 1,2,3,4,5,6,7) }
	var r = f16(a)
	return f16(a)._0 + 1, unpackstruct(r)
end

test.meq({2,1,7},c16())

struct S9 {
	a : uint8[9];
}

terra f17(a : S9)
	return a.a[0],a.a[8]
end

terra c17()
	var a = S9 { arrayof(uint8, 1,2,3,4,5,6,7,8,9) }
	var r = f17(a)
	return f17(a)._0 + 1, unpackstruct(r)
end


test.meq({2,1,9},c17())


struct S10 {
	a : double;
	b : int64
}


terra f18a(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a5 : int, a : S10)
	return a.a, a.b
end

terra c18a()
    var r = f18a(1,2,3,4,5,6,S10{7,8})
	return f18a(1,2,3,4,5,6,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8},c18a())


terra f18b(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a : S10)
	return a.a, a.b
end

terra c18b()
    var r = f18b(1,2,3,4,5,S10{7,8})
	return f18b(1,2,3,4,5,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8},c18b())

terra f18c(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a : S10)
	return a.a, a.b, a0, a1, a2
end
terra c18c()
    var r = f18c(1,2,3,4,5,S10 {7,8})
	return f18c(1,2,3,4,5,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8,1,2,3},c18c())

struct S11 {
	a : float;
	b : int;
}

terra f18d(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a5 : int, a : S11)
	return a.a, a.b
end
terra c18d()
    var r = f18d(1,2,3,4,5,6,S11{7,8})
	return f18d(1,2,3,4,5,6,S11{7,8})._0 + 1, unpackstruct(r)
end
test.meq({8,7,8},c18d())


terra f18e(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a : S11)
	return a.a, a.b
end

terra c18e()
    var r = f18e(1,2,3,4,5,S11{7,8})
	return f18e(1,2,3,4,5,S11{7,8})._0 + 1, unpackstruct(r) 
end

test.meq({8,7,8},c18e())

terra f18f(a0 : int, a1 : int, a2 : int, a3 : int, a4: int, a : S11)
	return a.a, a.b, a0, a1, a2
end

terra c18f()
    var r = f18f(1,2,3,4,5,S11{7,8})
	return f18f(1,2,3,4,5,S11{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8,1,2,3},c18f())


terra f18g(a0 : float, a1 : float, a2 : float, a3 : float, a4: float, a5 : float, a6 : float, a7 : float, a : S10)
	return a.a, a.b
end

terra c18g()
    var r = f18g(1,2,3,4,5,6,9,10,S10{7,8})
	return f18g(1,2,3,4,5,6,9,10,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8},c18g())

terra f18h(a0 : float, a1 : float, a2 : float, a3 : float, a4: float, a5 : float, a6 : float, a : S10)
	return a.a, a.b
end

terra c18h()
    var r = f18h(1,2,3,4,5,6,9,S10{7,8})
	return f18h(1,2,3,4,5,6,9,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8},c18h())

terra f18i(a0 : float, a1 : float, a2 : float, a3 : float, a4: float, a5 : float, a6 : float, a : S10)
	return a.a, a.b, a0, a1, a2
end

terra c18i()
    var r = f18i(1,2,3,4,5,6,9,S10{7,8})
	return f18i(1,2,3,4,5,6,9,S10{7,8})._0 + 1, unpackstruct(r)
end

test.meq({8,7,8,1,2,3},c18i())

struct S12 {
	a : float;
	b : int;
}

terra f19(a : S12) 
	return a.a, a.b
end
terra c19()
	var a = S12 { 3,5 }
	var r = f19(a)
	return f19(a)._0 + 1, unpackstruct(r)
end
test.meq({4,3,5},c19())



terra f20(a : S10, b : int)
	return a.a,a.b,b
end
terra c20()
    var r = f20(S10{1,2},3)
	return f20(S10{1,2},3)._0 + 1, unpackstruct(r)
end
test.meq({2,1,2,3},c20())


terra f21()
	return
end
f21()

terra f22()
	return S12 { 3, 4}
end
terra c22()
	return f22().a, f22()
end
local s22_0, s22_1 = terralib.unpackstruct(c22())
test.eq(s22_0,3)
test.eq(s22_1.a,3)
test.eq(s22_1.b,4)

terra f23()
	return S10 { 1, 2}
end

terra c23()
	return f23().a, f23()
end
local s23_0, s23_1 = terralib.unpackstruct(c23())
test.eq(s23_0,1)
test.eq(s23_1.a,1)
test.eq(s23_1.b,2)

terra f24()
	return S2 { 1,2,3}
end

terra c24()
	return f24().a, f24()
end
local s24_0, s24_1 = terralib.unpackstruct(c24())
test.eq(s24_0,1)
test.eq(s24_1.a,1)
test.eq(s24_1.b,2)
test.eq(s24_1.c,3)


local s22 = f22()
test.eq(s22.a,3)
test.eq(s22.b,4)

local s23 = f23()
test.eq(s23.a,1)
test.eq(s23.b,2)


local s24 = f24()

test.eq(s24.a,1)
test.eq(s24.b,2)
test.eq(s24.c,3)


test.meq({1,2,3},f20({1,2},3))


test.eq(f1(3),3)
test.eq(f2(4,5),9)
test.meq({3,4},f3())
test.meq({3.25,4.25},f4())
test.meq({0,1,2,3},f5(2))
test.meq({3.25,4.25,3},f6())
test.meq({3.25,4.25,4},f7(4))
test.meq({3.25,4.25},f8())
test.meq({3,5},f9({2,3}))
test.meq({1,2.5,3.5},f10({1,2.5,3.5}))
f11(3)
test.meq({10,3,10,3},f12())
test.meq({10,5},f13())
test.meq({4,5,6},f14({4,5,6}))
test.meq({1,2,3,4},f15({1,{2,3},4}))
test.meq({1,7},f16({{1,2,3,4,5,6,7}}))
test.meq({1,9},f17({{1,2,3,4,5,6,7,8,9}}))
test.meq({7,8},f18a(1,2,3,4,5,6,{7,8}))
test.meq({7,8},f18b(1,2,3,4,5,{7,8}))
test.meq({7,8,1,2,3},f18c(1,2,3,4,5,{7,8}))

test.meq({7,8},f18d(1,2,3,4,5,6,{7,8}))
test.meq({7,8},f18e(1,2,3,4,5,{7,8}))
test.meq({7,8,1,2,3},f18f(1,2,3,4,5,{7,8}))

test.meq({9,10},f18g(1,2,3,4,5,6,7,8,{9,10}))
test.meq({9,10},f18h(1,2,3,4,5,6,7,{9,10}))
test.meq({9,10,1,2,3},f18i(1,2,3,4,5,6,7,{9,10}))

test.meq({4,5}, f19({4,5}))

test.meq({5,4},c1())
test.meq({8,7},c2())
test.meq({4,3,4},c3())
test.meq({4.25,3.25,4.25},c4())
test.meq({1,0,1,8,3},c5())


-- Argument register exhaustion.
--
-- These cases have to cross into C. A Terra-to-Terra call agrees with itself no
-- matter how its arguments get classified, so only calling a Clang-compiled
-- function (or being called by one) can catch a disagreement about which
-- arguments travel in registers and which are passed on the stack.
--
-- Each test sits exactly on the boundary where one of the register files runs
-- out, which is where x86-64 SysV is easiest to get wrong. See
-- https://github.com/terralang/terra/issues/576. The exhaustive version of this
-- lives in cconv_more.t and cconv_fuzz.t; what is here is the short list worth
-- checking on every run.
--
-- Every scalar slot gets a distinct value (1, 2, 3, ...) and the C side returns
-- a weighted sum, so a dropped, duplicated, or reordered argument all show up.

local cc = terralib.includecstring [[
#include <stdint.h>

typedef struct CF2 { float a; float b; } CF2;                 /* one SSE eightbyte */
typedef struct CI1 { int64_t a; } CI1;                        /* one INTEGER eightbyte */
typedef struct CU1 { uint8_t a; } CU1;                        /* one byte, coerces to i8 */
typedef struct CU3 { uint8_t a; uint8_t b; uint8_t c; } CU3;  /* three bytes, coerces to i24 */
typedef struct CIF { int32_t a; float b; } CIF;               /* mixed, one INTEGER eightbyte */
typedef struct CD2 { double a; double b; } CD2;               /* two SSE eightbytes */
typedef struct CBIG { int64_t a; int64_t b; int64_t c; int64_t d; } CBIG;

/* The 8 SSE registers are used up by the first 8 aggregates, so the 9th and 10th
   go on the stack even though integer registers are still free.

   Two of them have to spill, not one: a stack slot for an SSE eightbyte is 8
   bytes wide, but a <2 x float> passed the same way takes 16, so a lone spilled
   argument still lands at the right offset and only the one after it moves. */
__attribute__ ((noinline)) double sse_spill(
    CF2 x1, CF2 x2, CF2 x3, CF2 x4, CF2 x5,
    CF2 x6, CF2 x7, CF2 x8, CF2 x9, CF2 x10) {
  return 1*x1.a + 2*x1.b + 3*x2.a + 4*x2.b + 5*x3.a + 6*x3.b
       + 7*x4.a + 8*x4.b + 9*x5.a + 10*x5.b + 11*x6.a + 12*x6.b
       + 13*x7.a + 14*x7.b + 15*x8.a + 16*x8.b + 17*x9.a + 18*x9.b
       + 19*x10.a + 20*x10.b;
}

/* The 6 integer registers are gone after the 6th aggregate. Clang does not use
   byval here: with no integer register left to hold a pointer it coerces the
   aggregate to an integer of the same size and lets that land on the stack. */
__attribute__ ((noinline)) double int_spill(
    CI1 x1, CI1 x2, CI1 x3, CI1 x4, CI1 x5, CI1 x6, CI1 x7) {
  return 1*x1.a + 2*x2.a + 3*x3.a + 4*x4.a + 5*x5.a + 6*x6.a + 7*x7.a;
}

/* Same, at sizes that are not a whole eightbyte: these coerce to i8 and i24. */
__attribute__ ((noinline)) double int_spill_i8(
    CU1 x1, CU1 x2, CU1 x3, CU1 x4, CU1 x5, CU1 x6, CU1 x7) {
  return 1*x1.a + 2*x2.a + 3*x3.a + 4*x4.a + 5*x5.a + 6*x6.a + 7*x7.a;
}

__attribute__ ((noinline)) double int_spill_i24(
    CU3 x1, CU3 x2, CU3 x3, CU3 x4, CU3 x5, CU3 x6, CU3 x7) {
  return 1*x1.a + 2*x1.b + 3*x1.c + 4*x2.a + 5*x2.b + 6*x2.c
       + 7*x3.a + 8*x3.b + 9*x3.c + 10*x4.a + 11*x4.b + 12*x4.c
       + 13*x5.a + 14*x5.b + 15*x5.c + 16*x6.a + 17*x6.b + 18*x6.c
       + 19*x7.a + 20*x7.b + 21*x7.c;
}

/* A struct of mixed class that still occupies a single INTEGER eightbyte. */
__attribute__ ((noinline)) double int_spill_mixed(
    CIF x1, CIF x2, CIF x3, CIF x4, CIF x5, CIF x6, CIF x7) {
  return 1*x1.a + 2*x1.b + 3*x2.a + 4*x2.b + 5*x3.a + 6*x3.b
       + 7*x4.a + 8*x4.b + 9*x5.a + 10*x5.b + 11*x6.a + 12*x6.b
       + 13*x7.a + 14*x7.b;
}

/* Both register files are exhausted before the aggregate. The coercion is to an
   integer even though the aggregate is SSE classed. */
__attribute__ ((noinline)) double both_spill(
    int64_t i1, int64_t i2, int64_t i3, int64_t i4, int64_t i5, int64_t i6,
    double d1, double d2, double d3, double d4,
    double d5, double d6, double d7, double d8, CF2 x, CF2 y) {
  return 1*i1 + 2*i2 + 3*i3 + 4*i4 + 5*i5 + 6*i6
       + 7*d1 + 8*d2 + 9*d3 + 10*d4 + 11*d5 + 12*d6 + 13*d7 + 14*d8
       + 15*x.a + 16*x.b + 17*y.a + 18*y.b;
}

/* The returned struct is too big for registers, so a hidden pointer takes the
   first integer register and only five are left for i1..i6. The aggregate needs
   no integer register at all, though, so it still travels in SSE registers. */
__attribute__ ((noinline)) CBIG sret_and_int_spill(
    int64_t i1, int64_t i2, int64_t i3, int64_t i4, int64_t i5, int64_t i6,
    CD2 x) {
  double t = 1*i1 + 2*i2 + 3*i3 + 4*i4 + 5*i5 + 6*i6 + 7*x.a + 8*x.b;
  CBIG r;
  r.a = (int64_t)t; r.b = 2*(int64_t)t; r.c = 3*(int64_t)t; r.d = 4*(int64_t)t;
  return r;
}

/* An argument that spills does not consume a register, so the trailing integer
   still arrives in one. */
__attribute__ ((noinline)) double spill_then_reg(
    double d1, double d2, double d3, double d4,
    double d5, double d6, double d7, double d8, CF2 x, CF2 y, int32_t n) {
  return 1*d1 + 2*d2 + 3*d3 + 4*d4 + 5*d5 + 6*d6 + 7*d7 + 8*d8
       + 9*x.a + 10*x.b + 11*y.a + 12*y.b + 13*n;
}

/* The reverse direction: C calls a Terra function whose arguments spill. This
   checks how Terra defines such a function, not just how it calls one. */
typedef double (*sse_spill_fn)(CF2, CF2, CF2, CF2, CF2, CF2, CF2, CF2, CF2, CF2);
__attribute__ ((noinline)) double call_sse_spill(sse_spill_fn f) {
  CF2 a1 = {1,2}, a2 = {3,4}, a3 = {5,6}, a4 = {7,8}, a5 = {9,10};
  CF2 a6 = {11,12}, a7 = {13,14}, a8 = {15,16}, a9 = {17,18}, a10 = {19,20};
  return f(a1, a2, a3, a4, a5, a6, a7, a8, a9, a10);
}

typedef double (*int_spill_fn)(CI1, CI1, CI1, CI1, CI1, CI1, CI1);
__attribute__ ((noinline)) double call_int_spill(int_spill_fn f) {
  CI1 a1 = {1}, a2 = {2}, a3 = {3}, a4 = {4}, a5 = {5}, a6 = {6}, a7 = {7};
  return f(a1, a2, a3, a4, a5, a6, a7);
}
]]

-- Sum of i*i for i = 1..n, which is what each weighted sum above comes to when
-- slot i holds the value i.
local function sumsq(n)
	local s = 0
	for i = 1, n do s = s + i * i end
	return s
end

terra c25()
	return cc.sse_spill(
		cc.CF2 { 1, 2 }, cc.CF2 { 3, 4 }, cc.CF2 { 5, 6 },
		cc.CF2 { 7, 8 }, cc.CF2 { 9, 10 }, cc.CF2 { 11, 12 },
		cc.CF2 { 13, 14 }, cc.CF2 { 15, 16 }, cc.CF2 { 17, 18 },
		cc.CF2 { 19, 20 })
end
test.eq(c25(), sumsq(20))

terra c26()
	return cc.int_spill(
		cc.CI1 { 1 }, cc.CI1 { 2 }, cc.CI1 { 3 }, cc.CI1 { 4 },
		cc.CI1 { 5 }, cc.CI1 { 6 }, cc.CI1 { 7 })
end
test.eq(c26(), sumsq(7))

terra c27()
	return cc.int_spill_i8(
		cc.CU1 { 1 }, cc.CU1 { 2 }, cc.CU1 { 3 }, cc.CU1 { 4 },
		cc.CU1 { 5 }, cc.CU1 { 6 }, cc.CU1 { 7 })
end
test.eq(c27(), sumsq(7))

terra c28()
	return cc.int_spill_i24(
		cc.CU3 { 1, 2, 3 }, cc.CU3 { 4, 5, 6 }, cc.CU3 { 7, 8, 9 },
		cc.CU3 { 10, 11, 12 }, cc.CU3 { 13, 14, 15 }, cc.CU3 { 16, 17, 18 },
		cc.CU3 { 19, 20, 21 })
end
test.eq(c28(), sumsq(21))

terra c29()
	return cc.int_spill_mixed(
		cc.CIF { 1, 2 }, cc.CIF { 3, 4 }, cc.CIF { 5, 6 }, cc.CIF { 7, 8 },
		cc.CIF { 9, 10 }, cc.CIF { 11, 12 }, cc.CIF { 13, 14 })
end
test.eq(c29(), sumsq(14))

terra c30()
	return cc.both_spill(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
		cc.CF2 { 15, 16 }, cc.CF2 { 17, 18 })
end
test.eq(c30(), sumsq(18))

terra c31()
	var r = cc.sret_and_int_spill(1, 2, 3, 4, 5, 6, cc.CD2 { 7, 8 })
	return double(r.a + r.b + r.c + r.d)
end
-- The callee returns t, 2t, 3t and 4t, so the four fields sum to 10t.
test.eq(c31(), 10 * sumsq(8))

terra c32()
	return cc.spill_then_reg(1, 2, 3, 4, 5, 6, 7, 8,
		cc.CF2 { 9, 10 }, cc.CF2 { 11, 12 }, 13)
end
test.eq(c32(), sumsq(13))

terra f33(x1 : cc.CF2, x2 : cc.CF2, x3 : cc.CF2, x4 : cc.CF2, x5 : cc.CF2,
          x6 : cc.CF2, x7 : cc.CF2, x8 : cc.CF2, x9 : cc.CF2, x10 : cc.CF2) : double
	return 1*x1.a + 2*x1.b + 3*x2.a + 4*x2.b + 5*x3.a + 6*x3.b
	     + 7*x4.a + 8*x4.b + 9*x5.a + 10*x5.b + 11*x6.a + 12*x6.b
	     + 13*x7.a + 14*x7.b + 15*x8.a + 16*x8.b + 17*x9.a + 18*x9.b
	     + 19*x10.a + 20*x10.b
end
f33:setinlined(false)

terra c33()
	return cc.call_sse_spill(f33)
end
test.eq(c33(), sumsq(20))

terra f34(x1 : cc.CI1, x2 : cc.CI1, x3 : cc.CI1, x4 : cc.CI1, x5 : cc.CI1,
          x6 : cc.CI1, x7 : cc.CI1) : double
	return 1*x1.a + 2*x2.a + 3*x3.a + 4*x4.a + 5*x5.a + 6*x6.a + 7*x7.a
end
f34:setinlined(false)

terra c34()
	return cc.call_int_spill(f34)
end
test.eq(c34(), sumsq(7))