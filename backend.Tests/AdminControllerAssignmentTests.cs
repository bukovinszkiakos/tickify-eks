using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Moq;
using System.Security.Claims;
using Tickify.Controllers;
using Tickify.DTOs;
using Tickify.Services;
using Xunit;

namespace Tickify.Tests;

public class AdminControllerAssignmentTests
{
    private static AdminController BuildController(Mock<ITicketService> serviceMock, string role = "Admin")
    {
        var storeMock = new Mock<IUserStore<IdentityUser>>();
        var userManagerMock = new Mock<UserManager<IdentityUser>>(
            storeMock.Object, null, null, null, null, null, null, null, null);

        var controller = new AdminController(userManagerMock.Object, serviceMock.Object);

        var claims = new List<Claim>
        {
            new Claim(ClaimTypes.NameIdentifier, "admin1"),
            new Claim(ClaimTypes.Role, role)
        };

        var httpContext = new DefaultHttpContext();
        httpContext.User = new ClaimsPrincipal(new ClaimsIdentity(claims, "test"));

        controller.ControllerContext = new ControllerContext { HttpContext = httpContext };
        return controller;
    }

    [Fact]
    public async Task AssignToMe_UnassignedTicket_Admin_ReturnsOk()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin1", false))
            .Returns(Task.CompletedTask);
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.AssignToMe(1);

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.AssignTicketToAdminAsync(1, "admin1", false), Times.Once);
    }

    [Fact]
    public async Task AssignToMe_TicketAssignedToAnother_Admin_Returns409()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin1", false))
            .ThrowsAsync(new InvalidOperationException("Ticket is already assigned to another admin."));
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.AssignToMe(1);

        Assert.IsType<ConflictObjectResult>(result);
    }

    [Fact]
    public async Task AssignToMe_TicketNotFound_Returns404()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin1", false))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.AssignToMe(1);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task AssignToMe_SuperAdmin_CallsServiceWithSuperAdminTrue()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin1", true))
            .Returns(Task.CompletedTask);
        var controller = BuildController(serviceMock, "SuperAdmin");

        var result = await controller.AssignToMe(1);

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.AssignTicketToAdminAsync(1, "admin1", true), Times.Once);
    }

    [Fact]
    public async Task AssignTicket_SuperAdmin_CallsServiceWithSuperAdminTrue()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin2", true))
            .Returns(Task.CompletedTask);
        var controller = BuildController(serviceMock, "SuperAdmin");
        var dto = new AssignTicketDto { AdminUserId = "admin2" };

        var result = await controller.ReassignTicket(1, dto);

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.AssignTicketToAdminAsync(1, "admin2", true), Times.Once);
    }

    [Fact]
    public async Task AssignTicket_TicketNotFound_SuperAdmin_Returns404()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.AssignTicketToAdminAsync(1, "admin2", true))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));
        var controller = BuildController(serviceMock, "SuperAdmin");
        var dto = new AssignTicketDto { AdminUserId = "admin2" };

        var result = await controller.ReassignTicket(1, dto);

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task ReassignTicket_UnauthorizedCaller_Returns403()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.ReassignTicketAsync(1, It.IsAny<string?>(), "admin1"))
            .ThrowsAsync(new UnauthorizedAccessException("Only the assigned admin or a SuperAdmin can reassign this ticket."));
        var controller = BuildController(serviceMock, "Admin");
        var dto = new ReassignTicketDto { NewAdminId = "admin2" };

        var result = await controller.ReassignTicket(1, dto);

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, statusResult.StatusCode);
    }

    [Fact]
    public async Task ReleaseTicket_OwnTicket_Admin_ReturnsOk()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.ReleaseTicketAsync(1, "admin1", false))
            .Returns(Task.CompletedTask);
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.ReleaseTicket(1);

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.ReleaseTicketAsync(1, "admin1", false), Times.Once);
    }

    [Fact]
    public async Task ReleaseTicket_AnotherAdminsTicket_Admin_Returns403()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.ReleaseTicketAsync(1, "admin1", false))
            .ThrowsAsync(new UnauthorizedAccessException("Only the assigned admin or a SuperAdmin can release this ticket."));
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.ReleaseTicket(1);

        var statusResult = Assert.IsType<ObjectResult>(result);
        Assert.Equal(403, statusResult.StatusCode);
    }

    [Fact]
    public async Task ReleaseTicket_AnyTicket_SuperAdmin_ReturnsOk()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.ReleaseTicketAsync(1, "admin1", true))
            .Returns(Task.CompletedTask);
        var controller = BuildController(serviceMock, "SuperAdmin");

        var result = await controller.ReleaseTicket(1);

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.ReleaseTicketAsync(1, "admin1", true), Times.Once);
    }

    [Fact]
    public async Task ReleaseTicket_TicketNotFound_Returns404()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.ReleaseTicketAsync(1, "admin1", false))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));
        var controller = BuildController(serviceMock, "Admin");

        var result = await controller.ReleaseTicket(1);

        Assert.IsType<NotFoundObjectResult>(result);
    }
}
