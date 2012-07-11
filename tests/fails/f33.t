
terra bar()
end

bar:compile()
local what = bar.fptr

terra foo()
   var a  = what
end
foo()