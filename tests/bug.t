local f = assert(io.popen("uname", 'r'))
local s = assert(f:read('*a'))
f:close()

if s~="Darwin\n" then
  print("Warning, not running test b/c this isn't a mac")
else


local OC = terralib.require("lib/objc")
local OCR = terralib.includec("objc/runtime.h")

terra main()
	var nsobject = OC.NSObject
	OCR.objc_allocateClassPair(nsobject:as(&OCR.objc_class),nil,0)
end

main:compile()

end