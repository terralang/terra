
terra bar()
end

bar:compile()
local what = bar.variants[1].fptr

terra foo()
   var a  = what
end
foo()