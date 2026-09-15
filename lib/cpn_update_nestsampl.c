#ifndef CPN_UPDATE_NESTSAMPL_C
#define CPN_UPDATE_NESTSAMPL_C

#include "../include/cpn_nestsampl.h"

/*
	in addition, a file for the single link updates of the nested sampling routine:

	insetad of 
		for (j=0; j<param->d_num_micro; j++) microcanonic_sweep_lattice(&(conf[0]),geo,param);
			overheatbath_sweep_lattice(&(conf[0]),geo,param,rng_state);
	decide
	1) random choice of update type: over-relaxation with probability p and over-heat-bath with probability 1-p, p=num_micro/(num_micro + 1)
	2) random uniform choice of site x
	3) random uniform choice of the field to update: z, U_0 or U_1
	=> number of "stochastic" udpates: start with 3V to give every site and field the chance to be hit

	reuse num_single_site_stoc_upd, stored as d_stoc_single_site_upd, for the number of stochastic updates (start perhaps with 3V)
*/

// reuse the single link/field updates!

// TODO: pass tolerance around 1e-9?
// TODO: add later the possibility to measure acceptance rates!
// TODO: pass &(live_param[new_label]) ?  or at all?
void stochastic_nested_sampl_update(CPN_Conf *conf, CPN_Param const * const param, 
									NS_Param *live_param, NS_Param *dead_param,
									Geometry const * const geo, RNG_Param *rng_state,
									double *z_acceptance_rate, double *u_acceptance_rate)
{
	int i, mu;
	long x;
	int acc_z=0, acc_U=0;
	int upd_z=0, upd_U=0;

	double pr_field, pr_upd;
	double pr_micro = ((double)param->d_num_micro)/((double)( 1 + param->d_num_micro));

	double curr_E = energy_density(&(conf[0]), geo, param);	// the original proposal's energy
	double tol = 1e-9;


	for(i=0; i<param->d_stoc_single_site_upd; i++)
	{
		// pick random site to update
		x = (long int) floor(rand_num(rng_state) * ((double)param->d_volume));	// unif(0,1) * V

		// random choice of which field to update
		pr_field=rand_num(rng_state); // random number for field choice

		// random choice what kind of update to perform
		pr_upd=rand_num(rng_state)-pr_micro;		// pr-pr_micro < 0: micro upd

		// updates:
		if (pr_field < 1./3.) // update z-field
		{
			acc_z += nestsampl_update_single_field_z(&(conf[0]), param, dead_param, geo, rng_state, x, pr_upd, &curr_E, tol);
			upd_z++;

		} else {		// update U-field
			if(pr_field < 2.0/3.0) mu=0; // update U_0 field
			else mu=1; // update U_1 field

			acc_U += nestsampl_update_single_link_U(&(conf[0]), param, dead_param, geo, rng_state, x, mu, pr_upd, &curr_E, tol);
			upd_U++;
		}
	
		// normalize the lattice fields of the updated config
		if ((conf[0]).update_index % param->d_num_norm == 0) normalize_replicas(&(conf[0]),param); 
		(conf[0]).update_index++;
		// ... and recompute energy density
		curr_E = energy_density(&(conf[0]), geo, param);

		// in principal, the energy density should not be shifted across the threshold in this way; check to be safe though and for now exit program
		if(curr_E >= dead_param->conf_energy - tol) 
		{
			printf("Warning: Normalization shifted the energy above the constraint!\n");
			exit(EXIT_FAILURE);
		}
	}

	live_param[dead_param->conf_label].conf_energy = curr_E;
	write_live_conf(&conf[0], param, dead_param);

	*z_acceptance_rate = (upd_z > 0) ? ((double)acc_z / (double)upd_z) : 0.0;
	*u_acceptance_rate = (upd_U > 0) ? ((double)acc_U / (double)upd_U) : 0.0;

	// TODO: check final time the nested sampling constraint, overwrite perhaps the old dead slot with the new live!

	// TODO: should we include directly into the loop though a counter for the succesful constraints?

	

}

