using Azure;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using Tickify.Contracts;
using Tickify.Services.Authentication;

namespace Tickify.Controllers
{
    [ApiController]
    [Route("[controller]")]
    public class AuthController : ControllerBase
    {
        private readonly IAuthService _authService;

        public AuthController(IAuthService authService)
        {
            _authService = authService;
        }

        [HttpPost("Register")]
        public async Task<ActionResult<RegistrationResponse>> Register([FromBody] RegistrationRequest request)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var result = await _authService.RegisterAsync(request.Email, request.Username, request.Password, "User");

            if (!result.Success)
            {
                foreach (var error in result.ErrorMessages)
                {
                    ModelState.AddModelError(error.Key, error.Value);
                }
                return BadRequest(ModelState);
            }

            return CreatedAtAction(nameof(Register), new RegistrationResponse(result.Email, result.Username));
        }

        [HttpPost("Login")]
        public async Task<ActionResult<AuthResponse>> Login([FromBody] AuthRequest request)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var result = await _authService.LoginAsync(request.Email, request.Password);

            if (!result.Success)
            {
                foreach (var error in result.ErrorMessages)
                {
                    ModelState.AddModelError(error.Key, error.Value);
                }
                return BadRequest(ModelState);
            }

            Response.Cookies.Append("token", result.Token, new CookieOptions
            {
                HttpOnly = true,
                Secure = true,
                SameSite = SameSiteMode.Lax,
                Expires = DateTime.UtcNow.AddMinutes(30)
            });

            return Ok(new AuthResponse(result.Email, result.Username, result.Token));
        }

        [HttpPost("Logout")]
        public IActionResult Logout()
        {
            Response.Cookies.Delete("token");
            return Ok(new { message = "Logout successful" });
        }

        [HttpGet("Me")]
        public IActionResult Me()
        {
            var user = HttpContext.User;

            if (user?.Identity == null || !user.Identity.IsAuthenticated)
                return Unauthorized();

            var userId = user.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var email = user.FindFirst(ClaimTypes.Email)?.Value;
            var username = user.FindFirst(ClaimTypes.Name)?.Value;
            var roles = user.FindAll(ClaimTypes.Role).Select(r => r.Value).ToList();

            var expClaim = user.FindFirst("exp")?.Value;
            long expirationUnix = 0;
            if (!string.IsNullOrEmpty(expClaim))
            {
                long.TryParse(expClaim, out expirationUnix);
            }

            return Ok(new
            {
                id = userId,
                email,
                username,
                roles,
                expirationUnix
            });
        }



    }
}
