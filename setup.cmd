@echo off
REM @author Florent HAZARD <f.hazard@sowapps.com>
REM ---------------------------------------------------------------------------
REM setup.cmd - THE entry point of Vigie. Double-click, and that is all.
REM
REM It does the whole thing: PowerShell 7 for the computer, the Pode module, the
REM local token, the startup task of THIS account, and the launch of the app.
REM
REM The current account must be an ADMINISTRATOR: Vigie holds the Windows Update
REM lock and installs for everyone. We check BEFORE elevating -- without that check
REM Windows would ask for ANOTHER account's credentials, and Vigie would install
REM for that one instead of you.
REM
REM The first pass runs on Windows PowerShell, present everywhere: when installing,
REM pwsh does not necessarily exist yet. install.ps1 switches over by itself.
REM
REM THE ENCODING. This file is UTF-8 WITHOUT BOM, and the terminal code page switches
REM to 65001 on the very first line. Without that, cmd.exe reads the file in the OEM
REM page (850) and an accented letter turns into a symbol -- which is why this text
REM used to be written without accents. The BOM is forbidden here: cmd.exe would print
REM it verbatim before the first line. The code page is not restored on exit: this
REM window was opened for the installation and closes with it.
REM ---------------------------------------------------------------------------
@chcp 65001 >nul
setlocal
title Installation de Vigie
REM THE INSTALL FOLDER CAN BE GIVEN AS AN ARGUMENT: setup.cmd "D:\Outils\Vigie".
REM Without one, the announcement window offers the default and lets another be chosen.
set "VIGIE_PATH=%~1"
set "VIGIE_SELF=%~f0"
REM THE WINDOW OPENS LARGE ENOUGH FOR WHAT IT SHOWS.
REM
REM By default cmd.exe opens 80 columns: paths and archive lines are cut there, and the
REM installation scrolls through a porthole. 120 columns by 45 lines hold the run without
REM wrapping, and stay under the size of an ordinary screen.
mode con: cols=120 lines=45 >nul 2>&1

REM WINDOWS TOOLS ARE CALLED BY THEIR FULL PATH.
REM
REM whoami and find ALSO exist in Git Bash, MSYS and Cygwin -- and if one of those leads
REM the PATH, it is the one that answers. Measured on 31/08: setup.cmd launched from a
REM Git terminal answered "whoami: extra operand '/groups'", then "this account is not an
REM administrator" to an account that is one. A rights check that calls the wrong program
REM is worse than no check at all.
"%SystemRoot%\System32\whoami.exe" /groups | "%SystemRoot%\System32\find.exe" "S-1-5-32-544" >nul 2>&1
if errorlevel 1 goto :pasadmin

"%SystemRoot%\System32\net.exe" session >nul 2>&1
if not errorlevel 1 goto :installe

REM WE SAY WHAT WE ARE ABOUT TO DO, BEFORE Windows asks for the elevation. The window is
REM carried by Windows PowerShell 5.1, present everywhere: at this instant pwsh is not
REM necessarily installed -- it is precisely one of the things we are about to put in.
REM
REM Code 0 = the user continues; anything else = a refusal, or the display failed.
echo.
echo L'installation de Vigie demande des droits supplémentaires.
echo Une fenêtre va expliquer ce qui sera fait, avant toute modification.
REM THE WINDOW WRITES THE RETAINED FOLDER TO A FILE: its standard output already carries its
REM own layout checks, and we would have read something other than a path there.
set "VIGIE_REPONSE=%TEMP%\vigie-install-path.txt"
if exist "%VIGIE_REPONSE%" del /q "%VIGIE_REPONSE%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lib\show-confirm.ps1" -Scenario installation -InstallPath "%VIGIE_PATH%" -OutFile "%VIGIE_REPONSE%"
if errorlevel 1 goto :refus
if exist "%VIGIE_REPONSE%" set /p VIGIE_PATH=<"%VIGIE_REPONSE%"
if exist "%VIGIE_REPONSE%" del /q "%VIGIE_REPONSE%" >nul 2>&1

echo Vigie a besoin des droits administrateur.
echo Une fenêtre de confirmation Windows va s'ouvrir.
REM THE ARGUMENT MUST CROSS THE ELEVATION. Start-Process relaunches this file in a NEW
REM console: without passing it on, the chosen folder would be forgotten between the two
REM windows. PowerShell quotes the path, reading it from the environment: cmd stays out of it,
REM its quoting rules being one more trap (D116).
powershell -NoProfile -Command "$chemin = $env:VIGIE_PATH; $args2 = @(); if ($chemin) { $args2 = @(('\"' + $chemin.TrimEnd('\') + '\"')) }; Start-Process -FilePath $env:VIGIE_SELF -Verb RunAs -ArgumentList $args2"
exit /b

:refus
echo.
echo Installation annulée. Rien n'a été modifié sur cette machine.
echo.
pause
exit /b 3

:installe
REM NO BANNER HERE. The script owns the display end to end; an extra title, in another
REM style, gave two layouts on the same screen.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" -InstallPath "%VIGIE_PATH%"
REM THE RESULT IS READ: announcing "Done" after a failure is worse than staying silent.
if errorlevel 1 goto :echec
REM NO DOUBLE CONCLUSION, AND NO "PRESS ANY KEY".
REM
REM The installation ends with a WINDOW that says what was done: it waits for the click,
REM so the console no longer needs to hold the user back. An installation started by a
REM double-click must end like an application, not like a script.
REM
REM On failure, however, the "pause" of the :echec block stays -- that is exactly where
REM the screen must be readable before it disappears.
exit /b 0

:pasadmin
echo.
echo Ce compte Windows n'est pas administrateur.
echo Vigie s'installe pour le compte qui lance ce setup, et ce compte doit être
echo administrateur : elle tient le verrou de Windows Update et installe
echo PowerShell 7 pour toute la machine.
echo.
echo Ouvrez une session administrateur, puis relancez ce fichier.
echo.
pause
exit /b 1

:echec
REM NO "PRESS ANY KEY": THE WINDOW HAS ALREADY CONCLUDED.
REM
REM This "pause" dated from the time when a failure was only said in the console. Since
REM then the installation ends with a window -- success AS WELL AS failure -- naming the
REM cause and giving the log. One closed that window only to face a terminal still
REM waiting for a key (measured on 01/09).
echo.
echo L'installation a ÉCHOUÉ. Journal détaillé : apps\backend-pode\var\log\install_*.log
exit /b 1