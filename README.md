# win-a2enmod
A PowerShell script for working with modules and sites on the [Apache Web Server][] for Windows. It was inspired by the a2enmod perl script for Debian written by [Stefan Fritsch][]. It employs some similar tactics as the original a2enmod, such as a single script referred to by different names by way of symbolic links. It was written independently with PowerShell as a way to provide a powerful script ideal for the Windows environment that employs the Linux philosophy of tools that do one thing and do it well.

[Apache Web Server]: http://httpd.apache.org/
[Stefan Fritsch]: http://www.sfritsch.de/

## Why not just use XAMPP to manage Apache on Windows?
[XAMPP][] is a wonderful tool for managing your web server, but they don't always support the latest versions of the software
they bundle. For example, XAMPP 1.8.1 only supported httpd 2.4.3 (instead of the most recent stable version at the time, 2.4.4,
which Apache *"recommend over all previous releases"*). They will upgrade these programs in newer versions, but not always to the most recent. Many web admins prefer the latest stable versions and this script lets you use a simple command line program that
offers similar functionality as the Debian utility.

[XAMPP]: http://www.apachefriends.org/en/xampp-windows.html

## Installation
To use the `a2enmod`, `a2dismod`, `a2ensite`, and `a2dissite` commands, make sure to do the following:

* Run CMD.exe as an Administrator
* Navigate to the directory with a2enmod.ps1
* Run setup.bat from the command line to create the symbolic links
* Run Powershell as an Administrator
* Run the command `Set-Executionpolicy Unrestricted -Scope Process -Force` to allow the execution of PowerShell scripts just in the current session
* Make sure httpd.exe is in your path
* Make sure your Windows user account has write access to the ServerRoot directory as assigned in the main Apache config file as it may create directories underneath the ServerRoot.

Be sure to add the directory containing the script and symbolic links to your user or system environment path variable so that you can refer to the commands from anywhere.

## Usage  

  __a2enmod [[-m[od]] \<String\> [[-s[earch]] \<String\>] [-r[eplace]] [-c[opy]] [-n[orestart]]]__
* _mod_ - The module to enable or add
* _search_ - The path to the module.
* _replace_ - Replace the path in the LoadModule line for this module with the file path passed to _search_.
* _copy_ - A new module will be added and the file will be copied to the default modules directory.
* _norestart_ - Don't restart the web server on completion

Locates the specified module and uncomments its LoadModule line to enable it. A new module will be added if a path to a valid file is passed to `-search`. The new LoadModule line will be appended to the long list of enabled and disabled lines that usually comes with Windows Apache. `-copy`. will make a copy in the default modules folder. If `-mod` names a newly added module, it must be the same name specified by the module file. If referring to a module already specifed in the conf, it may be named by either the part before `_module`, the full module name, filename, or basename (filename without extension).
	
  __a2dismod [[-m[od]] \<String\> [-n[orestart]]]__
* _mod_ - The module to disable
* _norestart_ - Don't restart the web server on completion

Adds a comment marker to the LoadModule line of the specified module to disable it.

***********

  __a2ensite [[-m[od]] \<String\> [-c[opy]] [-r[eplace]] [-n[orestart]]]__
* _mod_ - The conf file with a [Virtual Host] block that defines the site. Unless `-copy` is used, this names a basename or filename of a .conf file in ServerRoot\conf\sites-available.
* _copy_ - Copy the configuration file specified by `-mod` to sites-enabled.
* _replace_ - Delete the .conf file of the same name in sites-available.
* _norestart_ - Don't restart the web server on completion

Move or copy the file specified by `-mod` to  ServerRoot\conf\sites-enabled. `-copy` tells the script that `-mod` will name the path to a file instead of naming a conf file already in ServerRoot\conf\sites-available. Use `-replace` to delete the .conf of the same name in sites-available.

[Virtual Host]: http://httpd.apache.org/docs/2.4/vhosts/

  __a2dissite [[-m[od] \<String\> [-a[dd]] [-n[orestart]]]__
* _mod_ - The conf file in sites-enabled to be moved to sites-available
* _add_ - `-mod` will name a path to a file to be moved to sites-available
* _norestart_ - Don't restart the web server on completion

Move the specified site's conf file from ServerRoot\conf\sites-enabled to ServerRoot\conf\sites-available.

## Notes
Whenever the _site_ scripts are run, the line `Include /conf/sites-enabled` will be added to your main conf file and the sites-available and sites-enabled directories will be created if they don't exist. See the file at ServerRoot\conf\extra\httpd-vhosts.conf for an example Virtual Host configuration.

All commands restart the web server on successful completion unless the `-norestart` flag is given.

If you use `-norestart` when overwriting a module with `-copy` option, the script will ask if you’d like to restart the web server in order to overwrite the file. Saying “No” will exit.

The commands without parameters will display info about the modules or sites.


## Examples
	a2enmod
Show information about enabled and disabled modules.

	a2enmod sed
Enable the module whose name is *sed_module*.

	a2enmod ssl_module C:\my\folder\mod_ssl.so -a
Add the line `LoadModule ssl_module "C:\my\folder\mod_ssl.so"` to the main configuration file and restart the web server.

	a2enmod -mod ssl_module -search C:\my\folder\mod_ssl.so -copy
Copy the file passed to `-search` into the default modules folder, and add the line `LoadModule ssl_module "C:\my\folder\mod_ssl.so"` to the main configuration file. The module name for `-mod` must match its definition in the shared object file.

	a2enmod rewrite –n
Uncomment the line `LoadModule rewite_module modules/mod_rewrite.so` from the the main configuration, but don’t restart the web server.

	a2dismod ssl
Disable ssl_module.

***********
	a2ensite
Show information about enabled and disabled sites.

	a2ensite mysite
Enables the site defined in the file ServerRoot\conf\sites-available\mysite.conf.

	a2ensite C:\my\folder\mysite.conf -add
Move the Virtual host configuration defined in C:\my\folder\mysite.conf to ServerRoot\conf\sites-enabled.

	a2ensite C:\my\folder\mysite.conf -c
Copy mysite.conf from the specified folder into sites-enabled, then enable it.

	a2ensite mysite –norestart
Move ServerRoot\conf\sites-available\mysite.conf to ServerRoot\conf\sites-enabled, but don’t restart the web server.

	a2dissite mysite
Disable ServerRoot\conf\sites-enabled\mysite.conf by moving it to sites-available and restarting the web server.

## Screenshots
<img src="http://aninternetpresence.net/github/mod_screenshots.png" style="border:none"/>
<img src="http://aninternetpresence.net/github/site_screenshots.png" style="border:none"/>

## Disclaimer
This is a work in progress. Please feel free to contribute. You will inevitably notice some kinks and oddities in its operation, which I aim to improve. I would really like to get an optional GUI going or something like that, as it would be much nicer to run something to click these options rather than always type them. Please let me know if you have trouble using this, or have any suggestions. Pull requests are more than welcome. Thank you for trying out this project.
