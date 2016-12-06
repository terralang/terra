struct A {}
A.__typename = function() return "" end
struct B {}
B
.__typename = function() return "" end
print(A:cstring(),B:cstring())
