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

public class TicketsControllerImageValidationTests
{
    private static TicketsController BuildController(Mock<ITicketService> serviceMock, string role = "User")
    {
        var storeMock = new Mock<IUserStore<IdentityUser>>();
        var userManagerMock = new Mock<UserManager<IdentityUser>>(
            storeMock.Object, null, null, null, null, null, null, null, null);

        var controller = new TicketsController(serviceMock.Object, userManagerMock.Object);

        var httpContext = new DefaultHttpContext();
        httpContext.User = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, "user1"),
            new Claim(ClaimTypes.Role, role)
        }, "test"));

        controller.ControllerContext = new ControllerContext { HttpContext = httpContext };
        return controller;
    }

    private static IFormFile CreateFormFile(string fileName = "test.jpg", long length = 100, string contentType = "image/jpeg")
    {
        var fileMock = new Mock<IFormFile>();
        fileMock.Setup(f => f.Length).Returns(length);
        fileMock.Setup(f => f.FileName).Returns(fileName);
        fileMock.Setup(f => f.ContentType).Returns(contentType);
        fileMock.Setup(f => f.OpenReadStream()).Returns(new MemoryStream(new byte[(int)Math.Min(length, 1024)]));
        return fileMock.Object;
    }

    private static UpdateTicketDto ValidUpdateDto() => new()
    {
        Title = "T", Description = "D", Status = "Open", Priority = "Low"
    };

    [Fact]
    public async Task CreateTicket_OversizedImage_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.CreateTicket("title", "desc", "Low", CreateFormFile(length: 6_000_000));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.CreateTicketAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<IFormFile?>(),
            It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task CreateTicket_DisallowedContentType_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.CreateTicket("title", "desc", "Low", CreateFormFile(contentType: "application/zip"));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.CreateTicketAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<IFormFile?>(),
            It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task CreateTicket_DisallowedExtension_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.CreateTicket("title", "desc", "Low", CreateFormFile(fileName: "script.html"));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.CreateTicketAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<IFormFile?>(),
            It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task CreateTicket_ValidImage_PassesValidation_ServiceCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.CreateTicketAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<IFormFile?>(),
            It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync(new TicketDto { Id = 1, Title = "T", Description = "D", Status = "Open", Priority = "Low", CreatedBy = "user1" });

        var controller = BuildController(serviceMock);
        var result = await controller.CreateTicket("title", "desc", "Low", CreateFormFile());

        Assert.IsType<CreatedAtActionResult>(result);
        serviceMock.Verify(s => s.CreateTicketAsync(
            It.IsAny<string>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<bool>(), It.IsAny<IFormFile?>(),
            It.IsAny<string>(), It.IsAny<string>()), Times.Once);
    }

    [Fact]
    public async Task UpdateTicket_OversizedImage_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.UpdateTicket(1, ValidUpdateDto(), CreateFormFile(length: 6_000_000));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.UpdateTicketAsync(
            It.IsAny<int>(), It.IsAny<UpdateTicketDto>(), It.IsAny<string>(),
            It.IsAny<bool>(), It.IsAny<IFormFile?>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task UpdateTicket_DisallowedContentType_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.UpdateTicket(1, ValidUpdateDto(), CreateFormFile(contentType: "text/html"));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.UpdateTicketAsync(
            It.IsAny<int>(), It.IsAny<UpdateTicketDto>(), It.IsAny<string>(),
            It.IsAny<bool>(), It.IsAny<IFormFile?>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task UpdateTicket_DisallowedExtension_ReturnsBadRequest_ServiceNeverCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        var controller = BuildController(serviceMock);

        var result = await controller.UpdateTicket(1, ValidUpdateDto(), CreateFormFile(fileName: "payload.exe"));

        Assert.IsType<BadRequestObjectResult>(result);
        serviceMock.Verify(s => s.UpdateTicketAsync(
            It.IsAny<int>(), It.IsAny<UpdateTicketDto>(), It.IsAny<string>(),
            It.IsAny<bool>(), It.IsAny<IFormFile?>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task UpdateTicket_ValidImage_PassesValidation_ServiceCalled()
    {
        var serviceMock = new Mock<ITicketService>();
        serviceMock.Setup(s => s.UpdateTicketAsync(
            It.IsAny<int>(), It.IsAny<UpdateTicketDto>(), It.IsAny<string>(),
            It.IsAny<bool>(), It.IsAny<IFormFile?>(), It.IsAny<string>(), It.IsAny<string>()))
            .Returns(Task.CompletedTask);

        var controller = BuildController(serviceMock, role: "Admin");
        var result = await controller.UpdateTicket(1, ValidUpdateDto(), CreateFormFile());

        Assert.IsType<OkObjectResult>(result);
        serviceMock.Verify(s => s.UpdateTicketAsync(
            It.IsAny<int>(), It.IsAny<UpdateTicketDto>(), It.IsAny<string>(),
            It.IsAny<bool>(), It.IsAny<IFormFile?>(), It.IsAny<string>(), It.IsAny<string>()), Times.Once);
    }
}
