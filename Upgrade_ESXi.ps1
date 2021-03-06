#Automated steps for upgrading ESXi hosts using PowerCLI

#Prep: Have the ESXi upgrade image on your local machine and note the path for that file
#PowerCLI needs to be installed
#Posh-SSH needs to be installed


#To run cli commands on ESXi host, use Psh-SSH:
#Install-Module -Name Posh-SSH -RequiredVersion 3.0.0

#The above requires unrestricted execution policy:
#Set-ExecutionPolicy Unrestricted

<#
 #Ignore self signed certificate errors:
 PS C:\WINDOWS\system32> Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

Scope    ProxyPolicy     DefaultVIServerMode InvalidCertificateAction  DisplayDeprecationWarnings WebOperationTimeout
                                                                                                  Seconds
-----    -----------     ------------------- ------------------------  -------------------------- -------------------
Session  UseSystemProxy  Multiple            Ignore                    True                       300
User                                         Ignore
AllUsers
#>

Write-Output "Running ESXi host Upgrade script!"


Write-Output "Declaring variables....."
$vcenter = '1.2.3.4'
$username = 'administrator@vsphere.local'
$password = 'VMware1!'
$esxihost = '1.2.3.5'
$command = 'unzip /vmfs/volumes/<host datastore>/VMware-ESXi-7.0U2c-18426014-depot.zip -d /vmfs/volumes/<datastore>/'
$destination = 'vmstore:\DatacenterA\<host datastore>\'
$upgradebundle = 'C:\<Local File Path>\VMware-ESXi-7.0U2c-18426014-depot.zip'
$hostpath = '/vmfs/volumes/<host datastore>/vmw-ESXi-7.0.2-metadata.zip'

Write-Output "Connecting to the vCenter"
#Connect to vCenter:
Connect-VIServer -Server $vcenter -User $username -Password $password
sleep 2

Write-Output "Listing out hosts for visibilty!"
#Check the list of hosts and the versions of the hosts before starting!
Get-VMHost | Select @{Label = "Host"; Expression = {$_.Name}} , @{Label = "ESX Version"; Expression = {$_.version}}, @{Label = "ESX Build" ; Expression = {$_.build}}
sleep 2

Write-Output "Checking that SSH is enabled"
#Check if SSH is enabled on the host. SSH is used to transefer the upgrade bundle
Get-VMHost | Get-VMHostService | Where { $_.Key -eq "TSM-SSH" } |select VMHost, Label, Running
sleep 2

Write-Output "Enabeling SSH"
#Enable SSH on a specific host. This command can be modified to enable SSH for many hosts at once!
Get-VMHost -name $esxihost | Foreach {Start-VMHostService -HostService ($_ | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"} )}
sleep 2

Write-Output "Checking that SSH is enabled"
#Check if SSH is enabled on the host. SSH is used to transefer the upgrade bundle
Get-VMHost | Get-VMHostService | Where { $_.Key -eq "TSM-SSH" } |select VMHost, Label, Running
sleep 2

Write-Output "Checking Datastore information"
#Check the datastore information 
Get-PSDrive -PSProvider VimDatastore
sleep 2

Write-Output "Copying host upgrade bundle to the host!"
#Copy file (upgrade bundle) from my machine to the ESXi host
Copy-DatastoreItem -Item $upgradebundle  -Destination $destination
sleep 2

Write-Output "Unpacking the upgrade bundle!"
#Using Posh-SSH Command, Unzip the file on the host to the correct directory
$setsession = New-SSHSession -ComputerName $esxihost -Credential (Get-Credential root)
Invoke-SSHCommand -SessionId 0 -Command $command
sleep 2

Write-Output "Disable SSH for security. It is no longer needed!"
#disable SSH service since it will not be needed further
Get-VMHost -name $esxihost| Foreach {Stop-VMHostService -HostService ($_ | Get-VMHostService | Where { $_.Key -eq "TSM-SSH"} )}
sleep 2

Write-Output "Destroy Posh SSH session. Keep it clean!"
#Destroy Posh SSH session. Keep it clean!
Remove-SSHSession -SessionId 0
sleep 2

Write-Output "Verifying SSH has been disabled!"
#Check that the service is, in fact, disabled.
Get-VMHost | Get-VMHostService | Where { $_.Key -eq "TSM-SSH" } |select VMHost, Label, Running
sleep 2

Write-Output "Put host in MM to begin the upgrade!"
#Put host in MM so the upgrade can begin:
Get-VMHost -Name $esxihost | set-vmhost -State Maintenance
sleep 2

Write-Output "Installing ESXi Upgrade!"
#Install ESXi Update on the host:
Get-VMHost -Name $esxihost | Install-VMHostPatch -HostPath $hostpath
sleep 2

Write-Output "The upgrade has been installed, restarting the host!"
#restart the host!
Restart-VMHost -VMHost $esxihost
sleep 2

Write-Output "Check the host version!"
#Check host version while it is rebooting:
Get-VMHost | Select @{Label = "Host"; Expression = {$_.Name}} , @{Label = "ESX Version"; Expression = {$_.version}}, @{Label = "ESX Build" ; Expression = {$_.build}}
sleep 2

Write-Output "Trying to bring the host out of MM!"
# bring the host out of maintenance mode!!!!
Get-VMHost -Name $esxihost | set-vmhost -State Connected
sleep 2

Write-Output "Disconnect from vCenter!"
#Disconnect from vCenter
Disconnect-VIServer -Server $vcenter
