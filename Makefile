.SUFFIXES:
UNAME := $(shell uname)


LUAJIT_VERSION=LuaJIT-2.0.0-beta10
LUAJIT_URL=http://luajit.org/download/$(LUAJIT_VERSION).tar.gz
LUAJIT_TAR=$(LUAJIT_VERSION).tar.gz
LUAJIT_DIR=build/$(LUAJIT_VERSION)
LUAJIT_LIB=build/$(LUAJIT_VERSION)/src/libluajit.a

LIBS += -lluajit
LIB_PATH += -Lbuild
INCLUDE_PATH += -I$(LUAJIT_DIR)/src



CXX = /usr/local/bin/clang++
CC = /usr/local/bin/clang
FLAGS = -g $(INCLUDE_PATH)
LFLAGS = -g $(LIB_PATH) $(LIBS) 


SRC = lparser.cpp lstring.cpp main.cpp lobject.cpp lzio.cpp llex.cpp lctype.cpp
OBJS = $(SRC:.cpp=.o)
EXECUTABLE = lexer


.PHONY:	all clean
all:	$(EXECUTABLE)

build/%.o:	src/%.cpp
	$(CXX) $(FLAGS) $< -c -o $@

build/$(LUAJIT_TAR):
ifeq ($(UNAME), Darwin)
	curl $(LUAJIT_URL) -o build/$(LUAJIT_TAR)
else
	wget $(LUAJIT_URL) -O build/$(LUAJIT_TAR)
endif

$(LUAJIT_LIB): build/$(LUAJIT_TAR)
	(cd build; tar -xf $(LUAJIT_TAR))
	(cd $(LUAJIT_DIR); make)
	cp $(LUAJIT_DIR)/src/libluajit.a build/libluajit.a
	
$(EXECUTABLE):	$(addprefix build/, $(OBJS)) $(LUAJIT_LIB)
	$(CXX) $^ -o $@ $(LFLAGS)
	
clean:
	rm -rf build/*.o build/*.d
	rm -rf $(EXECUTABLE)

purge:	clean
	rm -rf build/*
	
# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp
	@$(CXX) $(FLAGS) -MM -MT '$@ $(@:.d=.o)' $< -o $@
	
-include $(DEPENDENCIES)
