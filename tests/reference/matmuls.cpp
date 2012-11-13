//#include<Accelerate/Accelerate.h>
extern "C" {
#include "cblas.h"
}
//#include "mkl_cblas.h"
#include <math.h>
#include<stdio.h>
#include<assert.h>
#include<sys/time.h>
/*
void cblas_dgemm(const enum CBLAS_ORDER Order, const enum CBLAS_TRANSPOSE TransA,
                 const enum CBLAS_TRANSPOSE TransB, const int M, const int N,
                 const int K, const float alpha, const float *A,
                 const int lda, const float *B, const int ldb,
                 const float beta, float *C, const int ldc)
*/
// A is a matrix of dim M x K
// B is a matrix of dim K x N
// C is a matrix of dim M x N
// lda is the stride of matrix A (normally its K, but it can be larger for alignment)
// ldb is the stride of matrix B (normally its N, ...)
// ldc is the stride of the output matrix (normally it is N, ...)



void asserteq(float * A, float * B, int M, int N) {
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
	assert(false);
}



void naive_dgemm( const int M, const int N,
                 const int K, const float alpha, const float *A,
                 const int lda, const float *B, const int ldb,
                 const float beta, float *C, const int ldc) {


	for(int m = 0; m < M; m++) {
		for(int n = 0; n < N; n++) {
			float v = 0.f;
			for(int k = 0; k < K; k++) {
				v += A[m*lda + k] * B[k*ldb + n]; 
			}
			C[m*ldc + n] = v;
		}
	}
}

extern "C"
void my_sgemm(double (*gettime)(), const int M, const int N,
                 const int K, const float alpha, const float *A,
                 const int lda, const float *B, const int ldb,
                 const float beta, float *C, const int ldc);

static double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

bool CalcTime(int * times, double * start) {
	if(*times == 0) {
		*start = CurrentTimeInSeconds();
	} else {
		double elapsed = CurrentTimeInSeconds() - *start;
		if(elapsed > 0.1f && *times >= 3) {
			*start = elapsed / *times;
			return false;
		}
	}
	(*times)++;
	return true;
}

extern "C"
void sgemm_ispc_32x32(float* a, float* b, float* c, int dim);
//extern "C"
//void sgemm_terra_32x32(float* a, float* b, float* c);

//calculates C = alpha * AB + beta * C 
void testsize(int M, int K, int N) {

	float * A = (float*) malloc(sizeof(float) * M * K);
	float * B = (float*) malloc(sizeof(float) * K * N);
	float * C = (float*) malloc(sizeof(float) * M * N);
	float * C2 = (float*) malloc(sizeof(float) * M * N);
	float * C3 = (float*) malloc(sizeof(float) * M * N);


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
		C[i] = C2[i] = C3[i] = 0;


	int times = 0;
	double blastime;
	while(CalcTime(&times,&blastime))
		cblas_sgemm(CblasRowMajor, CblasNoTrans,CblasNoTrans, M,N,K,1.f,A,K,B,N,0.f,C,N);
		//naive_dgemm(M,N,K,1.f,A,K,B,N,0.f,C,N);
	//float begin2 = CurrentTimeInSeconds();
	//naive_dgemm(CblasRowMajor, CblasNoTrans,CblasNoTrans, M,N,K,1.f,A,K,B,N,0.f,C2,N);
	
	double mytime;
	times = 0;
	while(CalcTime(&times,&mytime)) {
		my_sgemm(CurrentTimeInSeconds,M,N,K,1.f,A,K,B,N,0.f,C3,N);
		//for(int i = 0; i < M*N; i++)
		//	C3[i] = 0;
		//sgemm_terra_32x32(A,B,C3);
	}
	/*
	for(int m = 0; m < M; m++) {
		for(int n = 0; n < N; n++) {
			printf("%f ",C[m*N + n]);
		}
		printf("\n");
	}
	printf("\n\n");
	
	for(int m = 0; m < M; m++) {
		for(int n = 0; n < N; n++) {
			printf("%f ",C3[m*N + n]);
		}
		printf("\n");
	}*/

	//asserteq(C,C2,M,N);
	asserteq(C,C3,M,N);

	free(C);
	free(C2);
	free(C3);
	free(A);
	free(B);
	double logblastime = log(M) + log(N) + log(K) + log(2) + log(1e-9) - log(blastime);
	double logmytime = log(M) + log(N) + log(K) + log(2) + log(1e-9) - log(mytime);
	printf("%d %d %d %f %f %f\n",M,K,N,exp(logblastime),exp(logmytime), mytime/ blastime);
}

int main() {

	int NB = 48;
	for(int i = NB; i < 3000; i += 3*NB) {
		testsize(i,i,i);
	}
	//testsize(5000,5000,5000);

	return 0;
}