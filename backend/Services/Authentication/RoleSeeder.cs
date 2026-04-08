using Microsoft.AspNetCore.Identity;
using System;
using System.Threading.Tasks;

namespace Tickify.Services.Authentication
{
    public class RoleSeeder
    {
        private readonly RoleManager<IdentityRole> _roleManager;
        private readonly UserManager<IdentityUser> _userManager;

        public RoleSeeder(RoleManager<IdentityRole> roleManager, UserManager<IdentityUser> userManager)
        {
            _roleManager = roleManager;
            _userManager = userManager;
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

            if (adminUser == null)
            {
                var newAdmin = new IdentityUser
                {
                    UserName = "AdminUser",
                    Email = adminEmail,
                    EmailConfirmed = true
                };

                var result = await _userManager.CreateAsync(newAdmin, "Admin123!"); 
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

                var result = await _userManager.CreateAsync(newSuperAdmin, "Super123!");

                if (result.Succeeded)
                {
                    await _userManager.AddToRoleAsync(newSuperAdmin, "SuperAdmin");
                }
            }

        }
    }
}
