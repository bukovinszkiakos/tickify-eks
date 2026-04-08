using Microsoft.AspNetCore.Identity;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Globalization;

namespace Tickify.Services.Authentication
{
    public class TokenService : ITokenService
    {
        private const int ExpirationMinutes = 30;
        private readonly IConfiguration _configuration;

        public TokenService(IConfiguration configuration)
        {
            _configuration = configuration;
        }

        public string CreateToken(IdentityUser user, List<string> roles)
        {
            var expiration = DateTime.UtcNow.AddMinutes(ExpirationMinutes);
            var claims = CreateClaims(user, roles);

            claims.Add(new Claim("exp", ((DateTimeOffset)expiration).ToUnixTimeSeconds().ToString()));

            var signingCredentials = CreateSigningCredentials();
            var token = new JwtSecurityToken(
                issuer: _configuration["Jwt:ValidIssuer"],
                audience: _configuration["Jwt:ValidAudience"],
                claims: claims,
                expires: expiration,
                signingCredentials: signingCredentials
            );

            return new JwtSecurityTokenHandler().WriteToken(token);
        }

        private List<Claim> CreateClaims(IdentityUser user, List<string> roles)
        {
            var claims = new List<Claim>
            {
                new Claim(JwtRegisteredClaimNames.Sub, user.Id),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
                new Claim(JwtRegisteredClaimNames.Iat,
                    EpochTime.GetIntDate(DateTime.UtcNow).ToString(CultureInfo.InvariantCulture), ClaimValueTypes.Integer64),
                new Claim(ClaimTypes.NameIdentifier, user.Id),
                new Claim(ClaimTypes.Name, user.UserName),
                new Claim(ClaimTypes.Email, user.Email)
            };

            foreach (var role in roles)
            {
                claims.Add(new Claim(ClaimTypes.Role, role));
            }

            return claims;
        }

        private SigningCredentials CreateSigningCredentials()
        {
            var key = Encoding.UTF8.GetBytes(_configuration["Jwt:IssuerSigningKey"]);
            return new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256);
        }
    }
}
