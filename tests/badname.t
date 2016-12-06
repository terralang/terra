--tostring on a type should never error, so we assign it its original name if it does
struct A {}
A.__typename = error
print(A)
