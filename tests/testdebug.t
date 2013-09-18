if not terralib.traceback then return end
--this test require debug on, if it is not on, relaunch with it on
if 0 == terralib.isdebug then
  assert(0 == os.execute("../terra -g testdebug.t"))
  return
end
C = terralib.includec("stdio.h")
print(terralib.verbose)
terra foo(a : int, b : int)
  var c = a + b
  return c * 2
end

local ptr = terralib.cast(rawstring,foo:getdefinitions()[1]:getpointer())

terra findptr(a : &opaque)
  var addr : &opaque
  var sz : uint64
  var nm : int8[128]
  terralib.lookupsymbol(a,&addr,&sz,nm,128)
  C.printf("p = %p, addr = %p, sz = %d, nm = %s\n",a,addr,[int](sz), nm)
  terralib.lookupline(addr,a, nm, 128, &sz)
  C.printf("line = %s:%d\n",nm,[int](sz))
  return sz 
end
--foo:disas()
assert(11 == findptr(ptr+6))
assert(10 == findptr(ptr+4))
local ra = terralib.intrinsic("llvm.returnaddress", int32 -> &opaque )
local fa = terralib.intrinsic("llvm.frameaddress", int32 -> &opaque )
terra testbt()
  var frames : (&opaque)[128]
  var N = terralib.backtrace(frames,128,ra(0),fa(1))
  for i = 0,N do
    C.printf("%p\n",frames[i])
    var nm : int8[128]
    if terralib.lookupsymbol(frames[i],nil,nil,nm,128) then
      C.printf("%s\n", nm)
    end
  end
end
terra fn2()
  testbt()
  return 1
end
fn2()