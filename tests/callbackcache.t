
printtwo = terralib.cast({int,int} -> {},print)
printone = terralib.cast({int} -> {},print) 
for i = 1,10 do
	local terra doprint()
		printtwo(1,2)
		printone(3)
	end
	doprint()
end