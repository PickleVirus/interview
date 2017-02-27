Configuration Main
{
param ( $nodeName,
        $containerUrl,
        $SASToken,
        $ApplicationName )

Import-DscResource -ModuleName PSDesiredStateConfiguration

Node $nodeName
  {
    
    WindowsFeature WebServerRole
    {
		Name = "Web-Server"
		Ensure = "Present"
    }
    WindowsFeature WebManagementConsole
    {
        Name = "Web-Mgmt-Console"
        Ensure = "Present"
    }
    WindowsFeature WebManagementService
    {
        Name = "Web-Mgmt-Service"
        Ensure = "Present"
    }
    WindowsFeature ASPNet45
    {
		Ensure = "Present"
		Name = "Web-Asp-Net45"
    }
    WindowsFeature HTTPRedirection
    {
        Name = "Web-Http-Redirect"
        Ensure = "Present"
    }
    WindowsFeature CustomLogging
    {
        Name = "Web-Custom-Logging"
        Ensure = "Present"
    }
    WindowsFeature LogginTools
    {
        Name = "Web-Log-Libraries"
        Ensure = "Present"
    }
    WindowsFeature RequestMonitor
    {
        Name = "Web-Request-Monitor"
        Ensure = "Present"
    }
    WindowsFeature Tracing
    {
        Name = "Web-Http-Tracing"
        Ensure = "Present"
    }
    WindowsFeature BasicAuthentication
    {
        Name = "Web-Basic-Auth"
        Ensure = "Present"
    }
    WindowsFeature WindowsAuthentication
    {
        Name = "Web-Windows-Auth"
        Ensure = "Present"
    }
    WindowsFeature ApplicationInitialization
    {
        Name = "Web-AppInit"
        Ensure = "Present"
    }

	Script DownloadWebDeploy
    {
        TestScript = {
            Test-Path "C:\WindowsAzure\WebDeploy_amd64_en-US.msi"
        }
        SetScript ={
            $source = "http://download.microsoft.com/download/0/1/D/01DC28EA-638C-4A22-A57B-4CEF97755C6C/WebDeploy_amd64_en-US.msi"
            $dest = "C:\WindowsAzure\WebDeploy_amd64_en-US.msi"
            Invoke-WebRequest $source -OutFile $dest
        }
        GetScript = { @{Result = "WebDeployDownload"} }
		DependsOn = "[WindowsFeature]WebServerRole"
    }

	Package InstallWebDeploy
    {
        Ensure = "Present"  
        Path  = "C:\WindowsAzure\WebDeploy_amd64_en-US.msi"
        Name = "Microsoft Web Deploy 3.6"
        ProductId = "{ED4CC1E5-043E-4157-8452-B5E533FE2BA1}"
		Arguments = "/quiet ADDLOCAL=ALL"
		DependsOn = "[Script]DownloadWebDeploy"
    }

    Service StartWebDeploy
    {
		Name = "WMSVC"
		StartupType = "Automatic"
		State = "Running"
		DependsOn = "[Package]InstallWebDeploy"
    }
    Script DownloadArtifacts
    {
        TestScript = {
            Test-Path "C:\WindowsAzure\Applications\$using:ApplicationName"
        }
        SetScript ={
            $logdata = $using:nodeName, $using:containerUrl, $using:SASToken, $using:ApplicationName
            $logdata > "C:\WindowsAzure\Applications\Log.txt"
            mkdir "C:\WindowsAzure\Applications\$using:ApplicationName"
            $deploymentTypes = ".deploy.cmd",".deploy-readme.txt",".SetParameters.xml",".SourceManifest.xml",".zip"
            foreach($type in $deploymentTypes){
                    $source = $using:containerUrl + "/" + $using:ApplicationName + $type + $using:SASToken
                    $dest = "C:\WindowsAzure\Applications\" + $Using:ApplicationName + "\" + $Using:ApplicationName + "$type"
                    Invoke-WebRequest $source -OutFile $dest >> "C:\WindowsAzure\Applications\Log.txt"
            }
        }
        GetScript = { @{Result = "ArtifactsDownload"} }
		DependsOn = "[Service]StartWebDeploy"
    }
    Script DeployApplication
    {
        TestScript = {
            
			return $false
        }
        SetScript ={
            
			Invoke-Command -ScriptBlock { & "C:\WindowsAzure\Applications\$using:ApplicationName\$using:ApplicationName.deploy.cmd" /Y}
			Remove-Item "C:\WindowsAzure\Applications\$using:ApplicationName" -Recurse -Force          			
            }
        
        GetScript = { @{Result = "ApplicationDeployed"} }
		DependsOn = "[Script]DownloadArtifacts"
    }
  }
}
