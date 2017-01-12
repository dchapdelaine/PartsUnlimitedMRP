[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)] [string] $sshTarget,
	[Parameter(Mandatory=$True)] [string] $sshUser,
    [Parameter(Mandatory=$True)] [string] $privateKey,
    [Parameter(Mandatory=$True)] [string] $azureStorageAccountName,
    [Parameter(Mandatory=$True)] [string] $azureStorageAccountKey,
    [Parameter(Mandatory=$True)] [string] $containerName,
    [Parameter(Mandatory=$True)] [string] $keyName
)

$ErrorActionPreference = "Stop"

# Set deploy directory on target server
$deployDirectory = "/tmp/mrpdeploy_" + [System.Guid]::NewGuid().toString()
$buildName = $($env:BUILD_DEFINITIONNAME)

# Connection variables
$sshTarget = $sshTarget
$sshUser = $sshUser

# I could not figure out how to take the string input as a key and converti to a .PEM or key file that the Posh-SSH would accept so I actually uploaded it to a container on Azure.

$azureStorageAccountName = $azureStorageAccountName
$azureStorageAccountKey = $azureStorageAccountKey
$containerName = $containerName
$keyName = $keyName
$privateKeyFile = "$($deployDirectory)/$($keyName)"

# Install necessary component for Azure
if (Get-Module -ListAvailable -Name AzureRM)
    {
        Write-Host "Azure already Installed"
    }
    else
    {
        Install-Module Azure -Force -Scope CurrentUser
        Write-Host "Azure was installed."
    }

# NuGet is required to be installed for Posh-SSH
if (Get-PackageProvider -ListAvailable -Name "NuGet")
    {
        Write-Host "NuGet is already installed"
    }
else
    {
        Install-PackageProvider -Name NuGet -Force -Scope CurrentUser -ErrorAction SilentlyContinue
        Write-Host "NuGet Package Provider was installed"
    }

# Install Posh-SSH
if (Get-Module -ListAvailable -Name Posh-SSH)
    {
        Write-Host "Posh-SSH already installed"
    }
    else
    {
        iex (New-Object Net.WebClient).DownloadString("https://gist.github.com/darkoperator/6152630/raw/c67de4f7cd780ba367cccbc2593f38d18ce6df89/instposhsshdev")
        Install-Module Posh-SSH -Force -Scope CurrentUser
        Write-Host "Posh-SSH was installed"
    }

# Download Keyfile from Azure
$ctx = New-AzureStorageContext -StorageAccountName $azureStorageAccountName -StorageAccountKey $azureStorageAccountKey
Get-AzureStorageBlobContent -Container $containerName -Blob $keyName -Destination $deployDirectory -Context $ctx -Force


# Handle Credental information
$nopasswd = New-Object System.Security.SecureString
$cred = New-Object System.Management.Automation.PSCredential ($sshUser, $nopasswd)

# Create sftp connection
$session = New-SFTPSession -ComputerName $sshTarget -Credential $cred -KeyFile $privateKeyFile -Verbose
$dropDirectory = "./ROOT_DEPLOY_DIRECTORY/drop"

# Create Directories
New-SFTPItem -SFTPSession $session -ItemType Directory $deployDirectory -Verbose
New-SFTPItem -SFTPSession $session -ItemType Directory $dropDirectory -Verbose

# uploaded the files 
Set-SFTPFile -SFTPSession $session -LocalFile $buildName/MongoRecords.js -RemotePath $deployDirectory/MongoRecords.js
Set-SFTPFile -SFTPSession $session -LocalFile $buildName/deploy_mrp_app.sh -RemotePath $deployDirectory/deploy_mrp_app.sh
Set-SFTPFile -SFTPSession $session -LocalFile $buildName/drop/Backend/IntegrationService/build/libs/* -RemotePath $dropDirectory
Set-SFTPFile -SFTPSession $session -LocalFile $buildName/drop/Backend/OrderService/build/libs/* -RemotePath $dropDirectory
Set-SFTPFile -SFTPSession $session -LocalFile $buildName/drop/Clients/build/lib/* -RemotePath $dropDirectory

# Create SSH Session 
$session2 = New-SSHSession -ComputerName $sshTarget -Credential $cred -KeyFile $privateKeyFile -Verbose

# Change file permissions
Invoke-SSHCommand -SSHSession $session2 -Command "chmod 755 $($deployDirectory)/deploy_mrp_app.sh && chmod 755 $($dropDirectory)/*"

# Run commands previously run in plink
Invoke-SSHCommand -SSHSession $session2 -Command "cd $($deployDirectory)/deploy && sudo apt-get install dos2unix -y && dos2unix deploy_mrp_app.sh && sudo bash ./deploy_mrp_app.sh"