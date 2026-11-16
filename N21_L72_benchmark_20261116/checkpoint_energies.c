/* Recompute the live energies with the same routines used by cpn_ns. */
#include "../include/macro.h"
#include "../include/cpn_conf.h"
#include "../include/cpn_param.h"
#include "../include/geometry.h"

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "Usage: %s checkpoint_input.conf\n", argv[0]);
        return EXIT_FAILURE;
    }

    CPN_Param param;
    Geometry geo;
    CPN_Conf conf;
    read_input(argv[1], &param);
    init_geometry(&geo, &param);
    allocate_CPN_conf(&conf, &param);
    for (int slot = 0; slot < param.d_N_live_pt; slot++) {
        load_live_proposal(&conf, &param, slot);
        printf("%.17g\n", energy_density(&conf, &geo, &param));
    }
    free_CPN_conf(&conf, &param);
    free_geometry(&geo, &param);
    free_param(&param);
    return EXIT_SUCCESS;
}
