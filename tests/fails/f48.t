require("fail")

terra foo()
  if true then
    return 1,3
  else
    return 1,2,3
  end
end
foo()
