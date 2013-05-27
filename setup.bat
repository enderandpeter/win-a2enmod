@echo off
mklink "a2dismod.ps1" "a2enmod.ps1"
mklink a2ensite.ps1 a2enmod.ps1
mklink a2dissite.ps1 a2enmod.ps1

(
  Echo .*
  Echo a2dismod.ps1
  Echo a2ensite.ps1
  Echo a2dissite.ps1
) > .gitignore

if %ERRORLEVEL% gtr 0 (
	echo An error occurred
) else (
	echo win-a2enmod commands ready to use.
)
timeout 5
