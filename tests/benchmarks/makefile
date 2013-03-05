
INCLUDES += -I/Users/research/Documents/eigen
INCLUDES += -I/Users/zdevito/Downloads/eigen-eigen-5097c01bcdc4
default: bs_eigen raysphere_eigen

clean:
	rm bs_eigen

all: bs_eigen raysphere_eigen

bs_eigen: bs_eigen.cpp
	clang++ -O3 $(INCLUDES) bs_eigen.cpp -o bs_eigen

raysphere_eigen: raysphere_eigen.cpp
	clang++ -O3 $(INCLUDES) raysphere_eigen.cpp -o raysphere_eigen