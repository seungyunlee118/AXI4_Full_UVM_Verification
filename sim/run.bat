@echo off
REM =============================================================
REM Week 1 Sanity Test - Questa Run Script
REM Usage: 
REM   run.bat        - batch mode (no GUI)
REM   run.bat gui    - interactive GUI mode with waveforms
REM =============================================================

REM Clean previous run artifacts
if exist work rmdir /s /q work
if exist transcript del transcript
if exist vsim.wlf del vsim.wlf
if exist wlft* del wlft*

REM Create work library
echo === Creating work library ===
vlib work
vmap work work

REM Compile RTL (DUT)
echo === Compiling RTL ===
vlog -sv -lint ^
    +define+SIMULATION ^
    ..\rtl\axi_ram.v
if errorlevel 1 goto :error

REM Compile testbench
echo === Compiling TB ===
vlog -sv -lint ^
    ..\tb\tb_top.sv
if errorlevel 1 goto :error

REM Choose run mode
if "%1" == "gui" goto :gui_mode

REM ---- Batch mode ----
echo === Running simulation (batch mode) ===
vsim -c ^
    -voptargs=+acc ^
    -do "run -all; quit -f" ^
    tb_top
goto :done

REM ---- GUI mode with waveforms ----
:gui_mode
echo === Running simulation (GUI mode) ===
vsim ^
    -voptargs=+acc ^
    -do "add wave -r /tb_top/*; add wave -r /tb_top/dut/*; run -all" ^
    tb_top
goto :done

:error
echo *** Compilation failed ***
exit /b 1

:done
echo === Done ===