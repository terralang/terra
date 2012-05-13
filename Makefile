.SUFFIXES:
UNAME := $(shell uname)

CXX = /usr/local/bin/clang++
CC = /usr/local/bin/clang
FLAGS = -g
LFLAGS = -g 

SRC = lstring.cpp main.cpp lobject.cpp lzio.cpp llex.cpp lctype.cpp
OBJS = $(SRC:.cpp=.o)
EXECUTABLE = lexer


.PHONY:	all clean
all:	$(EXECUTABLE)

build/%.o:	src/%.cpp
	$(CXX) $(FLAGS) $< -c -o $@

$(EXECUTABLE):	$(addprefix build/, $(OBJS))
	$(CXX) $^ -o $@ $(LFLAGS)
	
clean:
	rm -rf build/*.o build/*.d
	rm -rf $(EXECUTABLE)

# dependency rules
DEPENDENCIES = $(patsubst %.o,build/%.d,$(OBJS))
build/%.d:	src/%.cpp
	@$(CXX) $(FLAGS) -MM -MT '$@ $(@:.d=.o)' $< -o $@
	
-include $(DEPENDENCIES)
