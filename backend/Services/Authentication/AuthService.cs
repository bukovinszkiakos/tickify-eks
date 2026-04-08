using Microsoft.AspNetCore.Identity;
using Tickify.Contracts;

namespace Tickify.Services.Authentication
{
    public class AuthService : IAuthService
    {
        private readonly UserManager<IdentityUser> _userManager;
        private readonly ITokenService _tokenService;

        public AuthService(UserManager<IdentityUser> userManager, ITokenService tokenService)
        {
            _userManager = userManager;
            _tokenService = tokenService;
        }

        public async Task<AuthResult> RegisterAsync(string email, string username, string password, string role = "User")
        {
            var user = new IdentityUser { UserName = username, Email = email };
            var result = await _userManager.CreateAsync(user, password);

            if (!result.Succeeded)
            {
                var authResult = new AuthResult(false, email, username, "");
                foreach (var error in result.Errors)
                {
                    authResult.ErrorMessages.Add(error.Code, error.Description);
                }
                return authResult;
            }

            await _userManager.AddToRoleAsync(user, role);

            return new AuthResult(true, email, username, "");
        }

        public async Task<AuthResult> LoginAsync(string email, string password)
        {
            var user = await _userManager.FindByEmailAsync(email);
            if (user == null)
            {
                var authResult = new AuthResult(false, email, "", "");
                authResult.ErrorMessages.Add("BadCredentials", "Invalid email");
                return authResult;
            }

            var isPasswordValid = await _userManager.CheckPasswordAsync(user, password);
            if (!isPasswordValid)
            {
                var authResult = new AuthResult(false, email, user.UserName, "");
                authResult.ErrorMessages.Add("BadCredentials", "Invalid password");
                return authResult;
            }

            var roles = await _userManager.GetRolesAsync(user);

            var token = _tokenService.CreateToken(user, roles.ToList());

            return new AuthResult(true, user.Email, user.UserName, token);
        }
    }
}
