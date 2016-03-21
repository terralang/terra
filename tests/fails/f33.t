if not require("fail") then return end

terra bar()
end

bar:compile()
local what = bar.rawjitptr

terra foo()
   var a  = what
end
foo()
