// just some random snippets of code that might be useful or might be turned into proper structures in the end"
#include "../include/cpn_conf.h"

// note that if we are ever going to use this setup, we should reference it in some headerfile!

// a basic setup could look like this:
typedef struct LivePoint
{
    CPN_Conf x;   // config will be smth like
    double E;
} LivePoint;

// ChatGPT says:
LivePoint *live_points; // get address
int K;  // nr of live points

// allocate memory
live_points = malloc(K * sizeof(LivePoint));

// and initialize
for(int i=0; i<K; i++){
    random_config(&live_points[i].x);               // initialize the config
    live_points[i].E = energy(&live_points[i].x);   // compute energy

}

