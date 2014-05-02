[CmdletBinding()]
Param(
    [Parameter(Position=1)]
    [string]$mod,
    [Parameter(Position=2)]
    [string]$search,
    [switch]$copy,
    [switch]$add,
    [switch]$norestart,
    [switch]$replace
)

# Halt on all errors by default
$ErrorActionPreference = "stop"

# Find out which command was called
If($MyInvocation.InvocationName -match "a2(en|dis)(mod|site)"){
    $act = $matches[1]
    $obj = $matches[2]
} Else {
    Write-Host $MyInvocation.InvocationName " call not recognized"
    Exit
}

$run_cfg = httpd -D DUMP_RUN_CFG

# Value of ServerRoot will be surrounded by quotes, so only group the actual pathname
# which will be available in $matches[1]
$run_cfg[0] -match "ServerRoot: \W(.*)\W" | Out-Null

$ServerRoot = $matches[1]

# The modules directory is assumed to be in the "modules" folder underneath ServerRoot
$mod_dirname = "modules"
$mod_dir = $ServerRoot + "\$mod_dirname"

# Find the main configuration file
httpd -V | ForEach{
    If($_ -match "-D SERVER_CONFIG_FILE=\W(.*)\W"){
        $conf = $ServerRoot + "\" + $matches[1]
    }
}

If(!(Test-Path $conf)){ 
    Write-Host -ForegroundColor RED -BackgroundColor BLACK "httpd configuration file at $conf could not be found"
    Exit 
} Else {

    $conf = Get-Item $conf
    $conf_dir = $conf.Directory
}

# Verify the existence of the required directories
try{
    # Default module dirctory
    $lookup_dir = $mod_dir
    $mod_dir = Get-Item $mod_dir
    
    # The default search directory is the current directory
    $lookup_dir = $search
    $search_dir = Get-Item $search
}
catch [System.Exception] {
    <#
    A System.Management.Automation.ParameterBindingValidationException is thrown
    if no parameters are passed
    #>
    switch($_.Exception.GetType().FullName) {
        'System.Management.Automation.ItemNotFoundException' {
            Write-Host -ForegroundColor RED -BackgroundColor BLACK "`"$lookup_dir`" not found"
            Exit
         }
        'System.IO.IOException' {
            Write-Host -ForegroundColor RED -BackgroundColor BLACK "Could not read `"$lookup_dir`""
            Exit
        }
    }
}

<#
Make the default site directories.
#>
Function makeSiteDirs{
    # Create the site directories if they are not already present
    If(!$conf_dir.GetDirectories("sites-enabled")){
        $conf_dir.CreateSubdirectory("sites-enabled")
    }
        
    If(!$conf_dir.GetDirectories("sites-available")){
        $conf_dir.CreateSubdirectory("sites-available")
    }  
}

<# 
Add the Include line for enabled sites to the bottom of the main config 
if it isn't already there
#>
Function includeSiteDir{
    $includeline = "IncludeOptional $($conf_dir.name)/*-enabled/"
    (Get-Content $conf) | ForEach { 
        If($_.Contains($includeline)){
            $hasline = $true
        }            
    }
        
    If(!$hasline){
        Write-Host -ForegroundColor GREEN "Adding site directories to config..."
        $includeline = "`n" + $includeline
        Add-Content $conf "$includeline"
    }
}

