using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using System.Linq;
using System.Threading.Tasks;
using Tickify.DTOs;
using Tickify.Services;
using Tickify.Services.FileStorage;
using Microsoft.EntityFrameworkCore;
using Tickify.Context;

namespace Tickify.Controllers
{
    [ApiController]
    [Authorize(Roles = "Admin,SuperAdmin,User")]
    [Route("api/tickets/{ticketId}/comments")]
    public class TicketCommentsController : ControllerBase
    {
        private readonly ITicketCommentService _ticketCommentService;
        private readonly UserManager<IdentityUser> _userManager;
        private readonly ApplicationDbContext _dbContext;
        private readonly IFileStorageService _fileStorageService;

        public TicketCommentsController(
            ITicketCommentService ticketCommentService,
            UserManager<IdentityUser> userManager,
            ApplicationDbContext dbContext,
            IFileStorageService fileStorageService)
        {
            _ticketCommentService = ticketCommentService;
            _userManager = userManager;
            _dbContext = dbContext;
            _fileStorageService = fileStorageService;
        }

        private const long MaxImageBytes = 5_242_880;
        private static readonly HashSet<string> AllowedContentTypes = new() { "image/jpeg", "image/png", "image/gif", "image/webp" };
        private static readonly HashSet<string> AllowedExtensions = new() { ".jpg", ".jpeg", ".png", ".gif", ".webp" };

        private static (bool Valid, string Error) ValidateImage(IFormFile image)
        {
            if (image.Length > MaxImageBytes)
                return (false, "Image must not exceed 5 MB.");
            if (!AllowedContentTypes.Contains(image.ContentType.ToLowerInvariant()))
                return (false, "Unsupported image type. Allowed: JPEG, PNG, GIF, WebP.");
            var ext = Path.GetExtension(image.FileName).ToLowerInvariant();
            if (!AllowedExtensions.Contains(ext))
                return (false, "Unsupported file extension. Allowed: .jpg, .jpeg, .png, .gif, .webp.");
            return (true, string.Empty);
        }

        [HttpGet]
        public async Task<IActionResult> GetComments(int ticketId)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            var comments = await _ticketCommentService.GetCommentsByTicketIdAsync(ticketId);

            var newStatuses = comments
                .Where(c => !_dbContext.CommentReadStatuses
                    .Any(r => r.UserId == userId && r.CommentId == c.Id))
                .Select(c => new CommentReadStatus
                {
                    UserId = userId!,
                    CommentId = c.Id,
                    SeenAt = DateTime.UtcNow
                })
                .ToList();

            if (newStatuses.Any())
            {
                _dbContext.CommentReadStatuses.AddRange(newStatuses);
                await _dbContext.SaveChangesAsync();
            }

            var result = await Task.WhenAll(comments.Select(async c => new
            {
                c.Id,
                c.Comment,
                c.CreatedAt,
                ImageUrl = await _fileStorageService.GetFileUrlAsync(c.ImageUrl ?? ""),
                OldImageUrl = await _fileStorageService.GetFileUrlAsync(c.OldImageKey ?? ""),
                Commenter = !string.IsNullOrWhiteSpace(c.CommenterName) ? c.CommenterName : "Unknown"
            }));

            return Ok(result);
        }





        [HttpPost]
        public async Task<IActionResult> AddComment(int ticketId, [FromForm] string comment, [FromForm] IFormFile? image)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null)
                return Unauthorized("User not found in token.");

            string? imageUrl = null;

            if (image != null && image.Length > 0)
            {
                var (valid, error) = ValidateImage(image);
                if (!valid) return BadRequest(error);
                imageUrl = await _fileStorageService.UploadFileAsync(
                    image.OpenReadStream(),
                    image.FileName,
                    image.ContentType);
            }


            try
            {
                var username = User.FindFirst(ClaimTypes.Name)?.Value ?? "Unknown";
                await _ticketCommentService.AddCommentAsync(ticketId, comment, userId, username, imageUrl);
                return Ok(new { message = "Comment added successfully", imageUrl = await _fileStorageService.GetFileUrlAsync(imageUrl ?? "") });
            }
            catch (KeyNotFoundException ex)
            {
                if (!string.IsNullOrEmpty(imageUrl))
                {
                    try { await _fileStorageService.DeleteFileAsync(imageUrl); }
                    catch (Exception cleanupEx)
                    {
                        Console.Error.WriteLine($"S3 delete failed for key '{imageUrl}': {cleanupEx.Message}");
                    }
                }
                return NotFound(ex.Message);
            }
        }
    }
}
