return {
	keywords = {"bar"};
	entrypoints = {"foo"};
	expression = function(self,lex) 
		lex:expect("foo")
		lex:expect("bar")
		return function() return 1 end
	end
}