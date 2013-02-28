#include <stdio.h>
#include <Eigen/Dense>
#include <iostream>

#include <sys/time.h>

using namespace Eigen;

static double CurrentTimeInSeconds() {
  struct timeval tv;
  gettimeofday(&tv, NULL);
  return tv.tv_sec + tv.tv_usec / 1000000.0;
}


static const int N_OPTIONS = 10000000;
static const int N_BLACK_SCHOLES_ROUNDS = 1;

static const double invSqrt2Pi = 0.39894228040;
static const double LOG10 = log(10);

void cndV(ArrayXd& X, ArrayXd& k, ArrayXd& w, ArrayXd& res) {
  k = 1.0 / (1.0 + 0.2316419 * X.abs()); 
  w = (((((1.330274429*k) - 1.821255978)*k + 1.781477937)*k - 0.356563782)*k + 0.31938153)*k;
  w *=  invSqrt2Pi * (X * X * -.5).exp();
  res = (X>0).select(1-w,w);
}

double * fill(int n, double v) {
  double * a = new double[n];
  std::fill(a,a+n,v);
  return a;
}

int main() {
  ArrayXd S(N_OPTIONS);
  ArrayXd X(N_OPTIONS);
  ArrayXd TT(N_OPTIONS);
  ArrayXd r(N_OPTIONS);
  ArrayXd v(N_OPTIONS);

  S.fill(100.0);
  X.fill(98.0);
  TT.fill(2.0);
  r.fill(.02);
  v.fill(5.0);
  

  ArrayXd delta(N_OPTIONS);
  ArrayXd d1(N_OPTIONS);
  ArrayXd d2(N_OPTIONS);
  ArrayXd k(N_OPTIONS);
  ArrayXd w(N_OPTIONS);
  ArrayXd cnd1(N_OPTIONS);
  ArrayXd cnd2(N_OPTIONS);

  delta.fill(0);
  d1.fill(0);
  d2.fill(0);
  k.fill(0);
  w.fill(0);
  cnd1.fill(0);
  cnd2.fill(0);

  double begin = CurrentTimeInSeconds();
  double acc = 0.0;
  
  for(int j = 0; j < N_BLACK_SCHOLES_ROUNDS; j++) {
        delta = v * TT.sqrt();
        d1 = ((S/X).log()/LOG10 + (r+v*v*0.5) * TT) / delta;
        d2 = d1 - delta;
        cndV(d1,k,w,cnd1);
        cndV(d2,k,w,cnd2);
        acc = (S*cnd1-X*(-r*TT).exp()*cnd2).sum();
  }
  acc /= (N_BLACK_SCHOLES_ROUNDS * N_OPTIONS);
  printf("%f\n",acc);
  printf("Elapsed: %f\n",CurrentTimeInSeconds() - begin);
}
