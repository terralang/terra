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

PACKAGE_DEPS += $(LUAJIT_LIB)

CXX = /usr/local/bin/clang++
CC = /usr/local/bin/clang
FLAGS = -g $(INCLUDE_PATH)
LFLAGS = -g $(LIB_PATH) $(LIBS) 

#makes luajit happy on osx 10.6 (otherwise luaL_newstate returns NULL)
LFLAGS += -pagezero_size 10000 -image_base 100000000 

SRC = terra.cpp lparser.cpp lstring.cpp main.cpp lobject.cpp lzio.cpp llex.cpp lctype.cpp
OBJS = $(SRC:.cpp=.o)
EXECUTABLE = lexer

BIN2C = build/bin2c

.PHONY:	all clean
all:	$(EXECUTABLE)

build/%.o:	src/%.cpp $(PACKAGE_DEPS)
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

	
$(EXECUTABLE):	$(addprefix build/, $(OBJS))
	$(CXX) $^ -o $@ $(LFLAGS)

$(BIN2C):	src/bin2c.c
	$(CC) -O3 -o $@ $<
	
clean:
	rm -rf build/*.o build/*.d
	rm -rf $(EXECUTABLE)

purge:	clean
	rm -rf build/*
	
# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp
	@g++ $(FLAGS)  -MG -MM -MT '$@ $(@:.d=.o)' $< -o $@
	
-include $(DEPENDENCIES)
