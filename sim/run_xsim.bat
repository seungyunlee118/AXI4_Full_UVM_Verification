@echo off
REM =============================================================
REM Vivado XSim Run Script  (primary simulator for this project)
REM
REM Usage:
REM   run_xsim.bat                 - default test (axi4_base_test), batch
REM   run_xsim.bat gui             - default test, XSim GUI + waveforms
REM   run_xsim.bat <TESTNAME>      - run a specific UVM test, batch
REM   run_xsim.bat <TESTNAME> gui  - run a specific UVM test in the GUI
REM
REM Tests: axi4_base_test (write+readback), axi4_write_test,
REM        axi4_read_test, axi4_rand_test
REM
REM Requires Vivado on PATH (xvlog / xelab / xsim). Run once per shell:
REM   call "C:\AMDDesignTools\2026.1\Vivado\settings64.bat"
REM
REM License: the node-locked .lic must sit at the default location
REM   C:\Users\<user>\.Xilinx\Xilinx.lic
REM (no XILINXD_LICENSE_FILE env var needed once it is there).
REM =============================================================
setlocal

REM ---- Pick test name + GUI flag from the two optional args ----
set "TEST=axi4_base_test"
set "GUI="
if /I "%~1"=="gui" (set "GUI=1") else if not "%~1"=="" (set "TEST=%~1")
if /I "%~2"=="gui" set "GUI=1"

REM ---- Clean previous run artifacts ----
if exist xsim.dir rmdir /s /q xsim.dir
if exist .Xil      rmdir /s /q .Xil
del /q *.jou *.log *.pb *.wdb 2>nul

REM ---- Compile (xvlog): -L uvm links the built-in UVM library,
REM      -i adds the include dir for the class .svh files ----
REM NOTE: xvlog/xelab/xsim are .bat files - they MUST be invoked with
REM "call", otherwise control never returns to this script.
echo === Compiling (xvlog) ===
call xvlog --sv -L uvm -i ..\tb\uvm ^
    ..\rtl\axi_ram.v ^
    ..\tb\axi4_if.sv ^
    ..\tb\axi4_pkg.sv ^
    ..\tb\tb_top.sv
if errorlevel 1 goto :error

REM ---- Elaborate (xelab) ----
REM --cov_db_* saves the functional-coverage database per test, so several
REM tests can later be merged into one report by cov_report.bat.
echo === Elaborating (xelab) ===
call xelab -debug typical -L uvm -timescale 1ns/1ps ^
    --cov_db_dir . --cov_db_name %TEST% ^
    tb_top -s tb_top_sim
if errorlevel 1 goto :error

REM ---- Simulate ----
if defined GUI goto :gui_mode

echo === Simulating %TEST% (batch) ===
call xsim tb_top_sim -runall -testplusarg "UVM_TESTNAME=%TEST%"
goto :done

:gui_mode
REM wave.tcl adds the signals to the wave window and THEN runs, because
REM XSim only records signals that were added before the run started.
echo === Simulating %TEST% (GUI) ===
call xsim tb_top_sim -gui -tclbatch wave.tcl -testplusarg "UVM_TESTNAME=%TEST%"
goto :done

:error
echo *** Build failed ***
exit /b 1

:done
echo === Done ===
endlocal
