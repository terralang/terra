if not require("fail") then return end

terra foo()
    var a  = [ int[2] ]({0, a = 3}).a
end
foo()
