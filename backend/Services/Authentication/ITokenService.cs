using Microsoft.AspNetCore.Identity;

namespace Tickify.Services.Authentication
{
    public interface ITokenService
    {
        string CreateToken(IdentityUser user, List<string> roles);
    }
}
