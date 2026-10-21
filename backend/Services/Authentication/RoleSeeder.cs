using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System;
using System.Threading.Tasks;

namespace Tickify.Services.Authentication
{
    public class RoleSeeder
    {
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly UserManager<IdentityUser> _userManager;
        private readonly IConfiguration _configuration;
        private readonly ILogger<RoleSeeder> _logger;

        public RoleSeeder(
            RoleManager<IdentityRole> roleManager,
            UserManager<IdentityUser> userManager,
            IConfiguration configuration,
            ILogger<RoleSeeder> logger)
        {
            _roleManager = roleManager;
            _userManager = userManager;
            _configuration = configuration;
            _logger = logger;
        }

        public async Task SeedRolesAndAdminAsync()
        {
            foreach (var role in new[] { "SuperAdmin", "Admin", "User" })
            {
                if (!await _roleManager.RoleExistsAsync(role))
                {
                    var result = await _roleManager.CreateAsync(new IdentityRole(role));
                    if (!result.Succeeded)
                        _logger.LogError("Failed to create role '{Role}': {Errors}",
                            role, FormatErrors(result));
                }
            }

            var adminPassword = _configuration["Seeding:AdminPassword"]
                ?? throw new InvalidOperationException(
                    "Seeding:AdminPassword is not configured. Set the SEEDING__ADMINPASSWORD environment variable.");

            var superAdminPassword = _configuration["Seeding:SuperAdminPassword"]
                ?? throw new InvalidOperationException(
                    "Seeding:SuperAdminPassword is not configured. Set the SEEDING__SUPERADMINPASSWORD environment variable.");

            bool resetPasswords = _configuration.GetValue<bool>("Seeding:ResetPasswords", false);

            await EnsureAdminAsync("admin@admin.com",    "AdminUser", "Admin",      adminPassword,      resetPasswords);
            await EnsureAdminAsync("super@admin.com",    "SuperAdmin", "SuperAdmin", superAdminPassword, resetPasswords);
        }

        private async Task EnsureAdminAsync(
            string email, string username, string role, string password, bool resetPassword)
        {
            var user = await _userManager.FindByEmailAsync(email);

            if (user == null)
            {
                var newUser = new IdentityUser
                {
                    UserName = username,
                    Email = email,
                    EmailConfirmed = true
                };

                var result = await _userManager.CreateAsync(newUser, password);
                if (!result.Succeeded)
                {
                    _logger.LogError("Failed to create {Email}: {Errors}", email, FormatErrors(result));
                    return;
                }

                user = newUser;
            }
            else if (resetPassword)
            {
                // GeneratePasswordResetTokenAsync + ResetPasswordAsync bypasses the old-password
                // requirement and goes through Identity's password validators.
                //
                // Concurrency note: this is idempotent in outcome (password ends up as the
                // configured value regardless of how many pods run it), but it is NOT
                // exactly-once. If two pods generate tokens concurrently and Pod A completes
                // first, the SecurityStamp changes and Pod B's token becomes invalid — producing
                // an InvalidToken warning rather than an error. The final state is still correct.
                var token = await _userManager.GeneratePasswordResetTokenAsync(user);
                var result = await _userManager.ResetPasswordAsync(user, token, password);

                if (result.Succeeded)
                {
                    _logger.LogInformation("Password reset for {Email}", email);
                }
                else if (result.Errors.Any(e => e.Code == "InvalidToken"))
                {
                    _logger.LogWarning(
                        "Password reset token was invalid for {Email}. " +
                        "Another pod instance may have already completed the reset.",
                        email);
                }
                else
                {
                    _logger.LogError("Failed to reset password for {Email}: {Errors}",
                        email, FormatErrors(result));
                }
            }

            // Idempotent role repair: runs on every startup for both new and existing users.
            if (!await _userManager.IsInRoleAsync(user, role))
            {
                var result = await _userManager.AddToRoleAsync(user, role);
                if (!result.Succeeded)
                    _logger.LogError("Failed to add {Email} to role '{Role}': {Errors}",
                        email, role, FormatErrors(result));
            }
        }

        private static string FormatErrors(IdentityResult result) =>
            string.Join("; ", result.Errors.Select(e => $"{e.Code}: {e.Description}"));
    }
}
