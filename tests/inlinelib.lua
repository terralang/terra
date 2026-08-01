-- Helpers for the JIT inliner tests (inline_jit_*.t).
--
-- Terra's JIT compiles one strongly connected component of the call graph at a
-- time, and inlines into an SCC as that SCC completes (ManualInliner, see
-- src/tinline.cpp). Because that path is separate from the module-at-a-time
-- pipeline used by saveobj, it can regress on its own -- it did, silently, from
-- LLVM 17 until the manual inliner was ported to the new pass manager. These
-- helpers let a test detect that automatically instead of eyeballing a
-- disassembly.
--
-- Two deliberate choices keep the checks portable:
--
--   * they read textual LLVM IR, not machine code, so they do not depend on the
--     target architecture; and
--   * they match on callee symbol names, not on instruction counts or opcodes,
--     so they do not depend on the LLVM version's choice of instructions,
--     attributes, or output formatting.
--
-- Callees are named by passing the Terra function object itself, so a test can
-- never drift out of sync with the symbol it is really asserting on.

local M = {}

local function jitir()
    -- Keep optimizations disabled so that we don't accidentally run the module-level inliner.
    return assert(terralib.jitcompilationunit:saveobj(nil, "llvmir", {}, false --[[ optimize ]]),
                  "no LLVM IR returned for the JIT compilation unit")
end

local function nameof(fn)
    if type(fn) == "string" then return fn end
    return assert(fn.name, "expected a Terra function or a symbol name")
end

local function escape(s) return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

-- Terra emits its own functions as @"$name", doubling the $ for a few names
-- that would otherwise collide with ELF's ARM ABI (TerraSymbolPrefix in
-- src/tcompiler.cpp). Functions imported from C keep their own name unprefixed.
local function candidates(fn)
    local n = nameof(fn)
    return { "$" .. n, "$$" .. n, n }
end

-- True if body still mentions the callee's symbol, i.e. it was not inlined.
local function refers(body, fn)
    for _, sym in ipairs(candidates(fn)) do
        if body:find('@"' .. sym .. '"', 1, true) then return true end
        -- Unquoted form: check the match is the whole symbol and not a prefix
        -- of a longer one.
        local i = 1
        while true do
            local s, e = body:find("@" .. sym, i, true)
            if not s then break end
            if not body:sub(e + 1, e + 1):match("[%w_%.%$]") then return true end
            i = e + 1
        end
    end
    return false
end

-- Compile fn and return the text of its LLVM definition from the JIT module.
function M.body(fn)
    fn:compile()
    local ir = jitir()
    for _, sym in ipairs(candidates(fn)) do
        local body = ir:match('\ndefine[^\n]-@"' .. escape(sym) .. '"%(.-\n}')
                  or ir:match('\ndefine[^\n]-@' .. escape(sym) .. '%(.-\n}')
        if body then return body end
    end
    error("no LLVM definition for '" .. nameof(fn) .. "' in the JIT module", 2)
end

local function describe(callees)
    local names = {}
    for i, c in ipairs(callees) do names[i] = nameof(c) end
    return table.concat(names, " ")
end

local function report(case, verdict, callees)
    print(string.format("  %-44s %s %s", case, verdict, describe(callees)))
end

local function fail(case, body, msg)
    error(string.format("%s: %s\n--- LLVM IR ---\n%s\n---------------", case, msg, body),
          3)
end

-- Assert every callee was inlined into body, i.e. body no longer refers to it.
function M.assertinlined(case, body, callees)
    for _, callee in ipairs(callees) do
        if refers(body, callee) then
            fail(case, body, "expected '" .. nameof(callee) .. "' to be inlined, but "
                             .. "the caller still refers to it")
        end
    end
    report(case, "inlined ", callees)
end

-- Assert every callee is still called, i.e. inlining was correctly suppressed.
-- These are the controls for this family of tests: they keep passing when the
-- inliner is broken, so if they pass while the positive checks fail, inlining
-- really is off rather than the detection being wrong.
function M.assertnotinlined(case, body, callees)
    for _, callee in ipairs(callees) do
        if not refers(body, callee) then
            fail(case, body, "expected '" .. nameof(callee) .. "' NOT to be inlined, "
                             .. "but the caller no longer refers to it")
        end
    end
    report(case, "kept    ", callees)
end

return M