# If no parameters were passed, assume the user just wanted to view information
If(!$mod){
    switch($obj){
        'mod'{
            # Enabled mods: Show the output of httpd -M
            httpd -M | Write-Host -ForegroundColor green -separator "`n"

            "============================"
            Write-Host ""

            # Disabled mods: Find the names of the modules with a commented LoadModule line in the main config
            $dismodlist = @()
           (Get-Content $conf) | ForEach {
                If($_ -match "\s*[#]\s*LoadModule (.*) (.*)"){
                 $dismodlist += " " + $matches[1]
                }
            }

            Write-Host "Disabled Modules:" -ForegroundColor yellow
            Write-Host -ForegroundColor yellow $dismodlist -separator "`n"            

        }
        'site'{
            includeSiteDir

            # Ask the user to add site configurations to the folders if they were just now made
            If(!$conf_dir.GetDirectories("sites-available") -or !$conf_dir.GetDirectories("sites-enabled")){
                 makeSiteDirs
                 Write-Host -ForegroundColor yellow "Site directories created. Please make a .conf file based on $conf_dir\extra\httpd-vhosts.conf and add it with `"a2ensite <file>`"."
                 Exit
            } Else {
                $sitesavailable = $conf_dir.GetDirectories("sites-available")[0]
            }
            
            # Enabled sites: Show the output of httpd -D DUMP_VHOSTS
            $ensitelist = httpd -D DUMP_VHOSTS
            Write-Host -ForegroundColor green $ensitelist -separator "`n"
            "============================"

            # Enabled sites: Show the files in conf\sites-available
            Write-Host -ForegroundColor yellow "Disabled Sites:"
            $sitesavailable.GetFiles() | Write-Host -ForegroundColor yellow -separator "`n"
        }
    }
    Exit
}

# $mod_dir, $conf, and $search_dir should be available
switch($obj){
    'mod'{
        <#
        Looks through the main configuration file and determines if the $mod the user specified can be found
        as a module name, filename, basename, or shortened module name defined at an enabled or commented out
        LoadModule line.
        #>
        Function getModuleInfo{
            (Get-Content $conf) | ForEach {
                If($_ -match '\s*[#]?\s*(?<enable>LoadModule (?<modname>\w*) (?<path>.*))'){
                     <#
                     If the path part of the LoadModule line begins with quotes, it is an absolute
                     path to the module file. Otherwise, it is a relative path underneath ServerRoot.
                     #>
                     $quoted = [regex]::match($matches['path'], "(['`"]).*\1")
                     If($quoted.Success){
                       $modline_file = $matches['path'].Replace($quoted.Groups[1].Value, "")
                     } Else {
                       $modline_file = $ServerRoot + "\" + $matches['path'];
                     }

                     <#
                     Find out if the path to the module exists
                     #>
                     If(Test-Path $modline_file){ 
	                   $modline_file = Get-Item $modline_file
                       $fileexists= $true
	                 } Else {
                       $fileexists = $false
                     }

                     $modline_shortname = $matches['modname'].Replace("_module", "")
                     $modinfo = @{
                                  name=$matches['modname'];
                                  fullfilename=$modline_file.FullName;
                                  filename=$modline_file.Name;
                                  basename=$modline_file.BaseName;
                                  path=$matches['path']; 
                                  file=$modline_file; 
                                  shortname=$modline_shortname;
                                 }
                     
                     <#
                     Backslashes in path names just cause
                     too much trouble
                     #>
                     If($modinfo.path -match "\\"){
                        $modinfo.path = $modinfo.path -replace "\\", "/" 
                     }

                     If($modinfo.ContainsValue($mod)){
                       $modinfo.fileexists = $fileexists
                       $modinfo.enable=$matches['enable']
                       $modinfo.disable='#' + $matches['enable']

                       # The specified module was found in the configutation file
                       return $modinfo
                     }
                 }
             }
             # If we don't break out of the ForEach, the module was not found in the configuration file
             return $false
        }
        $modinfo = getModuleInfo
        
        # Exit if the user is not adding or replacing a module and the specified module is not found
        If(!($search -or $replace) -and !$modinfo){
            # For now, only work with modules listed in the main config
            Write-Host -ForegroundColor RED -BackgroundColor BLACK "Module not found in $($conf.FullName)"
            Exit
        }

        # See if the module is already enabled        
        httpd -M | ForEach{
            If($_ -match "\b(.*) (.*)" -and $matches[1] -eq $modinfo.name){
                 $modfound = $True
                 If($act -eq 'en' -and !$replace){
                    Write-Host -ForegroundColor GREEN "Module already enabled"
                    Exit
                 }

                 Write-Host -ForegroundColor GREEN "Module found"                 
            }
        }        

        # The function for actually enabling or disabling the module    
        Function toggleModule{
            (Get-Content $conf) | ForEach {
                <#
                If an enabled or disabled LoadModule line is found, the line will be replaced
                by a LoadModule line of the opposite state. The new line will have no preceding
                whitespace. A newly disabled line will only have a single '#' before it.
                #> 
                ($_ -match "\s*[#]?\s*LoadModule $($modinfo.name) $($modinfo.path)") | Out-Null
                    If($act -eq 'en'){
                        $action = 'enabled'
                        $_.Replace($matches[0], $modinfo.enable)
                    }Else {
                        $action = 'disabled'
                        $_.Replace($matches[0], $modinfo.disable)
                    }
                        
            } | Set-Content $conf
    
            Write-Host -ForegroundColor GREEN "$($modinfo.name) $action" 
        }
        
        switch($act){
            'en'{ # Enable/Add Module
                # The module was located

                
                # The user is either adding a new module or replacing an existing one
                If($search -or $replace){
                    If(!$modfound -and $search){
                        Write-Host "Adding new module..."
                    }

                    # The module to add must be a path to a file specified in $search
                    If(!$search){
                        Write-Host -ForegroundColor RED -BackgroundColor BLACK "Specify the module to add with a2enmod [-mod] <module_name> [-search] <path_to_module>"
                        Exit
                    } Else {
                        If(!(Test-Path $search)){
                            Write-Host -ForegroundColor RED -BackgroundColor BLACK "`"$search`" not found"
                            Exit
                        } Else {
                            $searchItem = Get-Item $search
                        }
                    }

                    # The user wants to copy the module file to the default modules folder
                    If($copy){
                        <# 
                        If the user wishes to overwrite a module file of the same name, the web server
                        must not be running while the file is copied.
                        #>
                        $found = $mod_dir.GetFiles($searchItem.Name)
                        If($found -and $norestart){
                            $title = "Web Server Restart Required"
                            $message = "There is already a $($modinfo.name) in $mod_dir. Restart the web server and overwrite it?"

                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
                                "Overwrites $($mod_dir.GetFiles($search.Name)[0]) with $search"

                            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
                                "Immediately exits the script"

                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

                            $result = $Host.UI.PromptForChoice($title, $message, $options, 0) 

                            If($result -eq 1) { "Exiting"; Exit }
                            $replace = $True
                        }
                    
                        Write-Host -ForegroundColor YELLOW "Copying module..."

                        # If a file of the same name already exists, turn off the server so that the module can be replaced
                        If($found){
                            # Any non redirected errors in PowerShell 3 will be treated as terminating errors
                            $ErrorActionPreference = "silentlycontinue"
                            Write-Host -ForegroundColor YELLOW "Stopping Apache service..."
                            httpd -k stop
                            $ErrorActionPreference = "stop"
                        }

                        # Make $searchItem the location of the module in the default modules directory
                        $searchItem = Copy-Item -Path $searchItem -Destination $mod_dir -PassThru
                        "$mod was copied to $mod_dir"
                    }
                    <#
                    The user is either replacing the path for a module or adding a new one
                    #>
                    If($mod_dir.FullName -eq $searchItem.DirectoryName){
                        $newpath = "modules/$($searchItem.Name)"
                    } Else {
                        $newpath = "`"$($searchItem.FullName)`""
                        $newpath = $newpath -replace "\\", "/"
                    }

                    # The user has named an existing module, so it will be replaced
                    If($modinfo){
                        If(!$replace){
                            $title = "Module exists"
                            $message = "Would you like to replace $($modinfo.name) in $mod_dir ?"

                            $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
                                "LoadModule line replaced with new -search path"

                            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
                                "Immediately exits the script"

                            $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

                            $result = $Host.UI.PromptForChoice($title, $message, $options, 0) 

                            If($result -eq 1) { "Exiting"; Exit }
                        }        
                        (Get-Content $conf) | ForEach {
                            ($_ -match "\s*[#]?\s*LoadModule $($modinfo.name) $($modinfo.path)") | Out-Null
                                $_.Replace($matches[0], "LoadModule $($modinfo.name) $newpath")
                        } | Set-Content $conf
                        Write-Host -ForegroundColor GREEN "Replaced 'LoadModule $($modinfo.name) $($modinfo.path)' with 'LoadModule $($modinfo.name) $newpath'"

                    } ElseIf($search) {
                        <#
                        Add a new line to the main config file to load this module

                        This pattern matches the the block of LoadModule lines and their preceding
                        comments which customarily come with Windows Apache. The line for the new module will
                        be added right below this block.
                        #>                        
                        $pattern = "# Dynamic Shared Object \(DSO\) Support(\s*#.*){1,}(\s*[#]?LoadModule (.*) (.*)){1,}"
                        # Requires Powershell 3.0
                        $rawconf = Get-Content $conf -Raw

                        $rawconf -match $pattern | Out-Null
                        $rawconf -replace $pattern, ($matches[0] + "`nLoadModule $mod $newpath") | Set-Content $conf
                        Write-Host -ForegroundColor GREEN "Added 'LoadModule $mod $newpath' to $conf"
                    } Else {
                        # The module was not found and they are not adding one
                        Write-Host -ForegroundColor RED -BackgroundColor BLACK $mod "not found"
                        Exit
                    }
                } Else {
                    # Enable the module in the main config file
                    toggleModule
                }

                break # End of Enable Module
            }
            'dis'{ # Disable Module
                # If the specified $mod was not listed by httpd -M, tell the user it's already disabled.
                If(!$modfound){
                    Write-Host -ForegroundColor RED -BackgroundColor BLACK "$mod already disabled"
                    Write-Host $modinfo.path
                    Exit
                }

                toggleModule
                
                break # End of Disable Module
            }
        }
        break # End of Module
    }
    'site'{
        makeSiteDirs
          
        # Get DirectoryInfo object references for the site directories
        $sitesenabled = $conf_dir.GetDirectories("sites-enabled")
        $sitesenabled = $sitesenabled[0]
        
        $sitesavailable = $conf_dir.GetDirectories("sites-available")
        $sitesavailable = $sitesavailable[0]
        
        # Let the user refer to the file either by the basename or file name
        If(!$mod.Contains(".conf")){ $mod = $mod + ".conf"}
        
        includeSiteDir
        
        If($copy -or $add){
            If((Test-Path $mod)){
                $site = Get-Item $mod
                $location = $site.Directory
            } Else {
                Write-Host -ForegroundColor RED -BackgroundColor BLACK "Could not find file $mod"
                Exit
            }                
        } Else {
            If($act -eq 'en'){
                $location = $sitesavailable
            } Else {
                $location = $sitesenabled
            }
            
            $site = $location.GetFiles($mod)
        }

        # Enable or disable the site specified in $mod
        Function toggleSite {
            If($site){
                If($copy){
                    $action = 'Copying';
                } Else {
                    $action = 'Moving';
                }

                Write-Host -ForegroundColor YELLOW "$action $($site.FullName)..."

                If($act -eq 'en'){
                    # Move the new site to sites-enabled, unless the user explicitly chose to copy
                    If(!$copy){
                        Move-Item $site[0].FullName $sitesenabled.FullName    
                    } Else {
                        Copy-Item $site[0].FullName $sitesenabled.FullName
                    }                    
                } Else {
                    # Disable the site by moving it to sites-available
                    Move-Item $site[0].FullName $sitesavailable.FullName
                }
                return $true
            } Else {
                # The configuration file for the site was not found
                return $false 
            }
            
        }

        switch($act){
            
            'en'{ # Enable Site
                If(!$copy){                    
                    # See if the site is already enabled          
                    If($site -and $sitesenabled.GetFiles($site.Name) -and !$replace){
                        Write-Host -ForegroundColor GREEN "$mod is already enabled"
                        Exit
                    }

                    $result = toggleSite

                } Else {
                    # Check if there's already a site of the same name in sites-available
                    $oldsite = $sitesavailable.GetFiles($site.Name)
                            
                    If($oldsite){
                        $title = "Delete $mod in sites-available?"
                        $message = "There is a $mod in sites-available. Would you like to replace it?"

                        $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", `
                            "Copies $site to $sitesavailable and removes $($oldsite[0])"

                        $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", `
                            "Immediately exits the script"

                        $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)

                        $choiceresult = $Host.UI.PromptForChoice($title, $message, $options, 0)

                        # Exit if they don't wish to overwrite the similarly named file in sites-available
                        If($choiceresult -eq 1){
                            "Exiting"; Exit
                        } Else {
                            Remove-Item $oldsite[0].FullName
                        }
                    }

                    $result = toggleSite
                }

                # At this point, either the site was found or it wasn't
                If($result){
                    Write-Host -ForegroundColor GREEN "$mod enabled"
                } Else {
                    Write-Host -ForegroundColor RED -BackgroundColor BLACK "$mod was not found"
                    Exit
                }
                    
                break
             } # End of Enable Site
            
            
            'dis'{ # Disable Site
                $result = toggleSite
                If($result){
                    Write-Host -ForegroundColor GREEN "$mod disabled"
                } Else {
                    Write-Host -ForegroundColor RED -BackgroundColor BLACK "$mod is not enabled"
                    Exit
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

If($error[0].ToString() -eq "Syntax OK"){    
    If(!$norestart -or $modenabled){
        # Restart the webserver
        Write-Host -ForegroundColor GREEN "Syntax OK. Restarting Server..."
        httpd -k restart
        
        Write-Host -ForegroundColor GREEN "Server Restarted"
    }
}Else {
    Write-Host -ForegroundColor RED -BackgroundColor BLACK $error[0].ToString()
}
