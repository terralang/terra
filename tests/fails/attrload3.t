if not require("fail") then return end


terra f(x : &int)
  terralib.attrload(x, {align = "asdf"})
end
f:compile()
