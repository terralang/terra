

terra foobar(a : &vector(float,4),b : vector(int,4))
        var x = terralib.attrload(a,{ nontemporal = true })
	terralib.attrstore(a,b+x,{ nontemporal = true })
end

function wrap(attrs)
    local fn = terra (a : &vector(float,4),b : vector(int,4))
        var x = terralib.attrload(a,attrs)
	terralib.attrstore(a,b+x,attrs)
    end
    return fn
end

foobar:disas()
wrap({ nontemporal = true }):disas()
wrap({ nontemporal = false }):disas()
