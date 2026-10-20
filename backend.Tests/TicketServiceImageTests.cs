using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Moq;
using Tickify.Context;
using Tickify.DTOs;
using Tickify.Models;
using Tickify.Repositories;
using Tickify.Services;
using Tickify.Services.FileStorage;
using Xunit;

namespace Tickify.Tests;

public class TicketServiceImageTests
{
    private static TicketService BuildService(
        Mock<ITicketRepository> repoMock,
        Mock<IFileStorageService> fsMock,
        Mock<ITicketCommentService>? commentMock = null,
        Mock<UserManager<IdentityUser>>? userManagerMock = null)
    {
        var dbOptions = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase(Guid.NewGuid().ToString())
            .Options;
        var dbContext = new ApplicationDbContext(dbOptions);

        if (userManagerMock == null)
        {
            var storeMock = new Mock<IUserStore<IdentityUser>>();
            userManagerMock = new Mock<UserManager<IdentityUser>>(
                storeMock.Object, null, null, null, null, null, null, null, null);
        }

        if (commentMock == null)
        {
            commentMock = new Mock<ITicketCommentService>();
            commentMock.Setup(c => c.AddCommentAsync(
                It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
                It.IsAny<string>(), It.IsAny<string?>()))
                .Returns(Task.CompletedTask);
        }

        return new TicketService(
            repoMock.Object,
            userManagerMock.Object,
            commentMock.Object,
            dbContext,
            new Mock<IHttpContextAccessor>().Object,
            fsMock.Object);
    }

    private static IFormFile CreateFormFile(string fileName = "test.jpg", long length = 100)
    {
        var fileMock = new Mock<IFormFile>();
        fileMock.Setup(f => f.Length).Returns(length);
        fileMock.Setup(f => f.FileName).Returns(fileName);
        fileMock.Setup(f => f.ContentType).Returns("image/jpeg");
        fileMock.Setup(f => f.OpenReadStream()).Returns(new MemoryStream(new byte[(int)length]));
        return fileMock.Object;
    }

    private static Mock<UserManager<IdentityUser>> CreateUserManagerMock(string userId, IdentityUser? returnUser = null)
    {
        var storeMock = new Mock<IUserStore<IdentityUser>>();
        var umMock = new Mock<UserManager<IdentityUser>>(
            storeMock.Object, null, null, null, null, null, null, null, null);
        umMock.Setup(u => u.FindByIdAsync(userId)).ReturnsAsync(returnUser);
        return umMock;
    }

    // ---- DeleteTicketImageAsync ----

