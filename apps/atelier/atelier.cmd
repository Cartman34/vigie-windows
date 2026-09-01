@echo off
REM @author Florent HAZARD <f.hazard@sowapps.com>
REM Ouvre l atelier de validation Vigie (serveur local php, aucun droit admin).
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0atelier.ps1" %*
if errorlevel 1 pause
