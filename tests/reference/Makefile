CLANG_PREFIX=/usr/local
CXX = $(CLANG_PREFIX)/bin/clang++
CC = $(CLANG_PREFIX)/bin/clang

#FLAGS = -O3
FLAGS = -O3 -I/usr/local/atlasgccavx/include
#FLAGS = -O3 -I/opt/intel/composer_xe_2013.0.088/mkl/include
#LIBS = -framework Accelerate
LIBS = -L/usr/local/atlasgccavx/lib -latlas -lcblas

#LIBS = -L/opt/intel/composer_xe_2013.0.088/mkl/lib -lmkl_intel_lp64 -lmkl_core -lmkl_sequential -lm

matmul:	matmul.cpp ../dgemm.t
	../../terra ../dgemm2.t
	$(CXX) $(FLAGS) $(LIBS) -o matmul matmul.cpp my_dgemm.o

matmuls:	matmuls.cpp ../sgemmkernel.t
	../../terra -v ../sgemmkernel.t
	$(CXX) $(FLAGS) $(LIBS) -o matmuls matmuls.cpp sgemm_ispc.o my_sgemmkernel.o


%:	%.cpp
	$(CXX) $(FLAGS) $(LIBS) -o $@ $<

%:	%.c
	$(CC) $(FLAGS) $(LIBS) -o $@ $<