    [Fact]
    public async Task DeleteTicketImageAsync_WithImage_DeletesS3KeyAfterDbCommit()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var callOrder = new List<string>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync())
            .Callback(() => callOrder.Add("save"))
            .Returns(Task.CompletedTask);
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>()))
            .Callback(() => callOrder.Add("delete"))
            .Returns(Task.CompletedTask);

        var svc = BuildService(repoMock, fsMock);
        var result = await svc.DeleteTicketImageAsync(1, "user1", false);

        Assert.True(result);
        Assert.Equal(new[] { "save", "delete" }, callOrder);
        fsMock.Verify(s => s.DeleteFileAsync("img/key.jpg"), Times.Once);
    }

    [Fact]
    public async Task DeleteTicketImageAsync_NoImage_ReturnsFalseWithoutS3Call()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = null };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);

        var svc = BuildService(repoMock, fsMock);
        var result = await svc.DeleteTicketImageAsync(1, "user1", false);

        Assert.False(result);
        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Never);
    }

    [Fact]
    public async Task DeleteTicketImageAsync_DbFails_DoesNotCallS3AndReturnsFalse()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).ThrowsAsync(new Exception("DB error"));

        var svc = BuildService(repoMock, fsMock);
        var result = await svc.DeleteTicketImageAsync(1, "user1", false);

        Assert.False(result);
        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task DeleteTicketImageAsync_S3Fails_ReturnsTrueAfterDbCommit()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>())).ThrowsAsync(new Exception("S3 error"));

        var svc = BuildService(repoMock, fsMock);
        var result = await svc.DeleteTicketImageAsync(1, "user1", false);

        Assert.True(result);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Once);
    }

    [Fact]
    public async Task DeleteTicketImageAsync_Unauthorized_ThrowsWithoutAnyS3OrDbCall()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "other-user", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);

        var svc = BuildService(repoMock, fsMock);
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            svc.DeleteTicketImageAsync(1, "test-user", false));

        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Never);
    }

    // ---- UpdateTicketAsync ----

    [Fact]
    public async Task UpdateTicketAsync_ImageReplaced_DeletesOldS3KeyAfterDbCommit()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var commentMock = new Mock<ITicketCommentService>();
        var callOrder = new List<string>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", Priority = "Low", CreatedBy = "user1", ImageUrl = "old-key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync())
            .Callback(() => callOrder.Add("save"))
            .Returns(Task.CompletedTask);
        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("new-key.jpg");
        fsMock.Setup(s => s.GetFileUrlAsync(It.IsAny<string>(), It.IsAny<int>()))
            .ReturnsAsync("https://presigned");
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>()))
            .Callback(() => callOrder.Add("delete"))
            .Returns(Task.CompletedTask);
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1", new IdentityUser { UserName = "user1" });
        var svc = BuildService(repoMock, fsMock, commentMock, umMock);
        var dto = new UpdateTicketDto { Title = "T", Description = "D", Status = "Open", Priority = "Low" };
        await svc.UpdateTicketAsync(1, dto, "user1", false, CreateFormFile(), "https", "localhost");

        Assert.Equal(new[] { "save", "delete" }, callOrder);
        fsMock.Verify(s => s.DeleteFileAsync("old-key.jpg"), Times.Once);
    }

    [Fact]
    public async Task UpdateTicketAsync_NoPriorImage_UploadsNewWithoutDeletingS3()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var commentMock = new Mock<ITicketCommentService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", Priority = "Low", CreatedBy = "user1", ImageUrl = null };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);
        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("new-key.jpg");
        fsMock.Setup(s => s.GetFileUrlAsync(It.IsAny<string>(), It.IsAny<int>()))
            .ReturnsAsync("https://presigned");
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1", new IdentityUser { UserName = "user1" });
        var svc = BuildService(repoMock, fsMock, commentMock, umMock);
        var dto = new UpdateTicketDto { Title = "T", Description = "D", Status = "Open", Priority = "Low" };
        await svc.UpdateTicketAsync(1, dto, "user1", false, CreateFormFile(), "https", "localhost");

        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Once);
        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task UpdateTicketAsync_NoNewImage_NoS3Activity()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var commentMock = new Mock<ITicketCommentService>();

        var ticket = new Ticket { Id = 1, Title = "Old", Description = "D", Priority = "Low", CreatedBy = "user1", ImageUrl = "existing-key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1", new IdentityUser { UserName = "user1" });
        var svc = BuildService(repoMock, fsMock, commentMock, umMock);
        var dto = new UpdateTicketDto { Title = "New", Description = "D", Status = "Open", Priority = "Low" };
        await svc.UpdateTicketAsync(1, dto, "user1", false, null, "https", "localhost");

        fsMock.Verify(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()), Times.Never);
        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task UpdateTicketAsync_S3DeleteFails_DoesNotPropagate()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var commentMock = new Mock<ITicketCommentService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", Priority = "Low", CreatedBy = "user1", ImageUrl = "old-key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);
        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("new-key.jpg");
        fsMock.Setup(s => s.GetFileUrlAsync(It.IsAny<string>(), It.IsAny<int>()))
            .ReturnsAsync("https://presigned");
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>())).ThrowsAsync(new Exception("S3 error"));
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1", new IdentityUser { UserName = "user1" });
        var svc = BuildService(repoMock, fsMock, commentMock, umMock);
        var dto = new UpdateTicketDto { Title = "T", Description = "D", Status = "Open", Priority = "Low" };
        var ex = await Record.ExceptionAsync(() =>
            svc.UpdateTicketAsync(1, dto, "user1", false, CreateFormFile(), "https", "localhost"));

        Assert.Null(ex);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Once);
    }

    [Fact]
    public async Task UpdateTicketAsync_DbFails_OldS3KeyNotDeleted()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var commentMock = new Mock<ITicketCommentService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", Priority = "Low", CreatedBy = "user1", ImageUrl = "old-key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).ThrowsAsync(new Exception("DB error"));
        fsMock.Setup(s => s.UploadFileAsync(It.IsAny<Stream>(), It.IsAny<string>(), It.IsAny<string>()))
            .ReturnsAsync("new-key.jpg");
        fsMock.Setup(s => s.GetFileUrlAsync(It.IsAny<string>(), It.IsAny<int>()))
            .ReturnsAsync("https://presigned");
        commentMock.Setup(c => c.AddCommentAsync(
            It.IsAny<int>(), It.IsAny<string>(), It.IsAny<string>(),
            It.IsAny<string>(), It.IsAny<string?>()))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1", new IdentityUser { UserName = "user1" });
        var svc = BuildService(repoMock, fsMock, commentMock, umMock);
        var dto = new UpdateTicketDto { Title = "T", Description = "D", Status = "Open", Priority = "Low" };
        await Assert.ThrowsAsync<Exception>(() =>
            svc.UpdateTicketAsync(1, dto, "user1", false, CreateFormFile(), "https", "localhost"));

        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    // ---- DeleteTicketAsync ----

    [Fact]
    public async Task DeleteTicketAsync_WithImage_DeletesS3KeyAfterDbCommit()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();
        var callOrder = new List<string>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync())
            .Callback(() => callOrder.Add("save"))
            .Returns(Task.CompletedTask);
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>()))
            .Callback(() => callOrder.Add("delete"))
            .Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1");
        var svc = BuildService(repoMock, fsMock, null, umMock);
        await svc.DeleteTicketAsync(1, "user1", false);

        Assert.Equal(new[] { "save", "delete" }, callOrder);
        fsMock.Verify(s => s.DeleteFileAsync("img/key.jpg"), Times.Once);
    }

    [Fact]
    public async Task DeleteTicketAsync_NoImage_DoesNotCallS3Delete()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = null };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);

        var umMock = CreateUserManagerMock("user1");
        var svc = BuildService(repoMock, fsMock, null, umMock);
        await svc.DeleteTicketAsync(1, "user1", false);

        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task DeleteTicketAsync_S3DeleteFails_DoesNotPropagate()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).Returns(Task.CompletedTask);
        fsMock.Setup(s => s.DeleteFileAsync(It.IsAny<string>())).ThrowsAsync(new Exception("S3 error"));

        var umMock = CreateUserManagerMock("user1");
        var svc = BuildService(repoMock, fsMock, null, umMock);
        var ex = await Record.ExceptionAsync(() => svc.DeleteTicketAsync(1, "user1", false));

        Assert.Null(ex);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Once);
    }

    [Fact]
    public async Task DeleteTicketAsync_DbFails_S3NotTouched()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "user1", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);
        repoMock.Setup(r => r.SaveChangesAsync()).ThrowsAsync(new Exception("DB error"));

        var umMock = CreateUserManagerMock("user1");
        var svc = BuildService(repoMock, fsMock, null, umMock);
        await Assert.ThrowsAsync<Exception>(() => svc.DeleteTicketAsync(1, "user1", false));

        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
    }

    [Fact]
    public async Task DeleteTicketAsync_Unauthorized_ThrowsWithoutAnyS3OrDbCall()
    {
        var repoMock = new Mock<ITicketRepository>();
        var fsMock = new Mock<IFileStorageService>();

        var ticket = new Ticket { Id = 1, Title = "T", Description = "D", CreatedBy = "other-user", ImageUrl = "img/key.jpg" };
        repoMock.Setup(r => r.GetTicketByIdAsync(1)).ReturnsAsync(ticket);

        var umMock = CreateUserManagerMock("test-user");
        var svc = BuildService(repoMock, fsMock, null, umMock);
        await Assert.ThrowsAsync<UnauthorizedAccessException>(() =>
            svc.DeleteTicketAsync(1, "test-user", false));

        fsMock.Verify(s => s.DeleteFileAsync(It.IsAny<string>()), Times.Never);
        repoMock.Verify(r => r.SaveChangesAsync(), Times.Never);
    }
}
