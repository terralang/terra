local c = terralib.includecstring([[
#include <stdio.h>
#include <stdlib.h>
]])

struct anon100 {
  a : int[50000],
}

terra assert_(x : bool)
  if not x then
    c.printf("assertion failed\n")
  end
end

terra unpack_param(buffer : &opaque,
                   buffer_size : uint64) : int32[50000]
  var data_ptr1 : &uint8 = [&uint8](buffer) + [terralib.sizeof(int32[50000])]
  var result : int32[50000] = @[&int32[50000]](buffer)
  assert_(buffer_size == [uint64](data_ptr1 - [&uint8](buffer)))
  return result
end

unpack_param:setinlined(false)
print("about to compile unpack_param")
start_t = os.time()
-- unpack_param:compile()
terralib.saveobj("unpack_param.o", "object", {unpack_param=unpack_param}, {})
stop_t = os.time()
print("finished compile unpack_param in " .. tostring(stop_t - start_t) .. " seconds")
