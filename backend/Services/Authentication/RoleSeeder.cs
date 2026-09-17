using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using System;
using System.Threading.Tasks;

namespace Tickify.Services.Authentication
{
    public class RoleSeeder
    {
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly UserManager<IdentityUser> _userManager;
        // AI modernization: IConfiguration injected to read seed passwords from environment variables
        private readonly IConfiguration _configuration;

        public RoleSeeder(RoleManager<IdentityRole> roleManager, UserManager<IdentityUser> userManager, IConfiguration configuration)
        {
            _roleManager = roleManager;
            _userManager = userManager;
            _configuration = configuration;
        }

        public async Task SeedRolesAndAdminAsync()
        {
            if (!await _roleManager.RoleExistsAsync("SuperAdmin"))
            {
                await _roleManager.CreateAsync(new IdentityRole("SuperAdmin"));
            }

            if (!await _roleManager.RoleExistsAsync("Admin"))
            {
                await _roleManager.CreateAsync(new IdentityRole("Admin"));
            }

            if (!await _roleManager.RoleExistsAsync("User"))
            {
                await _roleManager.CreateAsync(new IdentityRole("User"));
            }


            var adminEmail = "admin@admin.com";
            var adminUser = await _userManager.FindByEmailAsync(adminEmail);

            // AI modernization: passwords read from env vars (SEEDING__ADMINPASSWORD / SEEDING__SUPERADMINPASSWORD) — startup fails clearly if missing
            var adminPassword = _configuration["Seeding:AdminPassword"]
                ?? throw new InvalidOperationException(
                    "Seeding:AdminPassword is not configured. Set the SEEDING__ADMINPASSWORD environment variable.");

            var superAdminPassword = _configuration["Seeding:SuperAdminPassword"]
                ?? throw new InvalidOperationException(
                    "Seeding:SuperAdminPassword is not configured. Set the SEEDING__SUPERADMINPASSWORD environment variable.");

            if (adminUser == null)
            {
                var newAdmin = new IdentityUser
                {
                    UserName = "AdminUser",
                    Email = adminEmail,
                    EmailConfirmed = true
                };

                var result = await _userManager.CreateAsync(newAdmin, adminPassword);
                if (result.Succeeded)
                {
                    await _userManager.AddToRoleAsync(newAdmin, "Admin");
                }
            }

            var superAdminEmail = "super@admin.com";
            var superAdminUser = await _userManager.FindByEmailAsync(superAdminEmail);

            if (superAdminUser == null)
            {
                var newSuperAdmin = new IdentityUser
                {
                    UserName = "SuperAdmin",
                    Email = superAdminEmail,
                    EmailConfirmed = true
                };

                var result = await _userManager.CreateAsync(newSuperAdmin, superAdminPassword);

                if (result.Succeeded)
                {
                    await _userManager.AddToRoleAsync(newSuperAdmin, "SuperAdmin");
                }
            }

        }
    }
}
