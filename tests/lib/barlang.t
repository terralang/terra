return {
	keywords = {"foo"};
	entrypoints = {"bar"};
	expression = function(self,lex) 
		lex:expect("bar")
		lex:expect("foo")
		return function() return 2 end
	end
}