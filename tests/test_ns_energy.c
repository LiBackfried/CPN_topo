#include "../include/cpn_nestsampl.h"
#include <assert.h>
#include <float.h>
#include <string.h>

static void check_cutoff(CPN_Conf *conf, CPN_Conf *trial, CPN_Conf const *original, CPN_Param const *param,
						 Geometry const *geo, RNG_Param *rng, int field)
{
	double const tol = 1.0e-9;
	double const roundoff = 32.0 * (double)param->d_volume * DBL_EPSILON;
	double const old_energy = energy_density(conf, geo, param);
	RNG_Param before_proposal = *rng;
	double trial_energy = old_energy;
	long site = 0;
	int const mu = field - 1;
	for (; site<param->d_volume; site++)
	{
		copyconf(conf, param, trial);
		before_proposal = *rng;
		if (field == 0)
			overheatbath_single_site_z(trial, geo, param, site, rng);
		else
			overheatbath_single_link_U(trial, geo, param, site, mu, rng);
		trial_energy = energy_density(trial, geo, param);
		if (trial_energy > old_energy) break;
	}
	assert(site < param->d_volume);

	/* Bias the running estimate towards the opposite decision. Recompute
	   the installed proposal to distinguish equality from one ULP below. */
	for (int test=0; test<3; test++)
	{
		double const at_limit = trial_energy + tol;
		double const cutoffs[] = {trial_energy, at_limit, nextafter(at_limit, INFINITY)};
		NS_Param dead = {.conf_energy = cutoffs[test]};
		assert(at_limit - tol == trial_energy);
		int const should_accept = test == 2;
		double const biased = old_energy + (should_accept ? 0.5 : -0.5) * roundoff;
		double running = biased;
		RNG_Param replay = before_proposal;
		int const accepted = field == 0
			? nestsampl_update_single_field_z(conf, param, &dead, geo, &replay, site, 1.0, &running, tol, roundoff)
			: nestsampl_update_single_link_U(conf, param, &dead, geo, &replay, site, mu, 1.0, &running, tol, roundoff);
		assert(accepted == should_accept);
		if (accepted)
		{
			assert(running == trial_energy);
			assert(running == energy_density(conf, geo, param));
		}
		else
		{
			assert(running == biased);
			assert(energy_density(conf, geo, param) == old_energy);
			for (long i=0; i<param->d_volume; i++)
			{
				assert(memcmp(conf->z[i], original->z[i], N * sizeof(cmplx)) == 0);
				assert(memcmp(conf->U[i], original->U[i], 2 * sizeof(cmplx)) == 0);
			}
		}
	}
}

int main(int argc, char **argv)
{
	assert(argc == 2);
	CPN_Param param;
	Geometry geo;
	RNG_Param rng;
	CPN_Conf conf, trial, original;
	read_input(argv[1], &param);
	init_geometry(&geo, &param);
	init_rng_state(&rng, &param);
	allocate_CPN_conf(&conf, &param);
	allocate_CPN_conf(&trial, &param);
	allocate_CPN_conf(&original, &param);
	init_bound_cond(&conf, 0, &param);
	init_bound_cond(&trial, 0, &param);
	init_CPN_conf(&conf, &param, param.d_conf_file, &rng);
	for (int i=0; i<4; i++) overheatbath_sweep_lattice(&conf, &geo, &param, &rng);
	copyconf(&conf, &param, &original);
	for (int field=0; field<3; field++)
	{
		copyconf(&original, &param, &conf);
		check_cutoff(&conf, &trial, &original, &param, &geo, &rng, field);
		for (long site=0; site<param.d_volume; site++)
		{
			assert(memcmp(conf.z[site], trial.z[site], N * sizeof(cmplx)) == 0);
			assert(memcmp(conf.U[site], trial.U[site], 2 * sizeof(cmplx)) == 0);
		}
	}
	free_bound_cond(&conf, &param);
	free_bound_cond(&trial, &param);
	free_CPN_conf(&conf, &param);
	free_CPN_conf(&trial, &param);
	free_CPN_conf(&original, &param);
	free_geometry(&geo, &param);
	free_param(&param);
	puts("Near-cutoff site and link proposals passed");
	return 0;
}
