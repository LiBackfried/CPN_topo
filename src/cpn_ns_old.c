#ifndef CPN_NS_C
#define CPN_NS_C

/*
 for comparison and also for a nicer dual split
*/

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
	// TODO: should the structure conf member be a pointer??? no i didnt use that in the end
	CPN_Live_Conf *livepts;	// store CPN_Conf as well as the energies and labels of the live points
	CPN_Conf aux_conf;		// have one for the MC updates of a livepoint
	CPN_Param param;			// contains all the simulation parameters; still adapt!!
	Ns_Param dead_param;			
	Geometry geo;
	RNG_Param rng_state;
	double dead_energy=0.0;		// store the current lowest bound
	time_t start_date, finish_date, i_start_date, i_finish_date;
	clock_t start_time, finish_time, i_start_time, i_finish_time;
	// TODO: adapt the below FILE instances
	FILE *datafilep, *topofilep;   //, *swaptrackfilep get also rid of the swaptrackfile? or use smth similar to record the energies
	int i, dead_label=0;

	// TODO: fix this: I think it is fixed? But if I want to include more sophisticated read-ins/storage of live and dead points then it has to be adapted!
	// read input file -> TODO: requires a new input file but in principle i think i understand whats going on here
	read_input(input_file_name, &param);
	// printf("%d\n", param.d_N_live_pt);

	// initialization of rng state
	init_rng_state(&rng_state, &param);

	// open data file => TODO change later WHAT is printed into the data file!
	init_data_file(&datafilep, &param);

	// open topo data file	=> TODO: do i still want this? maybe smth different instead? or to save the data from the dead configs?
	init_topo_file(&topofilep, &param);

	// open swap tracking file => replace by some file that saves the measurements on the dead configs s.t. we dont have to save them?
	// init_swap_track_file(&swaptrackfilep, &param);

	// initialize geometry
	init_geometry(&geo, &param);

	// TODO!!!! a) conf or *conf in livepts? also: initialize ALL members, also the conf members!!!
	// initialize nest of live points
	init_CPN_lives(&livepts, &param, &rng_state);	// could get a new function init_CPN_livepts(...) where the boundary conditions are those of a single replica across all replicas

	// TODO: what exactly do i need?
	// initialize aux conf (will be used for cooling and for periodic conf translations) => we could use this just as the one dead_point that measurements are performed on; need two aux then?
	allocate_CPN_conf(&aux_conf, &param);

	// to use the aux for the initial MC chain, we need to also initialize it!!! e.g., use the first of the randomly initialized livepts
	// copyconf(&(livepts[0].conf), &param, &aux_conf); 
	// overheatbath_sweep_lattice(&(livepts[0].conf),&geo,&param,&rng_state);

	// printf("%d\n", 	param.d_measevery);
	// if heatbath nested sampling, overwrite the lives to initialize them according to the heatbath prior distribution
	// rewrite to be independent of the aux conf...!
	time(&i_start_date);
	i_start_time=clock();
	// init_CPN_lives_heatbath(livepts, &param, &geo, &aux_conf, &rng_state);
	init_CPN_lives_heatbath(livepts, &param, &geo, &rng_state);
	// init_CPN_lives_heatbath(&param, &geo, &aux_conf, &rng_state);
	time(&i_finish_date);
	i_finish_time=clock();
	fprintf(stdout, "#Heatbath init. time: %.10lf s\n", ((double)(i_finish_time-i_start_time))/CLOCKS_PER_SEC );


	/*************************** nested sampling routine ***************************/
	// initialize the energy densities E = S_{Symanzik}(theta=0) / (2 V N beta)
	//double energy_density(CPN_Conf const * const conf, Geometry const * const geo, CPN_Param const * const param) 

	// loop through live points, assign them energies, find smallest
	for(i=0;i<param.d_N_live_pt;i++){
		livepts[i].live_energy = energy_density(&(livepts[i].conf), &geo, &param);	// works; for cold start, is just 0.00!
		// printf("%f\n", livepts[i].live_energy);
		if (i == 0) 
		{
			dead_energy = livepts[i].live_energy;
			dead_label = 0;
			// printf("%f\n", livepts[i].live_energy);
			// printf("%d\n", dead_label);
		} else if (livepts[i].live_energy > dead_energy) {
			dead_energy = livepts[i].live_energy;
			dead_label = i;
		}
	}

	// assign initial vals to Ns_Param
	dead_param.dead_label = dead_label;
	// for testing, add a shitton of energy:
	dead_param.dead_energy = dead_energy + 100.0;
	dead_param.mc_switch = 0;
	// printf("%d\n", 	dead_param.dead_label);

	// DO SOME MEASUREMENTS HERE!
	perform_measures_localobs(&(livepts[dead_param.dead_label].conf), &geo, &param, datafilep, topofilep, &aux_conf);
	if (param.d_save_dead != 0) write_dead_conf(&(livepts[dead_param.dead_label].conf), &param, 0);

	// actually this throws an error since it might be used uninitialized...
	//printf("\nMinimum energy %f of configuration %d\n",dead_energy,dead_label);	// print dead_label (and dead_energy) otherwise it might throw an unassigned error
	// printf("%d\n",param.d_N_live_pt);
	// printf("%d\n",rand_int(&rng_state, 0, param.d_N_live_pt));

 	// Nested sampling loop begins
	time(&start_date);
	start_time=clock();
	for (i=0; i<param.d_N_meas_ns; i++)
	{
		// TODO: should i just move everything into a function?
		// 1) get new proposal conf for replacing the dead and copy into aux_conf
		dead_param.new_label = rand_int(&rng_state, 0, param.d_N_live_pt);
		while (dead_param.new_label == dead_param.dead_label) {
			dead_param.new_label = rand_int(&rng_state, 0, param.d_N_live_pt);
			// printf("%d\n",dead_param.new_label);
		}
		// printf("%d\n",dead_param.new_label);
		dead_param.new_energy = livepts[dead_param.new_label].live_energy;
		copyconf(&(livepts[dead_param.new_label].conf), &param, &aux_conf);
		// dead_energy = energy_density(&aux_conf, &geo, &param);
		
		/* perhaps just use the livept conf as update and if not copy back... no problems with a possible segfault...  */

		// 2) 	update the proposed conf according to overrel + heatbath MC steps => then check if the nested sampling constraint holds
		//		if the constraint is not fulfilled - do we introd a param for repeats on the MC updates? and after that we just use the og prop. config?
		// in analogy to update_with_defect:
		// update_with_defect(&aux_conf, &geo, &param, &rng_state);	// actually there is no defect! d_N_replica_pt == 1
		//  nested_sampling_update(&aux_conf , livepts, &param, &dead_param, &geo,&rng_state);
		// maybe add some counter that counts the succesful updates as we progress?
		/*********************************** continue in the above function tomorrow! ***********************************/
		// overheatbath_sweep_lattice(&aux_conf,&geo,&param,&rng_state);
		copyconf(&(livepts[dead_param.new_label].conf), &param, &(livepts[dead_param.dead_label].conf));
		nested_sampling_update(livepts, &param, &dead_param, &geo, &rng_state);

		/* seg fault when using the aux_conf, not when using the livepts though! */
		/* is it perhaps since we're indexing the conf? */
		// update_with_defect(&(livepts[dead_param.new_label].conf), &geo, &param, &rng_state);
		// update_with_defect(&(livepts[dead_param.dead_label].conf), &geo, &param, &rng_state);
		// update_with_defect(&aux_conf, &geo, &param, &rng_state);

		// => update with the live point config, in the worst case copy back the aux_conf
		// if (i==1) copyconf(&aux_conf, &param, &(livepts[dead_param.new_label].conf));
		
		// 3) identify smallest likelihood/largest E, measure, repeat => shouldnt we be doing this the other way around 
		// 		more conveniently?
		identify_dead_conf(livepts, &param, &dead_param);
		

		// SAVE THE DEAD CONF/DEAD MEAS HERE!
		// but only the dead conf, not the entire structure... maybe add at some point param. to turn on/off


		// potential stopping criterion?
		// 

		// do we want to put the measurements together into a final obs here? I would rather not, lets do that in python?
		perform_measures_localobs(&(livepts[dead_param.dead_label].conf), &geo, &param, datafilep, topofilep, &aux_conf);
		// TODO: add switch to save the dead configs as well!
		if (param.d_save_dead != 0) write_dead_conf(&(livepts[dead_param.dead_label].conf), &param, i+1);
		write_rng_state(&rng_state, &param);

		// printf("dead %d:\t energy %f\n", dead_param.dead_label, energy_density(&(livepts[dead_param.dead_label].conf), &geo, &param));
		// printf("prop %d:\t energy %f\n", dead_param.new_label, energy_density(&(livepts[dead_param.new_label].conf), &geo, &param));
	}
	
	// Monte Carlo ends
	time(&finish_date);
	finish_time=clock();
	fprintf(stdout, "#Simulation time: %.10lf s\n", ((double)(finish_time-start_time))/CLOCKS_PER_SEC );

	// write simulations details on file
	print_simulation_details_nest_samp_cpn(input_file_name, &param, &start_date, &finish_date, start_time, finish_time, &i_start_date, &i_finish_date, i_start_time, i_finish_time);

	// close data file
	fclose(datafilep);

	// close topo file
	fclose(topofilep);

	// free CPN replicas confs
	free_CPN_live_pts(livepts, &param);

	// free CPN aux conf
	free_CPN_conf(&aux_conf, &param);

	// free geometry
	free_geometry(&geo, &param);

	// // free rectangle params
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
