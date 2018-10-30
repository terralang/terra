local ffi = require 'ffi'
if ffi.os == "Windows" then
    os.exit()
end

-- Test that terralib.linklibrary doesn't reject a library that just happens to end in bc

C = terralib.includec("stdio.h")

terra f()
    C.printf("it works!\n")
end

terralib.saveobj("./not_bc", "sharedlibrary", {g = f}) -- Not actually a .bc file!
terralib.linklibrary("./not_bc")
L = terralib.includecstring [[
  void g(void);
]]

L.g()
