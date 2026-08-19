@echo off
REM =============================================================
REM Merged functional-coverage report via xcrg
REM
REM  *** REQUIRES A VIVADO "PRO" LICENSE TIER ***
REM  On the free BASIC tier xcrg refuses to run:
REM    "The Vivado Simulator license tier, BASIC, does not meet the
REM     requirement to run xcrg ... Please upgrade to a PRO license."
REM
REM  Coverage COLLECTION works fine on BASIC — the testbench prints a
REM  per-coverpoint report itself (axi4_coverage::coverage_report(),
REM  built on the SystemVerilog coverage API). That is the primary
REM  reporting path for this project; this script is only useful if
REM  you have a PRO/Enterprise license.
REM
REM Usage (with a PRO license):
REM   run_xsim.bat axi4_cov_test
REM   run_xsim.bat axi4_directed_test
REM   cov_report.bat            -> cov_report\ (html + text, merged)
REM =============================================================

if exist cov_report rmdir /s /q cov_report

echo === Generating merged coverage report (needs PRO license) ===
call xcrg -cov_db_dir . -report_dir cov_report -report_format all
if errorlevel 1 goto :error

echo.
echo === Report written to cov_report\ ===
goto :done

:error
echo.
echo *** xcrg failed - most likely the BASIC license tier. ***
echo *** Use the testbench's built-in coverage report instead:  ***
echo ***   run_xsim.bat axi4_cov_test   (see the [COV] section) ***
exit /b 1

:done
