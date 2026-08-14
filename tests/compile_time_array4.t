-- Copying a large array has to stay a memcpy even when the copy cannot read
-- straight from the original address, which is the case for a parallel
-- assignment: the second copy reads a snapshot instead. Falling back to a plain
-- load and store of the array itself would let SROA expand it into one
-- instruction per element -- 600000 of them for the two arrays here -- after
-- which the rest of the pipeline never finishes.
-- https://github.com/terralang/terra/issues/709 is the same hazard for a load
-- with no store; parallelassign.t is what the snapshot is for.

local N = 50000

terra swap_arrays(p : &int32[N], q : &int32[N])
  @p, @q = @q, @p
end

swap_arrays:setinlined(false)
print("about to compile swap_arrays")
start_t = os.time()
swap_arrays:compile()
stop_t = os.time()
print("finished compile swap_arrays in " .. tostring(stop_t - start_t) .. " seconds")

terra check() : {int32, int32, int32, int32}
  var a : int32[N]
  var b : int32[N]
  a[0], b[0] = 1, 10
  a[N - 1], b[N - 1] = 2, 20
  swap_arrays(&a, &b)
  return a[0], a[N - 1], b[0], b[N - 1]
end
local r = check()
assert(r._0 == 10 and r._1 == 20 and r._2 == 1 and r._3 == 2)
