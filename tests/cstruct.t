local C = terralib.includecstring [[

// Generate an empty struct record and verify
// it will be skipped and the actual struct
// definition record is used instead.
typedef struct teststruct teststruct;

struct teststruct {
  int idata;
  float fdata;
};

void makeitlive(struct teststruct * s) {}

]]


terra foo()
	var a : C.teststruct
	a.idata = 3
	a.fdata = 3.5
	return a.idata + a.fdata
end

assert(foo() == 6.5)
