/**
 * file: cpn_ns.c (new version)
 * description: lattice simulations of 2d CP^{N-1} models topology via nested sampling
 * author: Liane Backfried, Claudio Bonanno
 *         based on the CPN topo package by Claudio Bonanno
 * date: 16.07.2026
*/

#ifndef CPN_NS_C
#define CPN_NS_C

#include "../include/macro.h" // NOTE: must be included before stdlib.h to activate posix_memalign correctly
#include "../include/cpn_conf.h"
#include "../include/cpn_cmplx_op.h"
#include "../include/cpn_param.h"
#include "../include/geometry.h"
#include "../include/rng.h"
#include "../include/endianness.h"

#include<stdio.h>
#include<stdlib.h>
#include<time.h>
#include<string.h>

void real_main(char *input_file_name) 
{
	// can we modify the CPN_Live_Conf in such a way, that it contains the path or so? => save and load the configs s.t. we can have a lot of consecutive live points
	// vars
	CPN_Conf *conf;
	CPN_Conf aux_conf;			// have one for the measurements
	CPN_Param param;			// contains all the simulation parameters; adapt potentially to be tailored to the nested sampling setup	
	NS_Param *live_param;	
	NS_Param dead_param;	
	Geometry geo;
	RNG_Param rng_state;
	time_t start_date, finish_date, i_start_date, i_finish_date;
	clock_t start_time, finish_time, i_start_time, i_finish_time;
	FILE *datafilep, *topofilep;
	FILE *acc_file;	// for the constraint acc.rate
	int i, new_label;
	double acc_rate, proposal_energy, u_candidates_per_angle, z_candidates_per_angle;

	// reuse the previous input_file template but add the nested sampling parameters
	read_input(input_file_name, &param);
	if (param.d_N_live_pt < 2)
	{
		fprintf(stderr, "Nested sampling requires at least two live points.\n");
		exit(EXIT_FAILURE);
	}
	if (param.d_num_norm <= 0)
	{
		fprintf(stderr, "num_norm must be positive.\n");
		exit(EXIT_FAILURE);
	}
	
	// initialization of rng state; if continued run, d_rng_start == 1, else == 0
	init_rng_state(&rng_state, &param);

	// open data file
	// TODO: change later WHAT is printed into the data file! (potentially)
	init_data_file(&datafilep, &param);

	// open topo data file
	init_topo_file(&topofilep, &param);

	// TODO: potentially another file that records further nested sampling stats?
	//

	// initialize geometry
	init_geometry(&geo, &param);
	
	// initialize aux conf (will be used for cooling and for periodic conf translations)
	allocate_CPN_conf(&aux_conf, &param);

	// initialize list of live point energies
	init_CPN_live_energies(&live_param, &param, &dead_param);

	// initialize ensemble of live points, fill live energies and dead param => single output conf contains current dead
	// if heatbath nested sampling, initialize the live points according to the heatbath prior distribution
	time(&i_start_date);
	i_start_time=clock();
	init_single_CPN_live(&conf, &live_param, &dead_param, &param, &geo, &rng_state);
	time(&i_finish_date);
	i_finish_time=clock();
	fprintf(stdout, "#Heatbath init. time: %.10lf s\n", ((double)(i_finish_time-i_start_time))/CLOCKS_PER_SEC );
	// printf("managed so far\n");

	/****
	   after init_single_CPN_live, conf[0] contains the current dead conf, 
	   dead_param the associated energy density, E = S_{Symanzik}(theta=0) / (2 V N beta), 
	   and the label 
	****/

	// do some measurements before starting the nested sampling routine
	perform_measures_localobs(&(conf[0]), &geo, &param, datafilep, topofilep, &aux_conf);
	if (param.d_save_dead != 0) write_dead_conf(&(conf[0]), &param, 0);
	write_live_energy_on_file(live_param, &param);

	/*-----------------------------------------------------------------------------*/
	/*************************** nested sampling routine ***************************/
	/*-----------------------------------------------------------------------------*/

	time(&start_date);
	start_time=clock();
	for (i=1; i<param.d_N_meas_ns; i++)
	{
		/* 0) copy the current dead energy for the acceptance rate measurement */
		// dead_E = live_param[dead_param.conf_label].conf_energy;


		/* 1) get new proposal conf for replacing the dead; load into conf */
		new_label = rand_int(&rng_state, 0, param.d_N_live_pt);
		while (new_label == dead_param.conf_label) new_label = rand_int(&rng_state, 0, param.d_N_live_pt);
		load_live_proposal(&(conf[0]), &param, new_label);
		proposal_energy = live_param[new_label].conf_energy;

		// also update the energy of the former dead config with that of the proposed new config and save proposal into dead slot
		live_param[dead_param.conf_label].conf_energy = live_param[new_label].conf_energy;
		write_live_conf(&(conf[0]), &param, &dead_param);


		/* 2) 	update the proposed conf according to overrel + heatbath MC steps => then check if the nested sampling constraint holds 
	    		if the constraint is not fulfilled the updates are looped
		*/
		// nested_sampling_update(conf, &param, live_param, &dead_param, &geo, &rng_state);
		// what we have at this point: conf has the replacement live for the dead; and live_param[dead] = new energy
		
		// save new live in place of old dead
		// write_live_conf(&(conf[0]), &param, &dead_param);
		
		// combine the acceptance rate measurements and writing of the live TODO: move below the dead param? or we want to explicitly see the energy of the proposal! such that we can gauge where in the distribution we are...!
		acc_rate = nested_sampling_updat_w_accrate(conf, &param, live_param, &dead_param, &geo, &rng_state,
														 &u_candidates_per_angle, &z_candidates_per_angle);
 		// we might actually be more interested in the proposal's original energy? no but the dead energy should also be good, since this is the benchmark!
		acc_file = fopen("acceptance_rate.dat", "a");
		if (acc_file == NULL)
		{
			perror("Error opening acceptance_rate.dat");
			exit(EXIT_FAILURE);
		}
		/* Columns: NS iteration, constraint acceptance, proposal energy, and mean
		   Von Neumann candidates needed per accepted U and z angle respectively. */
		fprintf(acc_file, "%d %.8f %.8f %.8f %.8f\n", i, acc_rate, proposal_energy,
				u_candidates_per_angle, z_candidates_per_angle);
		fclose(acc_file);

		// identify new dead, overwrite dead_param, load dead config for measurements
		identify_dead_conf(&live_param, &param, &dead_param);
		// printf("New dead E: %.10lf \n",dead_param.conf_energy);
		load_live_proposal(&(conf[0]), &param, dead_param.conf_label);
		
		// potentially save dead conf
		if (param.d_save_dead != 0) write_dead_conf(&(conf[0]), &param, i);


		/* 3) measurements on dead conf */
		perform_measures_localobs(&(conf[0]), &geo, &param, datafilep, topofilep, &aux_conf);		


		/* 4) potential stopping criterion? */


		/* 5) config files */
		write_live_energy_on_file(live_param, &param);
		write_rng_state(&rng_state, &param);
		
	}
	time(&finish_date);
	finish_time=clock();
	fprintf(stdout, "#Simulation time: %.10lf s\n", ((double)(finish_time-start_time))/CLOCKS_PER_SEC );


	/*-----------------------------------------------------------------------------*/
	/********************************** clean up  **********************************/
	/*-----------------------------------------------------------------------------*/
	// write simulations details on file
	print_simulation_details_nest_samp_cpn(input_file_name, &param, &start_date, &finish_date, start_time, finish_time, &i_start_date, &i_finish_date, i_start_time, i_finish_time);

	// close data file
	fclose(datafilep);

	// close topo file
	fclose(topofilep);

	// close live energy file
	// fclose(livenergfilep);	

	// free the energy vector!
	free_CPN_live_energies(live_param);

	// free CPN conf (put d_N_replica=1)
	free_CPN_replicas(conf, &param);

	// free CPN aux conf
	free_CPN_conf(&aux_conf, &param);

	// free geometry
	free_geometry(&geo, &param);

	// free params
	free_param(&param); 
}

