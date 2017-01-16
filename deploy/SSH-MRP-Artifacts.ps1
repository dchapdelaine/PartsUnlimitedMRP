[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True)] [string] $sshTarget,
	[Parameter(Mandatory=$True)] [string] $sshUser,
    [Parameter(Mandatory=$True)] [string] $sshPrivateKeyStorageAccountName,
    [Parameter(Mandatory=$True)] [string] $sshPrivateKeyContainerName,
    [Parameter(Mandatory=$True)] [string] $sshPrivateKeyBlobName,
    [Parameter(Mandatory=$True)] [string] $sshPrivateKeyStorageAccountKey
)

$ErrorActionPreference = "Stop"


# Get plink and psftp
$psftpExeUrl="https://the.earth.li/~sgtatham/putty/latest/x86/psftp.exe"
$plinkExeUrl="https://the.earth.li/~sgtatham/putty/latest/x86/plink.exe"

if (-not (Test-Path psftp.exe)) {
    wget $psftpExeUrl -OutFile psftp.exe
}
if (-not (Test-Path plink.exe)) {
    wget $plinkExeUrl -OutFile plink.exe
}

# Set deploy directory on target server
$deployDirectory = "/tmp/mrpdeploy_" + [System.Guid]::NewGuid().toString()
$buildName = $($env:BUILD_DEFINITIONNAME)
# Save sftp command text to file
$sftpFile = "sftp.txt"
$sftpContent = @'
mkdir ROOT_DEPLOY_DIRECTORY
cd ROOT_DEPLOY_DIRECTORY
mkdir deploy
cd deploy
put ./ARTIFACT_DIRECTORY/deploy/MongoRecords.js
put ./ARTIFACT_DIRECTORY/deploy/deploy_mrp_app.sh
chmod 755 deploy_mrp_app.sh
cd ..
mkdir drop
cd drop
put -r ./ARTIFACT_DIRECTORY/drop/Backend/IntegrationService/build/libs/
put -r ./ARTIFACT_DIRECTORY/drop/Backend/OrderService/build/libs/
put -r ./ARTIFACT_DIRECTORY/drop/Clients/build/libs/
chmod 755 ./*
'@
$sftpContent = $sftpContent.Replace('ROOT_DEPLOY_DIRECTORY',$deployDirectory)
$sftpContent = $sftpContent.Replace('ARTIFACT_DIRECTORY',$buildName)
Set-Content -Path $sftpFile -Value $sftpContent


# Save plink command text to file
$plinkFile = "plink.txt"
$plinkContent = @'
cd ROOT_DEPLOY_DIRECTORY/deploy
sudo apt-get install dos2unix -y
dos2unix deploy_mrp_app.sh
sudo bash ./deploy_mrp_app.sh
'@
$plinkContent = $plinkContent.Replace('ROOT_DEPLOY_DIRECTORY',$deployDirectory)
Set-Content -Path $plinkFile -Value $plinkContent

$context = New-AzureStorageContext -StorageAccountName $sshPrivateKeyStorageAccountName -StorageAccountKey $sshPrivateKeyStorageAccountKey
Get-AzureStorageBlobContent -Blob $sshPrivateKeyBlobName -Container $sshPrivateKeyContainerName -Destination sshPrivateKey.ppk -Context $context

Write-Host "Path to file: $currentPath/sshPrivateKey.ppk"
Get-Content "sshPrivateKey.ppk" | Write-Host

Write-Host "psftp"
echo y | & .\psftp.exe $sshUser@$sshTarget -i "sshPrivateKey.ppk" -b $sftpFile 
Write-Host "plink"
echo y | & .\plink.exe $sshUser@$sshTarget -i "sshPrivateKey.ppk" -m $plinkFile
