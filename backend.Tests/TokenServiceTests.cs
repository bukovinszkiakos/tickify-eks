using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using System.IdentityModel.Tokens.Jwt;
using Tickify.Services.Authentication;
using Xunit;

namespace Tickify.Tests;

public class TokenServiceTests
{
    [Fact]
    public void CreateToken_ExpClaimIsExactlyOneNumericValue()
    {
        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["Jwt:IssuerSigningKey"] = new string('a', 32),
                ["Jwt:ValidIssuer"] = "TestIssuer",
                ["Jwt:ValidAudience"] = "TestAudience"
            })
            .Build();

        var service = new TokenService(config);
        var user = new IdentityUser { Id = "u1", UserName = "testuser", Email = "test@test.com" };

        var token = service.CreateToken(user, new List<string> { "User" });

        var parsed = new JwtSecurityTokenHandler().ReadJwtToken(token);
        Assert.IsType<long>(parsed.Payload["exp"]);
    }
}
