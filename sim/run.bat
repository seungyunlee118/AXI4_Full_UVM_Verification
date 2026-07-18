@echo off
REM =============================================================
REM Questa Run Script  (SECONDARY — see run_xsim.bat for the main flow)
REM
REM The installed Questa is the free FPGA Starter Edition, which has
REM NO svverification license: it can COMPILE the UVM testbench (handy
REM as a fast syntax check) but CANNOT run randomize()/UVM. Use XSim
REM (run_xsim.bat) to actually simulate. With a verification-licensed
REM Questa, the vsim step below runs the UVM test normally.
REM
REM Usage:
REM   run.bat          - compile-only syntax check (default, works on Starter)
REM   run.bat run      - also attempt vsim (needs a verification license)
REM   run.bat gui      - attempt vsim in the GUI (needs a license)
REM =============================================================

REM Clean previous run artifacts
if exist work rmdir /s /q work
if exist transcript del transcript
if exist vsim.wlf del vsim.wlf
if exist wlft* del wlft*

echo === Creating work library ===
vlib work
vmap work work

REM ---- Compile order: RTL, interface, package (UVM), top ----
echo === Compiling RTL ===
vlog -sv -lint +define+SIMULATION ..\rtl\axi_ram.v
if errorlevel 1 goto :error

echo === Compiling interface ===
vlog -sv -lint ..\tb\axi4_if.sv
if errorlevel 1 goto :error

REM Package imports uvm_pkg (Questa built-in) and includes the UVM
REM classes from ..\tb\uvm ; the +incdir points the `include search there.
echo === Compiling UVM package ===
vlog -sv +incdir+..\tb\uvm ..\tb\axi4_pkg.sv
if errorlevel 1 goto :error

echo === Compiling TB top ===
vlog -sv ..\tb\tb_top.sv
if errorlevel 1 goto :error

echo === Compile OK ===

REM ---- Run only if explicitly asked (needs a verification license) ----
if "%1" == "run" goto :run_batch
if "%1" == "gui" goto :run_gui
echo (compile-only; pass "run" or "gui" to simulate with a licensed Questa)
goto :done

:run_batch
echo === Running simulation (batch mode) ===
vsim -c -voptargs=+acc -do "run -all; quit -f" tb_top
goto :done

:run_gui
echo === Running simulation (GUI mode) ===
vsim -voptargs=+acc ^
    -do "add wave -r /tb_top/*; run -all" ^
    tb_top
goto :done

:error
echo *** Compilation failed ***
exit /b 1

:done
echo === Done ===
