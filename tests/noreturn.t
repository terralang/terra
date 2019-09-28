exit = terralib.externfunction("exit", {int} -> {})
exit:setnoreturn(true)

terra foo() : {}
    exit(0)
end

foo:compile()
foo:disas()
