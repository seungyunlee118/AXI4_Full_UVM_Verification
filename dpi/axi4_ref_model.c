/*=============================================================
 * axi4_ref_model.c — golden AXI memory, called from SystemVerilog
 * via DPI-C. Byte-addressable, implementation-independent storage
 * for the AXI4 scoreboard's reference model. 16-bit address space.
 *=============================================================*/
#include <string.h>
#include "svdpi.h"

#define N (1 << 16)
#define M (N - 1)
static unsigned char mem[N];

void axi_ref_reset(void)                    { memset(mem, 0, sizeof(mem)); }
void axi_ref_write_byte(int addr, int data) { mem[(unsigned)addr & M] = (unsigned char)(data & 0xFF); }
int  axi_ref_read_byte(int addr)            { return (int)mem[(unsigned)addr & M]; }
