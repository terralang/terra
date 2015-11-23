local nan = tonumber("NaN")

terra isnanf (x : float) : bool
    return x ~= x
end

terra isnan (x : double) : bool
    return x ~= x
end

-- pass
assert(isnan(1.5) == false)
-- pass
assert(isnanf(1.5) == false)
-- fail
assert(isnan(nan) == true)
-- fail
assert(isnanf(nan) == true)