from pathlib import Path

# nr of files to generate:
nr_runs = 10

# ==========================
# Parameters
# ==========================

# Theory
L_t = 72
L_x = 72
beta = 0.6
theta = 0.0

# Simulation
num_MC_step = 40
meas_every = 8
num_micro = 4
num_norm = 1
save_conf_every = 1

start = 1

num_cool_step = 50
meas_cool_every = 5

base_seed = 1000
rng_start = 0

# Nested sampling
num_live_pts = 10
num_ns_meas = 2000
save_dead = 0

# ==========================
# Template loop
# ==========================

for run in range(nr_runs):
    # Output directory
    outdir = Path(f"out_data/quick_run_{run}")
    scratch_dir = Path(f"/scratch/network/users/lb25v444/{outdir}")

    # Create the directories if they don't already exist
    outdir.mkdir(parents=True, exist_ok=True)
    scratch_dir.mkdir(parents=True, exist_ok=True)

    rng_seed = base_seed + 20*run

    config = f"""# continued run: rng_start {rng_start}, start {start}
# theory parameters
size   {L_t} {L_x}    # L_t L_x
beta   {beta}      # bare inverse coupling
theta  {theta}      # bare imaginary theta

# simulation details
num_MC_step      {num_MC_step}
meas_every       {meas_every}
num_micro        {num_micro}
num_norm         {num_norm}
save_conf_every  {save_conf_every}

start {start}

num_cool_step    {num_cool_step}
meas_cool_every  {meas_cool_every}

rng_seed  {rng_seed}
rng_start {rng_start}

# Hasenbusch parallel tempering parameters
num_replica  1
defect_size  0
hierarc_upd  0

# multicanonic parameters
grid_step 1
grid_max 100
# num_smooth_step 0
num_single_site_stoc_upd 2500

# nested sampling parameters
num_live_pts {num_live_pts}
num_ns_meas {num_ns_meas}
save_dead {save_dead}

# file names
conf_file                 {scratch_dir}/conf
data_file                 {outdir}/dati.dat
topo_file                 {outdir}/topo.dat
live_energy_file          {outdir}/live_energy.dat
log_file                  {outdir}/my_log.dat
rng_state_file            {outdir}/rng_state.dat
swap_acc_file             {outdir}/swap_acc.dat
swap_track_file           {outdir}/swap_track.dat
topo_potential_file       {outdir}/topo_potential
multicanonic_acc_file     {outdir}/multicanonic_acc.dat
    """

    # ==========================
    # Write file
    # ==========================

    filename = f"config_files/quick_parallel_runs/config_run_{run}"

    with open(filename, "w") as f:
        f.write(config)

    print(f"Wrote {filename}")