
A = struct { a : &A }

terra foo()
    var a : A    
end
foo()