/*
	Perform the over-relaxation part as complete lattice sweeps, then apply the
	nested-sampling constraint separately to stochastic single-field/link
	heatbath proposals.  Acceptance rates therefore describe heatbath proposals
	only, rather than a mixture of microcanonical and heatbath updates.
*/
void stochastic_hb_nested_sampl_update(CPN_Conf *conf, CPN_Param const * const param,
									   NS_Param *live_param, NS_Param *dead_param,
									   Geometry const * const geo, RNG_Param *rng_state,
									   double *z_acceptance_rate, double *u_acceptance_rate)
{
	int i, mu;
	long x;
	int acc_z=0, acc_U=0;
	int upd_z=0, upd_U=0;
	double pr_field;
	double curr_E;
	double tol = 1e-9;

	for(i=0; i<param->d_num_micro; i++)
		microcanonic_sweep_lattice(&(conf[0]), geo, param);

	/* Recompute after the complete sweeps to avoid accumulating round-off. */
	curr_E = energy_density(&(conf[0]), geo, param);
	if(curr_E >= dead_param->conf_energy - tol)
	{
		fprintf(stderr, "Microcanonical sweeps shifted the energy above the nested-sampling constraint.\n");
		exit(EXIT_FAILURE);
	}

	for(i=0; i<param->d_stoc_single_site_upd; i++)
	{
		x = (long int) floor(rand_num(rng_state) * ((double)param->d_volume));
		pr_field = rand_num(rng_state);

		if(pr_field < 1.0/3.0)
		{
			acc_z += nestsampl_update_single_field_z(&(conf[0]), param, dead_param,
												 geo, rng_state, x, 1.0, &curr_E, tol);
			upd_z++;
		}
		else
		{
			mu = (pr_field < 2.0/3.0) ? 0 : 1;
			acc_U += nestsampl_update_single_link_U(&(conf[0]), param, dead_param,
												geo, rng_state, x, mu, 1.0, &curr_E, tol);
			upd_U++;
		}

		if ((conf[0]).update_index % param->d_num_norm == 0)
			normalize_replicas(&(conf[0]), param);
		(conf[0]).update_index++;
		curr_E = energy_density(&(conf[0]), geo, param);

		if(curr_E >= dead_param->conf_energy - tol)
		{
			fprintf(stderr, "Normalization shifted the energy above the nested-sampling constraint.\n");
			exit(EXIT_FAILURE);
		}
	}

	live_param[dead_param->conf_label].conf_energy = curr_E;
	write_live_conf(&(conf[0]), param, dead_param);

	*z_acceptance_rate = (upd_z > 0) ? ((double)acc_z / (double)upd_z) : 0.0;
	*u_acceptance_rate = (upd_U > 0) ? ((double)acc_U / (double)upd_U) : 0.0;
}



int nestsampl_update_single_field_z(CPN_Conf *conf, CPN_Param const * const param, 
									NS_Param *dead_param, Geometry const * const geo, 
									RNG_Param *rng_state, long const n, double const which_update,
									double *curr_E, double tol)
{
	double local_old, local_new, trial_E;
	cmplx z_old[N] __attribute__((aligned(DOUBLE_ALIGN)));
	vector_equal(z_old, conf->z[n]);

	// initial local energy contribution (unnormalized! <-> no 1/V)
	local_old = local_energy_z(conf, geo, n);

	// update the single field
	if(which_update < 0) microcanonic_single_site_z(conf, geo, n);		// should not change the energy!
	else overheatbath_single_site_z(conf, geo, param, n, rng_state);

	// unnorm. local energy contribution after single field update
	local_new = local_energy_z(conf, geo, n);

	// check updated energy density and compare to the overall nest sampl constraint
	trial_E = *curr_E + (local_new - local_old) / (double)param->d_volume;

	if (trial_E < dead_param->conf_energy - tol) {
		*curr_E = trial_E;
		return 1;
	} else {
		vector_equal(conf->z[n], z_old);
		return 0;
	}
}						

int nestsampl_update_single_link_U(CPN_Conf *conf, CPN_Param const * const param, 
									NS_Param *dead_param, Geometry const * const geo, 
									RNG_Param *rng_state, long const n, int const mu, double const which_update,
									double *curr_E, double tol)
{
	double local_old, local_new, trial_E;
	cmplx U_old = conf->U[n][mu];

	// initial local energy contribution (unnormalized! <-> no 1/V)
	local_old = local_energy_U(conf, geo, n, mu);

	// update the single field
	if(which_update < 0) microcanonic_single_link_U(conf, geo, param, n, mu);		// should not change the energy! 
	else overheatbath_single_link_U(conf, geo, param, n, mu, rng_state);

	// unnorm. local energy contribution after single field update
	local_new = local_energy_U(conf, geo, n, mu);

	// check updated energy density and compare to the overall nest sampl constraint
	trial_E = *curr_E + (local_new - local_old) / (double)param->d_volume;

	if (trial_E < dead_param->conf_energy - tol) {
		*curr_E = trial_E;
		return 1;
	} else {
		conf->U[n][mu] = U_old;
		return 0;
	}
}


