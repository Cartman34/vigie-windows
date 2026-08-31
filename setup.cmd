@echo off
REM ---------------------------------------------------------------------------
REM setup.cmd - LE point d'entrée de Vigie. Double-clic, et c'est tout.
REM
REM Il fait la totalité : PowerShell 7 pour la machine, le module Pode, le jeton
REM local, la tâche de démarrage de CE compte, et le lancement de l'application.
REM
REM Le compte courant doit être ADMINISTRATEUR : Vigie tient le verrou de Windows
REM Update et installe pour toute la machine. On le vérifie AVANT d'élever -- sans
REM ce contrôle, Windows demanderait les identifiants d'un AUTRE compte et Vigie
REM s'installerait pour celui-là, pas pour vous.
REM
REM La première passe se fait avec Windows PowerShell, présent partout : quand on
REM installe, pwsh n'existe pas forcément encore. install.ps1 bascule tout seul.
REM
REM L'ENCODAGE. Ce fichier est en UTF-8 SANS BOM, et la page de code du terminal est
REM basculée en 65001 dès la première ligne. Sans cela, cmd.exe lit le fichier dans la
REM page OEM (850) et « é » devient un symbole : c'est pourquoi ce texte était écrit
REM sans accents. Le BOM, lui, est interdit ici -- cmd.exe l'afficherait tel quel avant
REM la première ligne. La page de code n'est pas restaurée en sortant : cette fenêtre
REM est ouverte pour l'installation et se referme avec elle.
REM ---------------------------------------------------------------------------
@chcp 65001 >nul
setlocal
title Installation de Vigie

REM LES OUTILS DE WINDOWS S'APPELLENT PAR LEUR CHEMIN COMPLET.
REM
REM « whoami » et « find » existent AUSSI dans Git Bash, MSYS, Cygwin -- et si l'un de
REM ceux-la est en tete du PATH, c'est lui qui repond. Constate le 31/08 : setup.cmd
REM lance depuis un terminal Git a repondu « whoami: extra operand '/groups' », puis
REM « ce compte n'est pas administrateur » a un compte qui l'est. Un controle de droits
REM qui se trompe de programme est pire que pas de controle.
"%SystemRoot%\System32\whoami.exe" /groups | "%SystemRoot%\System32\find.exe" "S-1-5-32-544" >nul 2>&1
if errorlevel 1 goto :pasadmin

"%SystemRoot%\System32\net.exe" session >nul 2>&1
if not errorlevel 1 goto :installe

REM ON DIT CE QU'ON VA FAIRE, AVANT que Windows ne demande l'élévation. La fenêtre est
REM portée par Windows PowerShell 5.1, présent partout : à cet instant, pwsh n'est pas
REM forcément installé -- c'est justement une des choses qu'on s'apprête à poser.
REM
REM Code 0 = l'utilisateur continue ; tout le reste = il refuse, ou l'affichage a échoué.
echo.
echo L'installation de Vigie demande des droits supplémentaires.
echo Une fenêtre va expliquer ce qui sera fait, avant toute modification.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\lib\show-confirm.ps1" -Scenario installation
if errorlevel 1 goto :refus

echo Vigie a besoin des droits administrateur.
echo Une fenêtre de confirmation Windows va s'ouvrir.
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b

:refus
echo.
echo Installation annulée. Rien n'a été modifié sur cette machine.
echo.
pause
exit /b 3

:installe
REM PAS DE BANDEAU ICI. Le script tient l'affichage de bout en bout ; un titre ecrit
REM en plus, dans un autre style, donnait deux mises en page sur le meme ecran.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"
REM LE RÉSULTAT SE LIT : annoncer « Terminé » après un échec est pire que se taire.
if errorlevel 1 goto :echec
REM PAS DE CONCLUSION EN DOUBLE, ET PAS DE « APPUYEZ SUR UNE TOUCHE ».
REM
REM L'installation se termine par une FENETRE qui dit ce qui a ete fait : elle attend le
REM clic, donc la console n'a plus besoin de retenir l'utilisateur. Une installation
REM lancee au double-clic doit se conclure comme une application, pas comme un script.
REM
REM En cas d'echec, en revanche, le « pause » du bloc :echec reste -- c'est justement la
REM qu'il faut pouvoir lire l'ecran avant qu'il ne disparaisse.
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
echo.
echo L'installation a ÉCHOUÉ. Les lignes ci-dessus nomment la cause.
echo Journal détaillé : apps\backend-pode\var\log\install_*.log
echo.
pause
exit /b 1
