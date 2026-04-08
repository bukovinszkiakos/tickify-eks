using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using System.Linq;
using System.Threading.Tasks;
using Tickify.DTOs;
using Tickify.Services;
using System.IO;
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

        public TicketCommentsController(
     ITicketCommentService ticketCommentService,
     UserManager<IdentityUser> userManager,
     ApplicationDbContext dbContext) 
        {
            _ticketCommentService = ticketCommentService;
            _userManager = userManager;
            _dbContext = dbContext; 
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

            var result = comments.Select(c => new {
                c.Id,
                c.Comment,
                c.CreatedAt,
                c.ImageUrl,
                Commenter = !string.IsNullOrWhiteSpace(c.CommenterName) ? c.CommenterName : "Unknown"
            });

            return Ok(result);
        }





        [HttpPost]
        public async Task<IActionResult> AddComment(int ticketId, [FromForm] string comment, [FromForm] IFormFile? image)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (userId == null)
                return Unauthorized("User not found in token.");

            string imageUrl = null;

            if (image != null && image.Length > 0)
            {
                var uploadsPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot/uploads");
                Directory.CreateDirectory(uploadsPath);

                var fileName = $"{Guid.NewGuid()}_{image.FileName}";
                var filePath = Path.Combine(uploadsPath, fileName);

                using (var stream = new FileStream(filePath, FileMode.Create))
                {
                    await image.CopyToAsync(stream);
                }

                var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST") ?? Request.Host.Value;
                imageUrl = $"{Request.Scheme}://{publicHost}/uploads/{fileName}";
            }


            try
            {
                var username = User.FindFirst(ClaimTypes.Name)?.Value ?? "Unknown";
                await _ticketCommentService.AddCommentAsync(ticketId, comment, userId, username, imageUrl);
                return Ok(new { message = "Comment added successfully", imageUrl });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }
    }
}
