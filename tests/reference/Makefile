CLANG_PREFIX=/usr/local
CXX = $(CLANG_PREFIX)/bin/clang++
CC = $(CLANG_PREFIX)/bin/clang

FLAGS = -O3

LIBS = -framework Accelerate

matmul:	matmul.cpp ../dgemm.t
	../../terra ../dgemm.t
	$(CXX) $(FLAGS) $(LIBS) -o matmul matmul.cpp my_dgemm.o

%:	%.cpp
	$(CXX) $(FLAGS) $(LIBS) -o $@ $<

%:	%.c
	$(CC) $(FLAGS) $(LIBS) -o $@ $<