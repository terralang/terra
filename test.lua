b = terra(a : int,b : int) : int,int
 if a then 
 elseif b then 
 else 
 end
 while a do if b then end end
 repeat until b
 ::alabel::
 goto alabel
 break
 a.b
 if a then goto alabel end
 a[b]
 afunction:aname "astring"
 afunction:aname()
 afunction(a)
 a.b.c[b](c+d*e or a)
 a = true,false,nil
 a = { [a] = 4, a = 4, 3 }
 a,b,c,d,e = b,c,4,"astring"
 a = &b
 for i = 1,2 do end
 for i = 1,2,3 do end
 for i,b,c in a,b,c do end
 return #a.b.c.d[f]:e()
end
terra c(some : int,args : int)
	var a = 1
	return 4
end
a = {}
terra a.b(a : int)
	print("me")
end 
terra a.b(c : int)
end
function b() 
	local terra foo(a : int,b : {int,int}) end
end
b()
a = b
terra foo(c : int) : int
	var a : int, b = 4,5
end
print("and done")
