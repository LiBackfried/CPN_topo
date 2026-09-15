#ifndef CPN_NESTSAMPL_H
#define CPN_NESTSAMPL_H

#include "cpn_conf.h"

// in lib/cpn_update_nestsampl.c
void stochastic_nested_sampl_update(CPN_Conf *, CPN_Param const * const,
									NS_Param *, NS_Param *, Geometry const * const,
									RNG_Param *, double *, double *);

void stochastic_hb_nested_sampl_update(CPN_Conf *, CPN_Param const * const,
									   NS_Param *, NS_Param *, Geometry const * const,
									   RNG_Param *, double *, double *);

int nestsampl_update_single_field_z(CPN_Conf *, CPN_Param const * const,
									NS_Param *, Geometry const * const, RNG_Param *,
									long const, double const, double *, double);

int nestsampl_update_single_link_U(CPN_Conf *, CPN_Param const * const,
									NS_Param *, Geometry const * const, RNG_Param *,
									long const, int const, double const, double *, double);

double local_energy_z(CPN_Conf const * const, Geometry const * const, long const);
double local_energy_U(CPN_Conf const * const, Geometry const * const, long const, int const);

#endif
