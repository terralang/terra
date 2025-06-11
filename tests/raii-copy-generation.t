require "terralibext"  --load 'terralibext' to enable raii

local test = require("test")

local function printtestheader(s)
    print()
    print("===========================")
    print(s)
    print("===========================")
end

local struct A {
    data : int
}

printtestheader("raii-copy-generation.t - testing __copy generation - 1")

terralib.ext.addmissing.__copy(A)
assert(A.methods.__copy == nil)     -- a __copy method could not be generated
assert(A.__copy_generated == true)  -- a trait that signals that `terralib.ext.addmissing.__copy`n has been called

terra A.methods.__copy(from : &A, to : &A)
    to.data = from.data + 1
end


printtestheader("raii-copy-generation.t - testing __copy generation - 2")

local sum = {double,double} -> double

local struct B{
    a : A                   -- implements __copy
    i : int                 -- is trivially copyable
    v : vector(double, 3)   -- is trivially copyable
    f : sum                 -- is trivially copyable
    x : int[3]              -- is trivially copyable
    y : A[2]                -- elements implement __copy
}

terralib.ext.addmissing.__copy(B)
assert(B.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(B.methods.__copy ~= nil)     -- a __copy method was generated

printtestheader("raii-copy-generation.t - testing __copy generation - 3")

local struct C{
    a : A       -- implements __copy
    b : B       -- implements generated __copy
    c : B[2]    -- elements implement __copy
}

terralib.ext.addmissing.__copy(C)
assert(C.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(C.methods.__copy ~= nil)     -- a __copy method was generated

printtestheader("raii-copy-generation.t - testing __copy generation - 4")

local struct dummy{
    x : int
}

local struct D{
    d : dummy --copyable, but unmanaged. so __copy unnecessary
}

terralib.ext.addmissing.__copy(D)
assert(D.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(D.methods.__copy == nil)     -- but not __copy was generated

printtestheader("raii-copy-generation.t - testing __copy generation - 5")

terra dummy:__dtor() -- now dummy is managed, but not copyable
    self.x = -1
end

terralib.ext.addmissing.__copy(dummy)
assert(dummy.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(dummy.methods.__copy == nil)     -- but __copy could not be generated

local struct E{
    d : dummy  --not copyable
}

terralib.ext.addmissing.__copy(E)
assert(E.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(E.methods.__copy == nil)     -- but __copy could not be generated

printtestheader("raii-copy-generation.t - testing __copy generation - 6")

local struct F{
    a : A     --copyable
    b : dummy --not copyable
}

terralib.ext.addmissing.__copy(F)
assert(F.__copy_generated == true)  -- terralib.ext.addmissing.__copy has been called
assert(F.methods.__copy == nil)     -- but __copy could not be generated

printtestheader("raii-copy-generation.t - testing __copy generation - 7")

local struct G{
    a : A     --copyable
    p : &int  --not copyable
}

terralib.ext.addmissing.__copy(G)
assert(G.__copy_generated == true)
assert(G.methods.__copy == nil)


printtestheader("raii-copy-generation.t - testing __copy generation - 8")

local struct newdummy{
    ptr : &int  --not copyable
}

local struct H{
    a : A     --copyable
    p : newdummy  --not copyable
}

terralib.ext.addmissing.__copy(H)
assert(H.__copy_generated == true)
assert(H.methods.__copy == nil)
