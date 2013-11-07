[CmdletBinding()]
Param(
    [Parameter(Position=1)]
    [string]$mod,
    [Parameter(Position=2)]
    [string]$search = $pwd,
    [alias("a")]
    [switch]$add,
    [switch]$norestart
)


$ErrorActionPreference = "stop"

# Find out which command was called
if($MyInvocation.InvocationName -match "a2(en|dis)(mod|site)"){
    $act = $matches[1]
    $obj = $matches[2]
} else {
    write-host $MyInvocation.InvocationName " call not recognized"
}

$run_cfg = httpd -D DUMP_RUN_CFG

# Value of ServerRoot will be surrounded by quotes, so only group the actual pathname
# which will be available in $matches[1]
$run_cfg[0] -match "ServerRoot: \W(.*)\W" | out-null

$ServerRoot = $matches[1]

# The modules directory is assumed to be in the "modules" folder underneath ServerRoot
$mod_dir = $ServerRoot + "\modules"

# Find the main configuration file
httpd -V | foreach{
    if($_ -match "-D SERVER_CONFIG_FILE=\W(.*)\W"){
        $conf = $ServerRoot + "\" + $matches[1]
    }
}

if(!(get-item $conf)){ 
    write-host -foregroundcolor RED -backgroundcolor BLACK "httpd configuration file could not be found"
    exit 
} else {
    $conf = get-item $conf
    $conf_dir = $conf.directory
}


# Verify the existence of the required directories
try{
    # Default module dirctory
    $lookup_dir = $mod_dir
    $mod_dir = get-item $mod_dir
    
    # The current directory is the default search directory
    $lookup_dir = $search
    $search_dir = get-item $search
    
}
catch [System.Exception] {
    switch($_.Exception.GetType().FullName) {
        'System.Management.Automation.ItemNotFoundException' {
            write-host -foregroundcolor RED -backgroundcolor BLACK "`"$lookup_dir`" not found"
         }
        'System.IO.IOException' {
            write-host -foregroundcolor RED -backgroundcolor BLACK "Could not read `"$lookup_dir`""
        }
    }
    exit           
}

Function makeSiteDirs{
    # Create the site directories if they are not already present
    if(!$conf_dir.getdirectories("sites-enabled")){
        $conf_dir.createsubdirectory("sites-enabled")
    }
        
    if(!$conf_dir.getdirectories("sites-available")){
        $conf_dir.createsubdirectory("sites-available")
    }  
}

Function includeSiteDir{
    # Add the Include line for enabled sites to the main config if it isn't already there
    $includeline = "Include $($conf_dir.name)/sites-enabled/"
    (get-content $conf) | foreach { 
        if($_.contains($includeline)){
            $hasline = $true
        }            
    }
        
    if(!$hasline){
        write-host -foregroundcolor GREEN "Adding site directories to config..."
        $includeline = "`n" + $includeline
        add-content $conf $includeline
    }
}

