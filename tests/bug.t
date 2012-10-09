local OC = terralib.require("lib/objc")
local OCR = terralib.includec("objc/runtime.h")

terra main()
	var nsobject = OC.NSObject
	OCR.objc_allocateClassPair(nsobject:as(&OCR.objc_class),nil,0)
end

main:compile()