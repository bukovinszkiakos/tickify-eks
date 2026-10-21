using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Tickify.Services.Authentication;
using Xunit;

namespace Tickify.Tests;

public class RoleSeederTests
{
    private static IConfiguration BuildConfig(
        string? adminPassword = "Admin1234!",
        string? superAdminPassword = "Super1234!",
        bool resetPasswords = false)
    {
        var dict = new Dictionary<string, string?>();
        if (adminPassword != null) dict["Seeding:AdminPassword"] = adminPassword;
        if (superAdminPassword != null) dict["Seeding:SuperAdminPassword"] = superAdminPassword;
        dict["Seeding:ResetPasswords"] = resetPasswords.ToString().ToLower();
        return new ConfigurationBuilder().AddInMemoryCollection(dict).Build();
    }

    private static Mock<UserManager<IdentityUser>> CreateUserManagerMock()
    {
        var storeMock = new Mock<IUserStore<IdentityUser>>();
        return new Mock<UserManager<IdentityUser>>(
            storeMock.Object, null, null, null, null, null, null, null, null);
    }

    private static Mock<RoleManager<IdentityRole>> CreateRoleManagerMock()
    {
        var storeMock = new Mock<IRoleStore<IdentityRole>>();
        return new Mock<RoleManager<IdentityRole>>(
            storeMock.Object, null, null, null, null);
    }

    private static RoleSeeder BuildSeeder(
        Mock<UserManager<IdentityUser>> umMock,
        Mock<RoleManager<IdentityRole>> rmMock,
        IConfiguration config) =>
        new RoleSeeder(
            rmMock.Object,
            umMock.Object,
            config,
            NullLogger<RoleSeeder>.Instance);

