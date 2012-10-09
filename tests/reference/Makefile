CLANG_PREFIX=/usr/local
CXX = $(CLANG_PREFIX)/bin/clang++
CC = $(CLANG_PREFIX)/bin/clang

FLAGS = -O3

LIBS = -framework Accelerate

matmul:	matmul.cpp ../sgemm.t
	../../terra ../sgemm.t
	$(CXX) $(FLAGS) $(LIBS) -o matmul matmul.cpp my_sgemm.o

%:	%.cpp
	$(CXX) $(FLAGS) $(LIBS) -o $@ $<

%:	%.c
	$(CC) $(FLAGS) $(LIBS) -o $@ $<