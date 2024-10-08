local vec = vector(int8, 64)
terra compute(x: vec, y: vec)
    -- vec has a size of 8 * 64 = 512 bits so this operation should compile
    -- to a single AVX512 instruction
    return x + y
end
compute:compile()
compute:disas()