# If $mod was not initalized, assume the user just wanted to view information
if(!$mod){
    switch($obj){
        'mod'{
            # Enabled mods: Show the output of httpd -M
            httpd -M | write-host -foregroundcolor green -separator "`n"

            "============================"
            write-host ""

            # Disabled mods: Find the names of the modules with a commented LoadModule line in the main config
            $dismodlist = @()
           (get-content $conf) | foreach {
                if($_ -match "#LoadModule (.*)\s"){
                 $dismodlist += " " + $matches[1]
                }
            }

            write-host "Disabled Modules:" -foregroundcolor yellow
            write-host -foregroundcolor yellow $dismodlist -separator "`n"            

        }
        'site'{
            # Get the conf directory
            $conf_dir = $conf.directory

            includeSiteDir

            # Ask the user to add site configurations to the folders if they were just now made
            if(!$conf_dir.getdirectories("sites-available") -or !$conf_dir.getdirectories("sites-enabled")){
                 makeSiteDirs
                 write-host -foregroundcolor yellow "Site directories created. Please make a .conf file based on $conf_dir\extra\httpd-vhosts.conf and add it with `"a2ensite [file]`"."
                 exit
            } else {
                $sitesavailable = $conf_dir.getdirectories("sites-available")[0]
            }
            
            # Enabled sites: Show the output of httpd -D DUMP_VHOSTS
            $ensitelist = httpd -D DUMP_VHOSTS
            write-host -foregroundcolor green $ensitelist -separator "`n"
            "============================"

            # Enabled sites: Show the files in conf\sites-available
            write-host -foregroundcolor yellow "Disabled Sites:"
            $sitesavailable.getfiles() | write-host -foregroundcolor yellow -separator "`n"
        }
    }
    exit
}

# $mod_dir, $conf, and $search_dir should be available
switch($obj){
    'mod'{
        # Get just the basename of the module, expecting the possible extension .so
        $mod = $mod.replace(".so","")
        
        # Find out the name of the module as it would appear in httpd -M
        if($mod.startswith("mod_")){
            $basename = $mod
            $sub = $mod.trimstart("mod_");
        } else {
            $basename = "mod_" + $mod
            $sub = $mod
        }
        
        # Make a version that also has the extension
        $modfilename = $basename + ".so"
        
        # How it will appear in httpd -M
        $modname = $sub + "_module"    
        
        # See if the module is already enabled if not adding a new one
        
        httpd -M | foreach{
            if($_ -match "\b(.*)_module" -and $matches[0] -eq $modname){
                 $modfound = $true
                 if(!$add){
                     if($act -eq 'en'){
                        write-host -foregroundcolor GREEN "Module already enabled"
                        exit
                     } else { # Show this for Disable Module
                        write-host -foregroundcolor GREEN "Module found"
                     }
                 }
            }
        }
        
        # The actual function for enabling or disabling the module    
        Function toggleModule{
            (get-content $conf) | foreach { 
                $_ -match "LoadModule .*modules/($basename).so" | out-null
                $line = "#" + $matches[0]
        
                # Exit the script if the user is turning off an already disabled module
                if($act -eq 'en'){
                    $action = 'enabled'
                    $_.replace($line, $matches[0])
                }else {
                    $action = 'disabled'
                    $_.replace($matches[0], $line)
                }        
            } | set-content $conf
    
            write-host -foregroundcolor GREEN "Module $action" 
        }

        # This is for Disable Module. If it's not returned by httpd -M, tell the user it's not enabled.
        if($act -eq 'dis' -and !$modfound){
            write-host -foregroundcolor RED -backgroundcolor BLACK "$mod not enabled"
            exit
        }
        
        switch($act){
            'en'{ # Enable/Add Module
                # Don't look in the default location if the $add switch is on
                # This allows the user to explicitly overwrite a module of the same name
                $foundModule = $mod_dir.getfiles($modfilename)
                
                if(!$add){ 
                    write-host -foregroundcolor YELLOW "Looking in $($mod_dir.fullname) for $mod"
                        
                    if($foundModule){
                        $foundModule = $foundModule[0]
                        write-host -foregroundcolor GREEN "Module found"
                    }
                } else {
                    # This is just for the overwrite notice if $add is on
                    $foundModule = $null
                }

                # The module either wasn't found or wasn't searched for in the default location
                if(!$foundModule){                    
                    # See if the module is in either the current directory or the specified one
                    write-host -foregroundcolor YELLOW "Looking in $($search_dir.fullname) for $mod"
                    
                    $foundModule = $search_dir.getfiles($modfilename)
                    if($foundModule){                    
                        $foundModule = $foundModule[0]
                        write-host -foregroundcolor GREEN "Module found"
                        # Since it's not in the modules directory, it will need to be copied to there
                        $add = $True
                    } else {
                        # If the module still can't be found, let the user know
                        write-host -foregroundcolor RED -backgroundcolor BLACK "Module not found"
                        exit
                    }         
                }

                # The module was located
                # See if the module needs to be copied to $mod_dir
                if($add){
                    <# 
                    If the user wishes to overwrite an existing module file with a new one, the web server
                    must be restarted.
                    #>
                    if($modfound -and $norestart){
                        $title = "Web Server Restart Required"
                        $message = "There is already a $modfilename in $mod_dir. Restart the web server and overwrite it?"

                        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
                            "Overwrites $mod_dir\$modfilename with $($foundModule.fullname)"

                        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
                            "Immediately exits the script"

                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

                        $result = $host.ui.PromptForChoice($title, $message, $options, 0) 

                        if($result -eq 1) { "Exiting"; exit }
                    
                    
                    }
                    # Turn off the server so that the module can be replaced if a file of the same name already exists
                    write-host -foregroundcolor YELLOW "Copying module..."
                    
                    if($modfound){
                        # Any non redirected errors in PowerShell 3 will be treated as terminating errors
                        $ErrorActionPreference = "silentlycontinue"
                        write-host -foregroundcolor YELLOW "Stopping Apache service..."
                        httpd -k stop
                        $ErrorActionPreference = "stop"
                    }
                    copy $foundmodule.fullname $mod_dir
                    "$mod was copied to $mod_dir"
                }

                # Enable the module in httpd.conf
                toggleModule $basename $conf
                
                break # End of Enable Module
            }
            'dis'{ # Disable Module
                toggleModule $basename $conf
                
                break # End of Disable Module
            }
        }
        break # End of Module
    }
    'site'{
        makeSiteDirs     
          
        # Get DirectoryInfo object references for the site directories
        $sitesenabled = $conf_dir.getdirectories("sites-enabled")
        $sitesenabled = $sitesenabled[0]
        
        $sitesavailable = $conf_dir.getdirectories("sites-available")
        $sitesavailable = $sitesavailable[0]
        
        # Let the user refer to the file either by the basename or file name
        if(!$mod.contains(".conf")){ $mod = $mod + ".conf"}
        
        includeSiteDir
        
        # Enable or disable the site specified in $mod
        Function toggleSite {
        Param(
            [alias("s")]
            [switch]$search
        )
            
            if($search){
                $location = $search_dir
            } else {
                if($act -eq 'en'){
                    $location = $sitesavailable
                } else {
                    $location = $sitesenabled
                }    
            }            
            
            write-host -foregroundcolor YELLOW "Checking $location..."
            $site = $location.getfiles($mod)
            if($site){
                if($act -eq 'en'){
                    # Move over the new site if the source location is sites-available. Otherwise, copy it over
                    if(!(compare-object $location $sitesavailable)){ # compare-object returns false if there's no difference between operands
                        move-item $site[0].fullname $sitesenabled.fullname    
                    } else {
                        copy-item $site[0].fullname $sitesenabled.fullname
                    }                    
                } else {
                    move-item $site[0].fullname $sitesavailable.fullname
                }
                return $true
            } else {
               return $false 
            }
        }

        switch($act){
            'en'{ # Enable Site
                if(!$add){                    
                    # See if the site is already enabled          
                    if($sitesenabled.getfiles($mod)){
                        write-host -foregroundcolor GREEN "$mod is already enabled"
                        exit
                    }

                    # See if it is in sites-available
                    $result = toggleSite

                    if(!$result){
                        $result = toggleSite -s
                    }
                } else {                    
                    # Check if there's already a site of the same name in sites-available
                    $oldsite = $sitesavailable.getfiles($mod)
                            
                    if($oldsite){
                        $title = "Delete $mod in sites-available?"
                        $message = "There is a $mod in sites-available. Would you like to remove it?"

                        $yes = new-object System.Management.Automation.Host.ChoiceDescription "&Yes", `
                            "Copies $search_dir\$mod to $sitesavailable and removes $oldsite[0]"

                        $no = new-object System.Management.Automation.Host.ChoiceDescription "&No", `
                            "Immediately exits the script"

                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

                        $choiceresult = $host.ui.PromptForChoice($title, $message, $options, 0)

                        # Exit if they don't wish to overwrite the similarly named file in sites-available
                        if($choiceresult -eq 1){
                            "Exiting"; exit
                        } else {
                            remove-item $oldsite[0].fullname
                        }
                    }

                    $result = toggleSite -s
                }

                # At this point, either the site was found or it wasn't
                if($result){
                    write-host -foregroundcolor GREEN "$mod enabled"
                } else {
                    write-host -foregroundcolor RED -backgroundcolor BLACK "$mod was not found"
                    exit
                }
                    
                break
             } # End of Enable Site
            
            
            'dis'{ # Disable Site
                $result = toggleSite
                if($result){
                    write-host -foregroundcolor GREEN "$mod disabled"
                } else {
                    write-host -foregroundcolor RED -backgroundcolor BLACK "$mod is not enabled"
                    exit
                }
            }
        } # End of Site
    } 
}

<# 
Since "httpd -t" sends output to the error stream, even on success,
silently continue on errors until the end of the script.
#>
$ErrorActionPreference = "silentlycontinue"
# Check the main config file for syntax errors
httpd -t 2> $null

if($error[0].tostring() -eq "Syntax OK"){    
    if(!$norestart -or $modenabled){
        # Restart the webserver
        write-host -foregroundcolor GREEN "Syntax OK. Restarting Server..."
        httpd -k restart
        
        write-host -foregroundcolor GREEN "Server Restarted"
    }
}else {
    write-host -foregroundcolor RED -backgroundcolor BLACK $error[0].tostring()
}
