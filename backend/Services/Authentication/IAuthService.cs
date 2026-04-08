using Tickify.Contracts;

namespace Tickify.Services.Authentication
{
    public interface IAuthService
    {
        Task<AuthResult> RegisterAsync(string email, string username, string password, string role = "User");
        Task<AuthResult> LoginAsync(string email, string password);
    }

}
