require "terralibext"  --load 'terralibext' to enable raii

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local test = require "test"

local utils = require("lib.utils")
local lib = require("lib.raii-integration")


local copyable = false
local Stack = lib.DynamicStack(double, copyable)
local Vector = lib.DynamicVector(double, copyable)
local VectorPair = lib.VectorPair(double, copyable)

--Representative example:
--(1) We create a dynamic stack and start adding elements. The Stack
--will reallocate data when needed.
--(2) We transfer the dynamic stack into a dynamic vector. A dynamic vector
--has a fixed dynamic size and can not grow.
--(3) We use the dynamic vector in an aggregate data type that is used to double
--some more operations.
terra main()
    --fill the first stack
    var stack_x : Stack
    stack_x:push(1.0)
    stack_x:push(2.0)
    stack_x:push(3.0)
    stack_x:push(4.0)
    stack_x:push(5.0)

    --transfer to a vector (stack_x will become empty)
    var x : Vector = stack_x

    --check that stack_x is empty
    utils.assert(stack_x.data == nil and stack_x.size == 0 and stack_x.capacity == 0)

    --fill the second stack
    var stack_w : Stack
    stack_w:push(0.5)
    stack_w:push(1.0)
    stack_w:push(1.0)
    stack_w:push(1.0)
    stack_w:push(0.5)

    --transfer to a vector (stack_x will become empty)
    var w : Vector = stack_w
    --check that stack_w is empty
    utils.assert(stack_w.data == nil and stack_w.size == 0 and stack_w.capacity == 0)

    --store (x,w) in an aggregate datatype
    var q = VectorPair.new(x, w)
    --check that `x` and `w` are now empty
    utils.assert(x.data == nil and x.size == 0)
    utils.assert(w.data == nil and w.size == 0)

    for i=0,5 do
        var x, y = q(i)
        utils.printf("  q(%d) = (%0.1f, %0.1f)\n", i, x, y)
    end 

    return q:size()
end
test.eq(main(), 5)
