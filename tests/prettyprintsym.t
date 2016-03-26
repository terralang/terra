local myStruct = terralib.types.newstruct('myStruct')
local someFlagFld = label('someFlag')
table.insert(myStruct.entries, {field=someFlagFld,type=bool})
myStruct : printpretty()
