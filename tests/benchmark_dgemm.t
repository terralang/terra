local ffi = require("ffi")
if ffi.os == "Windows" then
    print("not supported on windows")
    return
end
C = terralib.includecstring [[
#include<stdio.h>
#include<assert.h>
#include<stdlib.h>
#include <unistd.h>
#include <sys/time.h>
#include <math.h>
void asserteq(double * A, double * B, int M, int N) {
    int i = 0;
    for(int m = 0; m < M; m++) {
        for(int n = 0; n < N; n++) {
            if(A[i] != B[i]) {
                goto printerr;
            }
            i++;
        }
    }
    return;
printerr:
    i = 0;
    for(int m = 0; m < M; m++) {
        for(int n = 0; n < N; n++) {
            if(A[i] != B[i]) {
                putchar('X');
            } else {
                putchar('*');
            }
            i++;
        }
        printf("\n");
    }
    assert(0);
}
void naive_dgemm(const int M, const int N,
                     const int K, const double alpha, const double *A,
                     const int lda, const double *B, const int ldb,
                     const double beta, double *C, const int ldc) {
       
        assert(alpha == 1.f);
        assert(beta == 0.f);

        for(int m = 0; m < M; m++) {
            for(int n = 0; n < N; n++) {
                double v = 0.f;
                for(int k = 0; k < K; k++) {
                    v += A[m*lda + k] * B[k*ldb + n]; 
                }
                C[m*ldc + n] = v;
            }
        }
    }
static double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

int CalcTime(int * times, double * start) {
	if(*times == 0) {
		*start = CurrentTimeInSeconds();
	} else {
		double elapsed = CurrentTimeInSeconds() - *start;
		if(*times == 1) {
			*start = elapsed / *times;
			return 0;
		}
	}
	(*times)++;
	return 1;
}

typedef void (*my_dgemm_t)(int, int,
                 int , double,  double *,
                 int, double *, int,
                 double , double *,  int);
                 
                 
//calculates C = alpha * AB + beta * C 
void testsize(int M, int K, int N, my_dgemm_t my_dgemm) {

	double * A = (double*) malloc(sizeof(double) * M * K);
	double * B = (double*) malloc(sizeof(double) * K * N);
	double * C = (double*) malloc(sizeof(double) * M * N);
	double * C2 = (double*) malloc(sizeof(double) * M * N);
	double * C3 = (double*) malloc(sizeof(double) * M * N);


	for(int m = 0; m < M; m++) {
		for(int k = 0; k < K; k++) {
			A[m*K + k] = rand() % 10;
		}
	}
	int i = 0;
	for(int k = 0; k < K; k++) {
		for(int n = 0; n < N; n++) {
			B[k*N + n] = rand() % 10;
		}
	}

	for(int i = 0; i < M *N; i++) 
		C[i] = C2[i] = C3[i] = -1.f;

	int times = 0;
	double blastime = 0;
	//while(CalcTime(&times,&blastime))
	//    naive_dgemm(M,N,K,1.f,A,K,B,N,0.f,C,N);

	double mytime;
	times = 0;
	while(CalcTime(&times,&mytime))
		my_dgemm(M,N,K,1.f,A,K,B,N,0.f,C3,N);
	
	//asserteq(C,C3,M,N);

	free(C);
	free(C2);
	free(C3);
	free(A);
	free(B);
	double logblastime = log(M) + log(N) + log(K) + log(2) + log(1e-9) - log(blastime);
	double logmytime = log(M) + log(N) + log(K) + log(2) + log(1e-9) - log(mytime);
	printf("%d %d %d %f %f %f\n",M,K,N,exp(logblastime),exp(logmytime), mytime/ blastime);
}
int run(my_dgemm_t my_dgemm, int e) {
	int NB = 40;
	for(int i = NB; 1; i += 3*NB) {
		int m = i;
		int n = i;
		int k = i;
		testsize(m,n,k,my_dgemm);
		if(m*n+ m*k+n*k > e)
			break;
	}
	return 0;
}
]]

local my_dgemm = assert(terralib.loadfile("gemm.t"))()
local limit = tonumber((...) or 2048*2048/2)
C.run(my_dgemm:getpointer(),limit)

