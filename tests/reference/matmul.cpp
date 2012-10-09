#include<Accelerate/Accelerate.h>
#include<stdio.h>
#include<assert.h>
#include<sys/time.h>
/*
void cblas_sgemm(const enum CBLAS_ORDER Order, const enum CBLAS_TRANSPOSE TransA,
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
	for(int i = 0; i < M*N; i++)
		if(A[i] != B[i]) {
			printf("%d: %f ~= %f\n",i,A[i],B[i]);
			assert(false);
		}
}

void naive_sgemm(const enum CBLAS_ORDER Order, const enum CBLAS_TRANSPOSE TransA,
                 const enum CBLAS_TRANSPOSE TransB, const int M, const int N,
                 const int K, const float alpha, const float *A,
                 const int lda, const float *B, const int ldb,
                 const float beta, float *C, const int ldc) {
	assert(Order == CblasRowMajor);
	assert(TransA == CblasNoTrans);
	assert(TransB == CblasNoTrans);
	assert(alpha == 1.f);
	assert(beta == 0.f);

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
void my_sgemm(const int M, const int N,
                 const int K, const float alpha, const float *A,
                 const int lda, const float *B, const int ldb,
                 const float beta, float *C, const int ldc);

static double CurrentTimeInSeconds() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1000000.0;
}

//calculates C = alpha * AB + beta * C 
void testsize(int M, int K, int N) {

	float * A = (float*) malloc(sizeof(float) * M * K);
	float * B = (float*) malloc(sizeof(float) * K * N);
	float * C = (float*) malloc(sizeof(float) * M * N);
	float * C2 = (float*) malloc(sizeof(float) * M * N);
	float * C3 = (float*) malloc(sizeof(float) * M * N);


	for(int m = 0; m < M; m++) {
		for(int k = 0; k < K; k++) {
			if(m == k)
				A[m*K + k] = 1.f;
			else
				A[m*K + k] = 0.f;
		}
	}
	int i = 0;
	for(int k = 0; k < K; k++) {
		for(int n = 0; n < N; n++) {
			B[k*N + n] = i++;
		}
	}

	for(int i = 0; i < M *N; i++) 
		C[i] = C2[i] = C3[i] = 0.f;


	double begin = CurrentTimeInSeconds();
	cblas_sgemm(CblasRowMajor, CblasNoTrans,CblasNoTrans, M,N,K,1.f,A,K,B,N,0.f,C,N);
	double begin2 = CurrentTimeInSeconds();
	naive_sgemm(CblasRowMajor, CblasNoTrans,CblasNoTrans, M,N,K,1.f,A,K,B,N,0.f,C2,N);
	double begin3 = CurrentTimeInSeconds();
	my_sgemm(M,N,K,1.f,A,K,B,N,0.f,C3,N);
	double finish = CurrentTimeInSeconds();

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
			printf("%f ",C2[m*N + n]);
		}
		printf("\n");
	}*/

	asserteq(C,C2,M,N);
	asserteq(C,C3,M,N);

	free(C);
	free(C2);
	free(C3);
	free(A);
	free(B);
	printf("%d %d %d %f %f %f\n",M,K,N,begin2 - begin, begin3 - begin2, finish - begin3);
}

int main() {

	for(int i = 100; i < 1000; i += 100) {
		testsize(i,i,i);
	}

	return 0;
}