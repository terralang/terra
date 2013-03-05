#include <stdio.h>
#include <algorithm>
#include <math.h>
#include <float.h>

#include "timing.h"

#include <Eigen/Dense>

using namespace Eigen;

int main() {

	int n = 10000000;
	double xo = 0;
	double yo = 0;
	double zo = 0;
	double xd = 1;
	double yd = 0;
	double zd = 0;
	
  ArrayXd xc(n);
  ArrayXd yc(n);
  ArrayXd zc(n);

	for(int i = 0; i < n; i++) {
		xc[i] = i;
		yc[i] = i;
		zc[i] = i;
	}

  ArrayXd b(n);
  ArrayXd c(n);
  ArrayXd disc(n);
    ArrayXd res(n);
	b.fill(0);
	c.fill(0);
	disc.fill(0);
	res.fill(0);
	double begin = current_time();

	double a = 1;
		
	double r = DBL_MAX;
	
  b = 2*(xd*(xo-xc)+yd*(yo-yc)+zd*(zo-zc));
  c = (xo-xc)*(xo-xc)+(yo-yc)*(yo-yc)+(zo-zc)*(zo-zc)-1;
  disc = b*b-4*c;
  res = ((disc<0).select(((-b - disc.sqrt())/2),DBL_MAX)); //.min( (-b + disc)/2),DBL_MAX));
  r = res.minCoeff();

	printf("%f\n",r);
	printf("Elapsed: %f\n", current_time()-begin);
	return 0;
}
