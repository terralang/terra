local bar = {}

struct what{}

terra foo() : &what
   [bar]
   return nil
end
