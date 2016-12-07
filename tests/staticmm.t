struct S {}

function S:__getmethod(name)
   return terra()
      terralib.printf("%s\n",name)
   end
end

terra f()
   S.hi()
   S.bar()
end

f()
