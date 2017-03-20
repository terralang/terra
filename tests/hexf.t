

assert(0xf == 15)

terra foo()
	return 0xf
end

assert(foo() == 15)

terra u32() : uint32
	return 0xffffffff
end

assert(u32() == math.pow(2, 32) - 1)

terra u64() : uin64
	return 0xfffffffffffffffff
end

assert(u64() == math.pow(2, 64) - 1)
