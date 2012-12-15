all:	../README.html ../embeddinglanguages.html
../%.html:	../%.md style.html Markdown.pl
	perl Markdown.pl $< | cat style.html - > $@
