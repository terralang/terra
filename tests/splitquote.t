local _,err = terralib.loadstring("moo\nquote\nend")
assert(err:match("unexpected symbol near 'quote'"))