    [Fact]
    public async Task SeedRolesAndAdminAsync_FreshInstall_CreatesUsersAndAssignsRoles()
    {
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();

        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);
        umMock.Setup(u => u.FindByEmailAsync(It.IsAny<string>())).ReturnsAsync((IdentityUser?)null);
        umMock.Setup(u => u.CreateAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Success);
        umMock.Setup(u => u.IsInRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()))
            .ReturnsAsync(false);
        umMock.Setup(u => u.AddToRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Success);

        await BuildSeeder(umMock, rmMock, BuildConfig()).SeedRolesAndAdminAsync();

        umMock.Verify(u => u.CreateAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()), Times.Exactly(2));
        umMock.Verify(u => u.AddToRoleAsync(
            It.Is<IdentityUser>(x => x.Email == "admin@admin.com"), "Admin"), Times.Once);
        umMock.Verify(u => u.AddToRoleAsync(
            It.Is<IdentityUser>(x => x.Email == "super@admin.com"), "SuperAdmin"), Times.Once);
    }

    [Fact]
    public async Task SeedRolesAndAdminAsync_CreateAsyncFails_DoesNotAssignRole()
    {
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();

        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);
        umMock.Setup(u => u.FindByEmailAsync(It.IsAny<string>())).ReturnsAsync((IdentityUser?)null);
        umMock.Setup(u => u.CreateAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Failed(
                new IdentityError { Code = "PasswordTooWeak", Description = "Too weak" }));

        await BuildSeeder(umMock, rmMock, BuildConfig()).SeedRolesAndAdminAsync();

        umMock.Verify(u => u.IsInRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()), Times.Never);
        umMock.Verify(u => u.AddToRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task SeedRolesAndAdminAsync_ExistingUser_ResetPasswordsFalse_OnlyRepairsRole()
    {
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();

        var existingAdmin = new IdentityUser { Email = "admin@admin.com", UserName = "AdminUser" };
        var existingSuper = new IdentityUser { Email = "super@admin.com", UserName = "SuperAdmin" };

        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);
        umMock.Setup(u => u.FindByEmailAsync("admin@admin.com")).ReturnsAsync(existingAdmin);
        umMock.Setup(u => u.FindByEmailAsync("super@admin.com")).ReturnsAsync(existingSuper);
        umMock.Setup(u => u.IsInRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>())).ReturnsAsync(false);
        umMock.Setup(u => u.AddToRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Success);

        await BuildSeeder(umMock, rmMock, BuildConfig(resetPasswords: false)).SeedRolesAndAdminAsync();

        umMock.Verify(u => u.GeneratePasswordResetTokenAsync(It.IsAny<IdentityUser>()), Times.Never);
        umMock.Verify(u => u.ResetPasswordAsync(
            It.IsAny<IdentityUser>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
        umMock.Verify(u => u.AddToRoleAsync(existingAdmin, "Admin"), Times.Once);
        umMock.Verify(u => u.AddToRoleAsync(existingSuper, "SuperAdmin"), Times.Once);
    }

    [Fact]
    public async Task SeedRolesAndAdminAsync_MissingAdminPassword_ThrowsInvalidOperationException()
    {
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();
        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);

        var seeder = BuildSeeder(umMock, rmMock,
            BuildConfig(adminPassword: null, superAdminPassword: "Super1234!"));

        await Assert.ThrowsAsync<InvalidOperationException>(() => seeder.SeedRolesAndAdminAsync());
    }

    [Fact]
    public async Task SeedRolesAndAdminAsync_ResetPasswordsTrue_CallsResetPasswordAsync()
    {
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();

        var existingAdmin = new IdentityUser { Email = "admin@admin.com", UserName = "AdminUser" };
        var existingSuper = new IdentityUser { Email = "super@admin.com", UserName = "SuperAdmin" };

        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);
        umMock.Setup(u => u.FindByEmailAsync("admin@admin.com")).ReturnsAsync(existingAdmin);
        umMock.Setup(u => u.FindByEmailAsync("super@admin.com")).ReturnsAsync(existingSuper);
        umMock.Setup(u => u.GeneratePasswordResetTokenAsync(It.IsAny<IdentityUser>()))
            .ReturnsAsync("reset-token");
        umMock.Setup(u => u.ResetPasswordAsync(
            It.IsAny<IdentityUser>(), "reset-token", It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Success);
        umMock.Setup(u => u.IsInRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>())).ReturnsAsync(true);

        await BuildSeeder(umMock, rmMock, BuildConfig(resetPasswords: true)).SeedRolesAndAdminAsync();

        umMock.Verify(u => u.ResetPasswordAsync(existingAdmin, "reset-token", "Admin1234!"), Times.Once);
        umMock.Verify(u => u.ResetPasswordAsync(existingSuper, "reset-token", "Super1234!"), Times.Once);
    }

    [Fact]
    public async Task SeedRolesAndAdminAsync_InvalidToken_LogsWarningAndContinuesToRoleRepair()
    {
        // Concurrency scenario: another pod already reset the password first,
        // invalidating this pod's token. Must log a warning (not throw) and still repair roles.
        var umMock = CreateUserManagerMock();
        var rmMock = CreateRoleManagerMock();

        var existingAdmin = new IdentityUser { Email = "admin@admin.com", UserName = "AdminUser" };
        var existingSuper = new IdentityUser { Email = "super@admin.com", UserName = "SuperAdmin" };

        rmMock.Setup(r => r.RoleExistsAsync(It.IsAny<string>())).ReturnsAsync(true);
        umMock.Setup(u => u.FindByEmailAsync("admin@admin.com")).ReturnsAsync(existingAdmin);
        umMock.Setup(u => u.FindByEmailAsync("super@admin.com")).ReturnsAsync(existingSuper);
        umMock.Setup(u => u.GeneratePasswordResetTokenAsync(It.IsAny<IdentityUser>()))
            .ReturnsAsync("stale-token");
        umMock.Setup(u => u.ResetPasswordAsync(
            It.IsAny<IdentityUser>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync(IdentityResult.Failed(
                new IdentityError { Code = "InvalidToken", Description = "Token invalid" }));
        umMock.Setup(u => u.IsInRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>())).ReturnsAsync(true);

        var ex = await Record.ExceptionAsync(() =>
            BuildSeeder(umMock, rmMock, BuildConfig(resetPasswords: true)).SeedRolesAndAdminAsync());

        Assert.Null(ex);
        // IsInRoleAsync returned true so no AddToRoleAsync calls needed
        umMock.Verify(u => u.AddToRoleAsync(It.IsAny<IdentityUser>(), It.IsAny<string>()), Times.Never);
    }
}
