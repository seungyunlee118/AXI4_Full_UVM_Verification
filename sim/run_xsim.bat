@echo off
REM =============================================================
REM Vivado XSim Run Script  (primary simulator for this project)
REM Usage:
REM   run_xsim.bat        - batch mode (no GUI)
REM   run_xsim.bat gui    - open the XSim GUI with waveforms
REM
REM Requires Vivado on PATH (xvlog / xelab / xsim). Install the
REM free AMD Vivado (Standard / ML Standard) edition, then run
REM Vivado's settings64.bat once per shell, e.g.:
REM   call "C:\Xilinx\Vivado\<ver>\settings64.bat"
REM =============================================================

REM ---- Clean previous run artifacts ----
if exist xsim.dir rmdir /s /q xsim.dir
if exist .Xil      rmdir /s /q .Xil
del /q *.jou *.log *.pb *.wdb 2>nul

REM ---- Compile (xvlog): package before files that import it ----
echo === Compiling (xvlog) ===
xvlog --sv ^
    ..\rtl\axi_ram.v ^
    ..\tb\axi4_pkg.sv ^
    ..\tb\axi4_if.sv ^
    ..\tb\tb_top.sv
if errorlevel 1 goto :error

REM ---- Elaborate (xelab) ----
echo === Elaborating (xelab) ===
xelab -debug typical -timescale 1ns/1ps tb_top -s tb_top_sim
if errorlevel 1 goto :error

REM ---- Choose run mode ----
if "%1" == "gui" goto :gui_mode

echo === Simulating (xsim batch) ===
xsim tb_top_sim -runall
goto :done

:gui_mode
echo === Simulating (xsim GUI) ===
xsim tb_top_sim -gui
goto :done

:error
echo *** Build failed ***
exit /b 1

:done
echo === Done ===
