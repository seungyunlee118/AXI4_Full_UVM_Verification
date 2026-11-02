# SHM waveform database for `make WAVE=1`; open it with `make view`.
database -open waves -shm -into waves.shm -default
probe -create tb_top -depth all -all -database waves
run
exit
