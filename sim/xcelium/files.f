// ---------------------------------------------------------------------------
// Compile order for xrun. Read with -F, so paths are relative to this file.
// Both DUT revisions are compiled; -define DUT_V2 picks one in tb_top.
// ---------------------------------------------------------------------------

-incdir ../../tb/uvm

../../rtl/axi_ram.v
../../rtl/Axi_ram_v2.v

../../tb/axi4_if.sv
../../tb/axi4_sva.sv
../../tb/axi4_pkg.sv
../../tb/tb_top.sv
