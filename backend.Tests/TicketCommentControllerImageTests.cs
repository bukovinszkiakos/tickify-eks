using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Moq;
using System.Security.Claims;
using Tickify.Context;
using Tickify.Controllers;
using Tickify.Services;
using Tickify.Services.FileStorage;
using Xunit;

namespace Tickify.Tests;

public class TicketCommentControllerImageTests
{
    private static TicketCommentsController BuildController(
        Mock<ITicketCommentService> commentServiceMock,
        Mock<IFileStorageService> fsMock,
        string userId = "user1",
        string userName = "username1")
    {
        var dbOptions = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        var dbContext = new ApplicationDbContext(dbOptions);

        var storeMock = new Mock<IUserStore<IdentityUser>>();
        var userManagerMock = new Mock<UserManager<IdentityUser>>(
            storeMock.Object, null, null, null, null, null, null, null, null);

        var controller = new TicketCommentsController(
            commentServiceMock.Object,
            userManagerMock.Object,
            dbContext,
            fsMock.Object);

        var httpContext = new DefaultHttpContext();
        httpContext.User = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, userId),
            new Claim(ClaimTypes.Name, userName)
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

    [Fact]
    public async Task AddComment_ImageUploadedButTicketNotFound_DeletesS3Key()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("img/test.jpg");
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string?>()))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>())).Returns(Task.CompletedTask);

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(99, "hello", CreateFormFile());

        Assert.IsType<NotFoundObjectResult>(result);
        fsMock.Verify(s => s.DeleteFileAsync("img/test.jpg"), Times.Once);
    }

    [Fact]
    public async Task AddComment_ImageUploadedButTicketNotFound_CleanupFails_StillReturns404()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("img/test.jpg");
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string?>()))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>())).ThrowsAsync(new Exception("S3 error"));

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(99, "hello", CreateFormFile());

        Assert.IsType<NotFoundObjectResult>(result);
    }

    [Fact]
    public async Task AddComment_NoImage_TicketNotFound_DoesNotCallDeleteFileAsync()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string?>()))
            .ThrowsAsync(new KeyNotFoundException("Ticket not found."));

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(99, "hello", null);

        Assert.IsType<NotFoundObjectResult>(result);
        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task AddComment_OversizedImage_ReturnsBadRequest_UploadNeverCalled()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(1, "hello", CreateFormFile(length: 6_000_000));

        Assert.IsType<BadRequestObjectResult>(result);
        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task AddComment_DisallowedContentType_ReturnsBadRequest_UploadNeverCalled()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(1, "hello", CreateFormFile(contentType: "application/octet-stream"));

        Assert.IsType<BadRequestObjectResult>(result);
        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task AddComment_DisallowedExtension_ReturnsBadRequest_UploadNeverCalled()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(1, "hello", CreateFormFile(fileName: "payload.exe"));

        Assert.IsType<BadRequestObjectResult>(result);
        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task AddComment_ValidImage_UploadsAndSucceeds()
    {
        var commentMock = new Mock<ITicketCommentService>();
        var fsMock = new Mock<IFileStorageService>();

        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("img/valid.jpg");
        fsMock.Setup(s => s.GetFileUrlAsync(It.IsAny<string>(), It.IsAny<int>()))
            .ReturnsAsync("https://cdn.example.com/img/valid.jpg");
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var controller = BuildController(commentMock, fsMock);
        var result = await controller.AddComment(1, "hello", CreateFormFile());

        Assert.IsType<OkObjectResult>(result);
        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Once);
    }
}
