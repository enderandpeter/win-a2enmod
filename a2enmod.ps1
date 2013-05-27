[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$mod,
    [Parameter(Position=2)]
    [string]$search,
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
    write-host $MyInvocation.InvocationName "call not recognized"
}

$run_cfg = httpd -D DUMP_RUN_CFG

# Value of ServerRoot will be surrounded by quotes, so only group the actual pathname
# which will be available in $matches[1]
$run_cfg[0] -match "ServerRoot: \W(.*)\W" | out-null

$ServerRoot = $matches[1]

$mod_dir = $ServerRoot + "/modules"

# Find the main configuration file
httpd -V | foreach{
    if($_ -match "-D SERVER_CONFIG_FILE=\W(.*)\W"){
        $conf = $ServerRoot + "/" + $matches[1]
    }
}

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
        
         # See if the module is already enabled
        httpd -M | foreach{
            if($_ -match "\b(.*)_module" -and $matches[0] -eq $modname){
                 if($act -eq 'en'){
                    write-host -foregroundcolor GREEN "Module already enabled"
                    exit
                 } else { # Show this for Disable Module
                    $modfound = $true
                    write-host -foregroundcolor GREEN "Module found"
                 }
                 
            }
        }
        
        # This is for Disable Module
        if($act -eq 'dis' -and !$modfound){
            write-host -foregroundcolor RED -backgroundcolor BLACK "$mod not found"
            exit
        }
        
        switch($act){
            'en'{ # Enable/Add Module
                # Don't look in the default location if the $add switch is on
                # This allows the user to explicitly overwrite a module of the same name
                if(!$add){ 
                    try{
                        # The modules directory is assumed to be in the "modules" folder underneath ServerRoot
                        # Forward slashes are displayed because that's what httpd uses internally
                        $mod_dir = get-item $mod_dir
                        write-host -foregroundcolor YELLOW "Looking in $($mod_dir.fullname) for $mod"
                        
                        $foundModule = $mod_dir.getfiles($modfilename)
                        if($foundModule){
                            $foundModule = $foundModule[0]
                            write-host -foregroundcolor GREEN "Module found"
                        }
                    }
                    catch [System.Exception] {
                      switch($_.Exception.GetType().FullName) {
                        'System.Management.Automation.ItemNotFoundException' {
                            write-host -foregroundcolor RED -backgroundcolor BLACK "`"$mod_dir`" directory not found"
                         }
                        'System.IO.IOException' {
                            write-host -foregroundcolor RED -backgroundcolor BLACK "Could not read the `"$mod_dir`" directory"
                        }
                      }
                      exit           
                    }
                }

                # The module either wasn't found or wasn't searched for in the default location
                if(!$foundModule){        
                    if(!$search) {
                        $search = $pwd
                    }
                    
                    try{
                        # See if the module is in either the current directory or the specified one
                        $search_dir = get-item $search
                        
                        write-host -foregroundcolor YELLOW "Looking in $($search_dir.fullname) for $mod"
                        
                        $foundModule = $search_dir.getfiles($modfilename)
                        if($foundModule){
                            $foundModule = $foundModule[0]
                            write-host -foregroundcolor GREEN "Module found"
                            # Since it's not in the modules directory, it will need to be copied to there
                            $add = $True
                        }
                    }
                    catch [System.Exception] {
                      switch($_.Exception.GetType().FullName) {
                        'System.Management.Automation.ItemNotFoundException' {
                            write-host -foregroundcolor RED -backgroundcolor BLACK "`"$search`" directory not found"
                         }
                        'System.IO.IOException' {
                            write-host -foregroundcolor RED -backgroundcolor BLACK "Could not read the `"$search`" directory"
                        }
                      }
                      exit           
                    }
                    
                    # If the module still can't be found, let the user know
                    if(!$foundModule){
                        write-host -foregroundcolor RED -backgroundcolor BLACK "Module not found"
                        exit
                    }
                }

                # The module was located
                # See if the module needs to be copied to $mod_dir
                if($add){    
                    copy $foundmodule.fullname $mod_dir
                    "$mod was copied to $mod_dir"
                }

                # Enable the module in httpd.conf
                (get-content $conf) | foreach { 
                    $_ -match "LoadModule .*modules/($basename).so" | out-null
                    $line = "#" + $matches[0]
                    $_.replace($line, $matches[0])    
                } | set-content $conf
                write-host -foregroundcolor GREEN "Module enabled"
                
                break # End of Enable Module
            }
            'dis'{ # Disable Module
                (get-content $conf) | foreach {
                    $_ -match "LoadModule .*modules/($basename).so" | out-null
                    $line = "#" + $matches[0]
                    $_.replace($matches[0], $line)
                } | set-content $conf
                write-host -foregroundcolor GREEN "Module disabled"
                
                break # End of Disable Module
            }
        }
        break # End of Module
    }
    'site'{        
        $conf_dir = (get-item $conf).directory   
        
        # Create the site directories if they are not already present
        if(!$conf_dir.getdirectories("sites-enabled")){
            $conf_dir.createsubdirectory("sites-enabled")
        }
        
        if(!$conf_dir.getdirectories("sites-available")){
            $conf_dir.createsubdirectory("sites-available")
        }       
        
        # Get DirectoryInfo object references for the site directories
        $sitesenabled = $conf_dir.getdirectories("sites-enabled")
        $sitesenabled = $sitesenabled[0]
        
        $sitesavailable = $conf_dir.getdirectories("sites-available")
        $sitesavailable = $sitesavailable[0]
        
        # Let the user refer to the file either by the basename or file name
        if(!$mod.contains(".conf")){ $mod = $mod + ".conf"}
        
        # Add the Include line for enabled sites to the main config if it isn't already there
        $includeline = "Include $($conf_dir.name)/sites-enabled/"
        (get-content $conf) | foreach { 
            if($_.contains($includeline)){
                $hasline = $true
            }            
        }
        
        if(!$hasline){
            write-host -foregroundcolor GREEN "Adding sites directory to config..."
            $includeline = "`n" + $includeline
            add-content $conf $includeline
        }
        
        switch($act){
            'en'{ # Enable Site
                try{
                    if(!$add){
                        # See if the site is already enabled          
                        if($sitesenabled.getfiles($mod)){
                            write-host -foregroundcolor GREEN "$($mod) is already enabled"
                            exit
                        }
                    
                        # See if it is in sites-available
                        write-host -foregroundcolor YELLOW "Checking sites-available..."
                        $site = $sitesavailable.getfiles($mod)
                        if($site){
                            move-item $site[0].fullname $sitesenabled.fullname
                            write-host -foregroundcolor GREEN "$($site[0].basename) enabled"
                        }
                    }
                    
                    # See if the user specified the directory that the site is in
                    if(!$site){
                        if($search){
                            $search_dir = get-item $search
                            write-host -foregroundcolor YELLOW "Checking $($search_dir.fullname)..."
                        } else {
                            # Look in the current directory by default
                            $search_dir = get-item $pwd
                            write-host -foregroundcolor YELLOW "Checking $($search_dir.fullname)..."
                        }
                        
                        $site = $search_dir.getfiles($mod)
                        if($site){
                            move-item $site[0].fullname $sitesenabled.fullname
                            write-host -foregroundcolor GREEN "$($site[0].basename) enabled"
                        } else {
                            write-host -foregroundcolor RED -backgroundcolor BLACK "$mod was not found"
                            exit
                        }
                    }
                }
                catch [System.Exception] {
                  switch($_.Exception.GetType().FullName) {
                    'System.Management.Automation.ItemNotFoundException' {
                        write-host -foregroundcolor RED -backgroundcolor BLACK "`"$search`" directory not found"
                     }
                    'System.IO.IOException' {
                        write-host -foregroundcolor RED -backgroundcolor BLACK "Could not read the `"$search`" directory"
                    }
                  }
                  exit           
                }            
                
                break # End of Enable Site
            }
            
            'dis'{ # Disable Site
                $site = $sitesenabled.getfiles($mod)
                if($site){
                    move-item $site[0].fullname $sitesavailable.fullname
                    write-host -foregroundcolor GREEN "$($site[0].basename) disabled"
                } else {
                    write-host -foregroundcolor RED -backgroundcolor BLACK "$($site.name) is not enabled"
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
    if(!$norestart){
        # Restart the webserver
        write-host -foregroundcolor GREEN "Syntax OK. Restarting Server..."
        httpd -k restart
        
        write-host -foregroundcolor GREEN "Server Restarted"
    }
}else {
    write-host -foregroundcolor RED -backgroundcolor BLACK $error[0].tostring()
}