int main (int argc, char **argv)
{
	char input_file_name[STD_STRING_LENGTH];
	if(argc != 2)
	{
		printf("\n");
		printf("__________________________________________________________________________________________________________________________________\n");
		printf("|________________________________________________________________________________________________________________________________|\n");
		printf("||                                                                                                                              ||\n");
		printf("||                                                                                                                              ||\n");
		printf("||      ,o888888o.    8 888888888o   b.             8      8888888 8888888888 ,o888888o.     8 888888888o       ,o888888o.      ||\n");
		printf("||     8888     `88.  8 8888    `88. 888o.          8            8 8888    . 8888     `88.   8 8888    `88.  . 8888     `88.    ||\n");
		printf("||  ,8 8888       `8. 8 8888     `88 Y88888o.       8            8 8888   ,8 8888       `8b  8 8888     `88 ,8 8888       `8b   ||\n");
		printf("||  88 8888           8 8888     ,88 .`Y888888o.    8            8 8888   88 8888        `8b 8 8888     ,88 88 8888        `8b  ||\n");
		printf("||  88 8888           8 8888.   ,88' 8o. `Y888888o. 8            8 8888   88 8888         88 8 8888.   ,88' 88 8888         88  ||\n");
		printf("||  88 8888           8 888888888P'  8`Y8o. `Y88888o8            8 8888   88 8888         88 8 888888888P'  88 8888         88  ||\n");
		printf("||  88 8888           8 8888         8   `Y8o. `Y8888            8 8888   88 8888        ,8P 8 8888         88 8888        ,8P  ||\n");
		printf("||  `8 8888       .8' 8 8888         8      `Y8o. `Y8            8 8888   `8 8888       ,8P  8 8888         `8 8888       ,8P   ||\n");
		printf("||     8888     ,88'  8 8888         8         `Y8o.`            8 8888    ` 8888     ,88'   8 8888          ` 8888     ,88'    ||\n");
		printf("||      `8888888P'    8 8888         8            `Yo            8 8888       `8888888P'     8 8888             `8888888P'      ||\n");
		printf("||                                                                                                                              ||\n");
		printf("||______________________________________________________________________________________________________________________________||\n");
		printf("|________________________________________________________________________________________________________________________________|\n");
		printf("\n");
		printf("Package: %s-v%s\n", PACKAGE_NAME, PACKAGE_VERSION);
		printf("Compiled from main %s\n", __FILE__);
		printf("Description: lattice simulations of 2d CP^{N-1} models topology via parallel tempering\n\n");
		printf("Author: Claudio Bonanno\n");
		printf("Other contributors: Mario Berni, Davide Vadacchino\n");
		printf("Bug report: %s\n", PACKAGE_BUGREPORT);
		printf("\nCompiled with N = %i\n", N);
		#ifdef __INTEL_COMPILER
		printf("Compiled with icc\n");
		#elif defined( __GNUC__ )
		printf("Compiled with gcc %d.%d.%d\n", __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__);
		#endif
		printf("Usage: %s input_file \n", argv[0]);
		return(EXIT_FAILURE);
	}
	else
	{
		if(strlen(argv[1]) >= STD_STRING_LENGTH)
		{
			fprintf(stderr, "Input file name too long. Increase STD_STRING_LENGTH in include/macro.h\n");
			return(EXIT_FAILURE);
		}
		else
		{
			strcpy(input_file_name, argv[1]);
			real_main(input_file_name);
			return(EXIT_SUCCESS);
		}
	}
}

#endif
