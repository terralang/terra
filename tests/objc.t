
local OC = terralib.require("lib/objc")

terra main()
	OC.NSAutoreleasePool:new()
	var str = OC.NSString:stringWithUTF8String("the number of hacks is overwhelming...")
	var err = OC.NSError:errorWithDomain_code_userInfo(str,12,nil)
	var alert = OC.NSAlert:alertWithError(err)

	var imgname = OC.NSString:stringWithUTF8String("foo.png")
	var img = OC.NSImage:alloc():initByReferencingFile(imgname)
	alert:setIcon(img)
	alert:runModal()
end

terralib.saveobj("objc",{main = main}, { "-framework", "Foundation", "-framework", "Cocoa" })