// compute the local energy for single field: E = S_{Symanzik}(theta=0)[z_x|U_x,mu] / (2 N beta) 
// => normalize with 1/V later, leave out terms only ~ ci
double local_energy_z(CPN_Conf const * const conf, Geometry const * const geo, long const n)
{
	int mu;
	double e = 0.0;
	cmplx e1 = 0.0 + I * 0.0, e2 = 0.0 + I * 0.0; 
	cmplx aux1, aux2;
	
	for(mu=0 ; mu<2 ; mu++)
	{
		// first contrib ~ c1
		aux1=vector_scalar_product(conf->z[geo->up[n][mu]], conf->z[n]); // conj( z(n+mu) ) * z(n)
		e1 += conj(conf->U[n][mu]) * aux1;	 // [conj( z(n+mu) ) * z(n)] * conj U(n)_mu

		// second contrib ~ c1
		aux1=vector_scalar_product(conf->z[n], conf->z[geo->dn[n][mu]]); // conj( z(n) ) * z(n-mu)
		e1 += conj(conf->U[geo->dn[n][mu]][mu]) * aux1;	 // [conj( z(n+mu) ) * z(n)] * conj U(n)_mu

		// first contrib ~ c2
		aux2=vector_scalar_product(conf->z[geo->up[geo->up[n][mu]][mu]], conf->z[n]); // conj( z(n+2mu) ) * z(n)
		e2 += conj(conf->U[geo->up[n][mu]][mu] * conf->U[n][mu]) * aux2;  // [conj( z(n+2mu) ) * z(n)]  * conj U(n+mu)_mu * conj U(n)_mu

		// second contrib ~ c2
		aux2=vector_scalar_product(conf->z[n], conf->z[geo->dn[geo->dn[n][mu]][mu]]); // conj( z(n) ) * z(n-2mu)
		e2 += conj(conf->U[geo->dn[n][mu]][mu] * conf->U[geo->dn[geo->dn[n][mu]][mu]][mu]) * aux2;   // [...]  * conj U(n-mu)_mu * conj U(n-2mu)_mu
	}
	
	e = - (c1*creal(e1) + c2*creal(e2)); 
	// e /= (double)(param->d_volume);
	return e; 
}

double local_energy_U(CPN_Conf const * const conf, Geometry const * const geo, long const n, int const mu)
{
	double e = 0.0;
	cmplx e1 = 0.0 + I * 0.0, e2 = 0.0 + I * 0.0; 
	cmplx aux1, aux2;

	// first contrib ~ c1
	aux1=vector_scalar_product(conf->z[geo->up[n][mu]], conf->z[n]); // conj( z(n+mu) ) * z(n)
	e1 += conj(conf->U[n][mu]) * aux1;	 // [conj( z(n+mu) ) * z(n)] * conj U(n)_mu

	// first contrib ~ c2
	aux2=vector_scalar_product(conf->z[geo->up[geo->up[n][mu]][mu]], conf->z[n]); // conj( z(n+2mu) ) * z(n)
	e2 += conj(conf->U[geo->up[n][mu]][mu] * conf->U[n][mu]) * aux2;  // [conj( z(n+2mu) ) * z(n)]  * conj U(n+mu)_mu * conj U(n)_mu

	// second contrib ~ c2
	aux2=vector_scalar_product(conf->z[geo->up[n][mu]], conf->z[geo->dn[n][mu]]); // conj( z(n+mu) ) * z(n-mu)
	e2 += conj(conf->U[n][mu] * conf->U[geo->dn[n][mu]][mu]) * aux2;   // [...]  * conj U(n)_mu * conj U(n-mu)_mu

	e = - (c1*creal(e1) + c2*creal(e2)); 
	// e /= (double)(param->d_volume);
	return e; 
}









#endif
