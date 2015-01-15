CLANG_PREFIX=/usr
CXX = $(CLANG_PREFIX)/bin/clang++
CC = $(CLANG_PREFIX)/bin/clang

#FLAGS = -O3
FLAGS = -g -O3 -I/usr/local/atlasgccavx/include
#FLAGS = -O3 -I/opt/intel/composer_xe_2013.0.088/mkl/include
#LIBS = -framework Accelerate
#LIBS = -L/usr/local/atlasgccavx/lib -latlas -lcblas
LIBS = -L/usr/local/atlasgccavx/lib -latlas -lcblas

#LIBS = -L/opt/intel/composer_xe_2013.0.088/mkl/lib -lmkl_intel_lp64 -lmkl_core -lmkl_sequential -lm

matmul:	matmul.cpp ../dgemm3.t
	../../terra -m ../gemm.t
	$(CXX) $(FLAGS) $(LIBS) -o matmul matmul.cpp my_dgemm.o

matmuls:	matmuls.cpp ../sgemm3.t
	../../terra -v -m ../sgemm3.t
	$(CXX) $(FLAGS) $(LIBS) -o matmuls matmuls.cpp sgemm_ispc.o my_sgemm.o


%:	%.cpp
	$(CXX) $(FLAGS) $(LIBS) -o $@ $<

%:	%.c
	$(CC) $(FLAGS) $(LIBS) -o $@ $<