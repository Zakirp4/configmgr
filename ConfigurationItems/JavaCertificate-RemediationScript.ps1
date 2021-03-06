<#
.SYNOPSIS
 Installs certificates to the Java RTE certificate store of Windows client workstations

 .DESCRIPTION
 The Java keytool.exe is used to import certificates into the Java RTE certificate store for all users

.NOTES
 Author: Mark Allen
 Created: 22-11-2016
 References: https://docs.microsoft.com/en-us/azure/java-add-certificate-ca-store
 Credit to Steve Renard for the Get-JavaHomeLocation function: http://powershell-guru.com/author/powershellgu/
#>

function Get-JavaHomeLocation
{
    $OSArchitecture = Get-WmiObject -Class Win32_OperatingSystem | Select-Object -ExpandProperty OSArchitecture
    
    switch ($OSArchitecture)
    {
        '32-bit' { $javaPath = 'HKLM:\SOFTWARE\JavaSoft' }
        '64-bit' { $javaPath = 'HKLM:\SOFTWARE\Wow6432Node\JavaSoft' }
        Default  { return 'Unable to determine OS architecture'}
    }
    
    if (Test-Path -Path $javaPath)
    {
        try
        {
            $javaPathRegedit =  Get-ChildItem -Path $javaPath -Recurse -ErrorAction Stop
            [bool]$foundCurrentVersion = ($javaPathRegedit| ForEach-Object {($_ | Get-ItemProperty).PSObject.Properties} | Select-Object -ExpandProperty Name -Unique).Contains('CurrentVersion')
        }
        catch
        {
            return $_.Exception.Message
        }

        if ($foundCurrentVersion)
        {
            [string]$currentVersion = $javaPathRegedit | ForEach-Object {($_ | Get-ItemProperty).PSObject.Properties | Where-Object {$_.Name -eq 'CurrentVersion'} } | Select-Object -ExpandProperty Value -Unique -First 1
            Get-ItemProperty -Path "$javaPath\Java Runtime Environment\$currentVersion" -Name JavaHome | Select-Object -ExpandProperty JavaHome
        }
        else
        {
            return "Unable to retrieve CurrentVersion"
        }
    }
    else
    {
        return "$env:PROCESSOR_ARCHITECTURE : $javaPath not found"
    }
}

<#
 *** Customise here only ***
#>
# define the publicly acccessible folder that will store certificate files (*.cer)
$ExternalFileStore = '\\SERVER\Share\Certificates\'
# create  a hash table for the certificates that should be imported
# The key is the certificate alias and the item is the certificate file name
# eg $Certificates = @{'my-alias-1' = 'MyCertificate-1.cer';'my-alias-2' = 'MyCertificate-2.cer'}
$Certificates = @{'my-alias-1' = 'MyCertificate-1.cer';'my-alias-2' = 'MyCertificate-2.cer'}
<#
 *** End customisation ***
#>

<#
 Form the relevant file and folder paths
#>
$JavaHome = Get-JavaHomeLocation
$KeyTool = $JavaHome + '\bin\keytool.exe'
$CaCerts = $JavaHome + '\lib\security\cacerts'
$CaCertsBak = $CaCerts + '.bak'
$LogFile = $JavaHome + '\lib\security\import-certificates.log'

<#
 Test that all the relevant paths have been formed correctly
#>
if (!(Test-Path $ExternalFileStore)) {"Can't access $ExternalFileStore" | Add-Content $LogFile; exit 1}
if (!(Test-Path $JavaHome)) {"JavaHome error: $JavaHome" | Add-Content $LogFile; exit 1}
if (!(Test-Path $KeyTool)) {"Can't find $KeyTool" | Add-Content $LogFile; exit 1}
if (!(Test-Path $CaCerts)) {"Can't find $CaCerts" | Add-Content $LogFile; exit 1}

<#
 Iterate through the collection of certificates and import if missing from the certificate store
#>
foreach ($Certificate in $Certificates.Keys) {
    # test if the certificate is is already present in the certificate store
    if( (& $KeyTool -list -keystore $CaCerts -storepass changeit -alias $Certificate -noprompt) -like "keytool error: java.lang.Exception: Alias <*> does not exist" )
    {
        $CertificateFile = $ExternalFileStore + $Certificates.Item($Certificate)
        # test that the certificate file exists and can be accessed
        if (!(Test-Path $CertificateFile)) { "Can't access $CertificateFile" | Add-Content $LogFile }
        "Found $CertificateFile, importing $Certificate into $CaCerts." | Add-Content $LogFile
        # execute the import of the certificate file
        & $KeyTool -keystore $CaCerts -storepass changeit -importcert -alias $Certificate -file $CertificateFile -noprompt
    }
}

<#
 Confirm that all of the certificates have been correctly added to the certificate store
#>
"Checking that certificates were correctly added..." | Add-Content $LogFile
# if any of the certificates is missing the script will exit with code 1, this is a requirement for the ConfigMgr remediation failure status
$Certificates.Keys | ForEach-Object { if( (& $KeyTool -list -keystore $CaCerts -storepass changeit -alias $_ -noprompt) -like "keytool error: java.lang.Exception: Alias <*> does not exist" ) { 'Non-Compliant' | Add-Content $LogFile ; Exit 1 } }
'Compliant' | Add-Content $LogFile
Write-Host 'Compliant'