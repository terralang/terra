print ("loaded terra lib")
terra = {}
function printTable(t)
    function printTableHelper(t, spacing)
        for k,v in pairs(t) do
            print(spacing..tostring(k), v)
            if (type(v) == "table") then 
                printTableHelper(v, spacing.."\t")
            end
        end
    end

    printTableHelper(t, "");
end
function terra.newfunction(x)
	print ("function:")
	printTable(x)
end