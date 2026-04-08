using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Claims;
using Tickify.Context;
using Tickify.DTOs;

namespace Tickify.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UserController : ControllerBase
    {
        private readonly ApplicationDbContext _dbContext;

        public UserController(ApplicationDbContext dbContext)
        {
            _dbContext = dbContext;
        }

        [Authorize]
        [HttpGet("notifications")]
        public async Task<IActionResult> GetNotifications()
        {
            var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);

            var notifications = await _dbContext.Notifications
                .Where(n => n.UserId == userId && (n.CreatedBy == null || n.CreatedBy != userId))
                .OrderByDescending(n => n.CreatedAt)
                .Take(10)
                .ToListAsync();

            var notificationDtos = notifications.Select(n => new NotificationDto
            {
                Id = n.Id,
                UserId = n.UserId,
                Message = n.Message,
                TicketId = n.TicketId,
                CreatedAt = n.CreatedAt,
                IsRead = n.IsRead,
                IsTicketDeleted = string.IsNullOrEmpty(n.TicketId)
                    || !_dbContext.Tickets.Any(t => t.Id.ToString() == n.TicketId) 
            });

            return Ok(notificationDtos);
        }




        [Authorize]
        [HttpPost("notifications/{id}/read")]
        public async Task<IActionResult> MarkAsRead(int id)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var notification = await _dbContext.Notifications
                .FirstOrDefaultAsync(n => n.Id == id && n.UserId == userId);

            if (notification == null)
            {
                return NotFound();
            }

            notification.IsRead = true;
            await _dbContext.SaveChangesAsync();

            return Ok(new { success = true }); 
        }


        [HttpDelete("notifications/{id}")]
        public async Task<IActionResult> DeleteNotification(int id)
        {
            var notification = await _dbContext.Notifications.FindAsync(id);
            if (notification == null) return NotFound();

            _dbContext.Notifications.Remove(notification);
            await _dbContext.SaveChangesAsync();

            return Ok(new { success = true });
        }








    }
}
