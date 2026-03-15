Write-Host "Script Execution Started"

# Load necessary assemblies
Add-Type -Path "C:\Users\dthakur1\Downloads\Dependencies\Microsoft.IdentityModel.Tokens.dll"
Add-Type -Path "C:\Users\dthakur1\Downloads\Dependencies\Microsoft.IdentityModel.JsonWebTokens.dll"
Add-Type -Path "C:\Users\dthakur1\Downloads\Dependencies\System.IdentityModel.Tokens.Jwt.dll"
Add-Type -Path "C:\Users\dthakur1\Downloads\Dependencies\Microsoft.IdentityModel.Logging.dll"
Add-Type -Path "C:\Users\dthakur1\Downloads\Dependencies\Microsoft.IdentityModel.Abstractions.dll"

Write-Host "Assembilies Loaded"

Write-Host "Variables Initialized"

# Load certificate
$x509cert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($CertificatePath_Pfx, $CertPassWord)

Write-Host "Certificate Loaded"

# Create claims
$claims = @()

# Add claims to the array
$claims += New-Object System.Security.Claims.Claim("jti", [GUID]::NewGuid().ToString("D"))
$claims += New-Object System.Security.Claims.Claim("sub", $ClientId)
    
# $claims
    
# Create ClaimsIdentity
$claimsIdentity = New-Object System.Security.Claims.ClaimsIdentity($claims)
    
# $claimsIdentity
    
# Create signing credentials
$signingCredentials = [Microsoft.IdentityModel.Tokens.X509SigningCredentials]::new($x509cert)
    
# Create SecurityTokenDescriptor
$securityTokenDescriptor = New-Object Microsoft.IdentityModel.Tokens.SecurityTokenDescriptor
$securityTokenDescriptor.Subject = $claimsIdentity
$securityTokenDescriptor.Audience = $aud
$securityTokenDescriptor.Issuer = $ClientId
$securityTokenDescriptor.Expires = [DateTime]::UtcNow.AddMinutes(10)
$securityTokenDescriptor.SigningCredentials = $signingCredentials
    
    
Write-Host "SecurityTokenDescriptor Created"

# Create token handler
$tokenHandler = New-Object Microsoft.IdentityModel.JsonWebTokens.JsonWebTokenHandler
$tokenHandler

# Create token
$clientAssertion = $tokenHandler.CreateToken($securityTokenDescriptor)
$clientAssertion

