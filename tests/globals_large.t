-- In Clang (as of LLVM 7), certain large arrays get encoded as structs,
-- particularly when they contain trailing zeros. If Terra does not emit the
-- correct code, this results in a crash.
--
-- See: https://github.com/terralang/terra/issues/630

local c = terralib.includec("stdlib.h")

local gamma_header_big = terralib.includecstring([[
const double gamma_table[3][50] = {
        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,

        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 1.33, 1.33, 1.33, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,

        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33,
        1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 1.33, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,
        0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00, 0.00,

};
]])

print(gamma_header_big.gamma_table)

terra getGammaTableArrayBig(j : int, index : int) : double
  var gval: double
  gval = gamma_header_big.gamma_table[j][index]
  return gval
end
getGammaTableArrayBig:setinlined(false)
-- getGammaTableArrayBig:setoptimized(false)
-- getGammaTableArrayBig:disas()

terra g3d(r_gamma_table : &double, N : int, M : int)
  for x = 0, N do
    for y = 0, M do
      r_gamma_table[x * M + y] =  getGammaTableArrayBig(x, y)
    end
  end
end

terra main()
  var N = 3
  var M = 50
  var r_gamma_table_big = [&double](c.malloc(N*M*terralib.sizeof(double)))
  g3d(r_gamma_table_big, N, M)
end

main()
