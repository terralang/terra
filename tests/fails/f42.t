local a = quote
    while true do end
end
terra foo()
  return  a
end
foo()