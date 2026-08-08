//=============================================================
// dpi_demo_tb.sv — DPI-C golden-memory demo
//
// Self-contained extract of the AXI4 project's reference model:
// the golden memory lives in C (axi4_ref_model.c) and is driven
// from SystemVerilog through DPI-C, exactly as the UVM scoreboard
// does. Demonstrates the two non-trivial modelling rules:
//   - write-strobe byte masking
//   - narrow transfers folding into one aligned bus word
//
// Runs on any DPI-capable simulator (Questa/VCS/Riviera, and Vivado
// XSim for this small non-UVM case). On EDA Playground: pick Mentor
// Questa, add both files, no UVM needed.
//=============================================================
module dpi_demo_tb;

    import "DPI-C" function void axi_ref_reset();
    import "DPI-C" function void axi_ref_write_byte(input int addr, input int data);
    import "DPI-C" function int  axi_ref_read_byte (input int addr);

    localparam int STRB_W = 4;   // 32-bit bus
    int errors = 0;

    // ---- predict: apply one write beat with byte strobes ----
    function automatic void apply_write_beat(int addr, bit [31:0] data, bit [3:0] strb);
        int word_base = addr - (addr % STRB_W);
        for (int lane = 0; lane < STRB_W; lane++)
            if (strb[lane])
                axi_ref_write_byte(word_base + lane, int'(data[8*lane +: 8]));
    endfunction

    // ---- check: expected full aligned word from the model ----
    function automatic bit [31:0] expected_word(int addr);
        int word_base = addr - (addr % STRB_W);
        for (int lane = 0; lane < STRB_W; lane++)
            expected_word[8*lane +: 8] = axi_ref_read_byte(word_base + lane)[7:0];
    endfunction

    task automatic check(string name, bit [31:0] got, bit [31:0] exp);
        if (got !== exp) begin
            $display("  [FAIL] %-22s got=0x%08h exp=0x%08h", name, got, exp);
            errors++;
        end else
            $display("  [ ok ] %-22s = 0x%08h", name, got);
    endtask

    initial begin
        $display("=== DPI-C golden-memory demo ===");

        // 1) full-word write/read
        axi_ref_reset();
        apply_write_beat(16'h0000, 32'hDEADBEEF, 4'hF);
        check("full-word RW", expected_word(16'h0000), 32'hDEADBEEF);

        // 2) byte strobe: write only lanes 0 and 2
        axi_ref_reset();
        apply_write_beat(16'h0010, 32'h11223344, 4'b0101);
        check("byte-strobe masking", expected_word(16'h0010), 32'h00220044);

        // 3) narrow transfer: two 1-byte beats into the SAME word
        //    (size=0: addr 0x20 -> lane0, addr 0x21 -> lane1)
        axi_ref_reset();
        apply_write_beat(16'h0020, 32'h000000AA, 4'b0001);  // byte at 0x20
        apply_write_beat(16'h0021, 32'h0000BB00, 4'b0010);  // byte at 0x21
        check("narrow -> same word", expected_word(16'h0020), 32'h0000BBAA);

        // 4) unwritten memory reads back as 0 (matches DUT zero-init)
        axi_ref_reset();
        check("unwritten = 0", expected_word(16'h0100), 32'h00000000);

        if (errors == 0) $display("=== DPI_DEMO_PASS ===");
        else             $display("=== DPI_DEMO_FAIL (%0d) ===", errors);
        $finish;
    end
endmodule
