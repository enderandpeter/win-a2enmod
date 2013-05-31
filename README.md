# win-a2enmod
A PowerShell script for working with modules and sites on the [Apache Web Server][] for Windows. It was inspired by the a2enmod perl script for Debian written by Stefan Fritsch. It employs some similar tactics as the original a2enmod, such as a single script referred to by different names by way of symbolic links, but it was written independently and specifically for PowerShell as a way to provide a powerful script ideal for the Windows environment that employs the Linux philosophy of tools that do one thing and do it well.

[Apache Web Server]: http://httpd.apache.org/

## Why not just use XAMPP to manage Apache on Windows?
[XAMPP][] is a wonderful tool for managing your web server, but they don't always support the latest versions of the software they bundle. At the moment, XAMPP 1.8.1 only supports Apache 2.4.3 (instead of the most recent stable version 2.4.4, which they *"recommend over all previous releases"*) and PHP 5.4.7 (not yet the current 5.4.15). Many web admins prefer the latest stable versions and this script lets you use a simple command line program that offers the same functionality as the Debian utility.

[XAMPP]: http://www.apachefriends.org/en/xampp-windows.html

## Installation
To use the `a2enmod`, `a2dismod`, `a2ensite`, and `a2dissite` commands, make sure to do the following:

* Run CMD.exe as an Administrator
* Navigate to the directory with a2enmod.ps1
* Run setup.bat from the command line to create the symbolic links and the .gitignore
* Run Powershell as an Administrator
* Run the command `set-executionpolicy unrestricted -scope process` to allow the execution of PowerShell scripts just in the current session
* Make sure httpd.exe is in your path
* Make sure your Windows user account has full access to the ServerRoot directory as assigned in the main Apache config file

You will find it easiest to add the directory containing the script and symbolic links to your path so that you can refer to the commands directly by name rather than always saying `.\a2enmod`, for example.

## Usage  

  __a2enmod [-mod] \<String\> [-search] \<String\> [-a[dd]] [-norestart]__
* _mod_ - The module to enable or add
* _search_ - The location in which to look for the module file if not found in the default directory (ServerRoot\modules)
* _add_ - Force script to copy the module file from the search location to the default directory
* _norestart_ - Don't restart the web server on completion

Locates the specified module and uncomments its LoadModule line to enable it. If the module is not in ServerRoot\modules, the script looks in _location_ or the current directory for the module. `-add` will force the script to either find the file in the current or specified location or fail.
	
  __a2dismod [-mod] \<String\> [-norestart]__
* _mod_ - The module to add
* _norestart_ - Don't restart the web server on completion

Adds a comment marker to the LoadModule line of the specified module to disable it.

***********

  __a2ensite [-mod] \<String\> [-search] \<String\> [-a[dd]] [-norestart]__
* _mod_ - The conf file with a [Virtual Host] block that defines the site. Moved to sites-enabled (default directory) if not already there.
* _search_ - The location in which to look for the conf file if not found in the default directory
* _add_ - Force script to move the site conf file from the location to the default directory
* _norestart_ - Don't restart the web server on completion

Move the specified site's conf file to ServerRoot\conf\sites-enabled from either _location_ or the current directory if not found in ServerRoot\conf\sites-available. `-add` will force the script to either find the file in the current or specified location or fail.


[Virtual Host]: http://httpd.apache.org/docs/2.4/vhosts/

  __a2dismod [-mod] \<String\> [-norestart]__
* _mod_ - The conf file to move to sites-disabled
* _-norestart_ - Don't restart the web server on completion

Move the specified site's conf file to ServerRoot\conf\sites-available from ServerRoot\conf\sites-enabled.

## Notes
Module and site names can only refer to files of type `.so` or `.conf`, respectively, and may be specified by either their basename or filename with extension. Additionally, modules can be referred to by the part of their name following the prefix “mod_”.

The line `Include /conf/sites-enabled` will be added to your main conf file and the /conf/sites-available and /conf/sites-enabled directories will be created if they don't already exist. See the file at ServerRoot\conf\extra\httpd-vhosts.conf for an example Virtual Host configuration.

All commands restart the web server on successful completion unless the `-norestart` flag is given.

a2enmod will not create a `LoadModule` line for new modules added with `-add`.

If you use `-norestart` when overwriting an enabled module with the `-add` option, the script will ask if you’d like to restart the web server in order to overwrite the file. Saying “No” will exit.


## Examples
	a2enmod ssl
Enable the mod_ssl.so module. If it’s not in the default modules folder, look for it in the current directory and copy it to the modules folder.

	a2enmod mod_ssl C:\my\folder
Enable the mod_ssl.so module, first looking for it in the default modules folder and then in `C:\my\folder`. If it’s in the specified folder, copy it to the default modules folder before enabling it.

	a2enmod mod_ssl.so C:\my\folder –a
Copy the mod_ssl.so module from the specified folder into the default modules folder, then enable it.

	a2enmod ssl –norestart
Enable the mod_ssl.so module, but don’t restart the web server.

	a2dismod ssl
Disable the mod_ssl.so module.

***********
	
	a2ensite mysite
Enables the site defined in the file mysite.conf. If it’s not in the sites-available folder, look for it in the current directory and move it to the sites-enabled folder.

	a2ensite mysite.conf C:\my\folder
Enable the mysite.conf site, first looking for the file in sites-available and then in `C:\my\folder`. If it’s in the specified folder, copy it to the default modules folder before enabling it.

	a2ensite mysite C:\my\folder –add
Copy the mysite.conf from the specified folder into sites-enabled, then enable it.

	a2ensite mysite –norestart
Enable the site in mysite.conf, but don’t restart the web server.

	a2dissite mysite
Disable the mysite.conf site.

## Screenshot
<img src="http://aninternetpresence.net/github/win_a2en_usage.PNG" style="border:none"/>

## Disclaimer
This is a work in progress. Please feel free to contribute. You will inevitably notice some kinks and oddities in its operation, which I aim to improve. I would really like to get an optional GUI going or something like that, as it would be much nicer to run something to click these options rather than always type them. Please let me know if you have trouble using this, or have any suggestions. Thank you for trying out this project.
