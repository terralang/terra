local C = terralib.includecstring [[
extern int printf (const char *__restrict __format, ...);
void testC() {
        printf("C\n");
}
void testC2() {
        printf("C\n");
}
]]
local terra testTerra()
        C.printf("Terra\n")
end
testTerra()
C.testC()
C.testC2()
terralib.dumpmodule(terralib.jitcompilationunit.llvm_cu)