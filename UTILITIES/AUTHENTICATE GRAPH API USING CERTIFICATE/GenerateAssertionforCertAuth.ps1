# Write-Host "Script Execution Started"

# Load necessary assemblies
Add-Type -Path "Dependencies\Microsoft.IdentityModel.Abstractions.dll"
Add-Type -Path "Dependencies\Microsoft.IdentityModel.JsonWebTokens.dll"
Add-Type -Path "Dependencies\System.IdentityModel.Tokens.Jwt.dll"
Add-Type -Path "Dependencies\Microsoft.IdentityModel.Logging.dll"
Add-Type -Path "Dependencies\Microsoft.IdentityModel.Abstractions.dll"

# Credentials
# $ClientID = "ClientID"
# $TenantID = "TenantID"
# $CertPassWord = "CertPassWord"
# $aud = "https://login.microsoftonline.com/$TenantID/v2.0/"
# $CertificatePath_Pfx = "CertificatePath_Pfx"

Function Get-ClientAssertion {

    $x509cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath_Pfx, $CertPassWord)
    $claims = new-object 'System.Collections.Generic.Dictionary[String, Object]'
    $claims['aud'] = $aud
    $claims['iss' ] = $ClientId
    $claims['sub'] = $ClientId
    $claims['jti'] = [GUID]::NewGuid().ToString('D')
                   
    $signingCredentials = [Microsoft.IdentityModel.Tokens.X509SigningCredentials]::new($x509cert)
    $securityTokenDescriptor = [Microsoft.IdentityModel.Tokens.SecurityTokenDescriptor]::new()
    $securityTokenDescriptor.Claims = $claims
    $securityTokenDescriptor.SigningCredentials = $signingCredentials 

    $tokenHandler = [Microsoft.IdentityModel.JsonWebTokens.JsonWebTokenHandler]::new()
    $clientAssertion = $tokenHandler.createToken($securityTokenDescriptor)
    write-host $clientAssertion
}  

$myvar = Get-ClientAssertion