local myStruct = terralib.types.newstruct('myStruct')
local someFlagFld = symbol(bool, 'someFlag')
table.insert(myStruct.entries, {field=someFlagFld,type=someFlagFld.type})
myStruct : printpretty()
