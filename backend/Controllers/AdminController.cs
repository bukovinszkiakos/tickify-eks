using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Linq;
using System.Threading.Tasks;
using Tickify.Services;
using Tickify.DTOs;
using Microsoft.Extensions.Hosting;
using System.Security.Claims;

namespace Tickify.Controllers
{
    [ApiController]
    [Route("api/admin")]
    public class AdminController : ControllerBase
    {
        private readonly UserManager<IdentityUser> _userManager;
        private readonly ITicketService _ticketService;

        public AdminController(UserManager<IdentityUser> userManager, ITicketService ticketService)
        {
            _userManager = userManager;
            _ticketService = ticketService;
        }
        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpGet("users")]
        public async Task<IActionResult> GetUsers()
        {
            var users = await _userManager.Users.ToListAsync();

            var result = new List<object>();

            foreach (var user in users)
            {
                var roles = await _userManager.GetRolesAsync(user);

                result.Add(new
                {
                    user.Id,
                    user.UserName,
                    user.Email,
                    Roles = roles 
                });
            }

            return Ok(result);
        }

        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpDelete("users/{userId}")]
        public async Task<IActionResult> DeleteUser(string userId)
        {
            var user = await _userManager.FindByIdAsync(userId);
            if (user == null)
                return NotFound("User not found");

            var roles = await _userManager.GetRolesAsync(user);

            if (roles.Contains("SuperAdmin") && User.IsInRole("Admin") && !User.IsInRole("SuperAdmin"))
                return Forbid("Admins cannot delete SuperAdmins.");

            var activeStatuses = new[] { "Open", "In Progress" };
            var hasActiveTickets = await _ticketService
                .GetTicketsForUserAsync(userId, false);

            if (hasActiveTickets.Any(t => activeStatuses.Contains(t.Status)))
                return BadRequest("Cannot delete user: there are still active tickets.");

            var closedTickets = hasActiveTickets.Where(t => t.Status == "Resolved" || t.Status == "Closed").ToList();
            foreach (var ticket in closedTickets)
            {
                await _ticketService.DeleteTicketAsync(ticket.Id, userId, isAdmin: true);
            }

            var result = await _userManager.DeleteAsync(user);
            if (!result.Succeeded)
                return StatusCode(500, "Failed to delete user.");

            return Ok(new { message = "User and all resolved/closed tickets deleted successfully." });
        }



        [Authorize(Roles = "SuperAdmin")]
        [HttpPost("users/{userId}/role/{role}")]
        public async Task<IActionResult> AssignRole(string userId, string role)
        {
            var user = await _userManager.FindByIdAsync(userId);
            if (user == null) return NotFound("User not found");

            var currentRoles = await _userManager.GetRolesAsync(user);
            var isCurrentlyAdmin = currentRoles.Contains("Admin") || currentRoles.Contains("SuperAdmin");
            var willBeAdmin = role == "Admin" || role == "SuperAdmin";

            var removeResult = await _userManager.RemoveFromRolesAsync(user, currentRoles);
            if (!removeResult.Succeeded) return BadRequest(removeResult.Errors);

            var addResult = await _userManager.AddToRoleAsync(user, role);
            if (!addResult.Succeeded) return BadRequest(addResult.Errors);

            if (willBeAdmin && !isCurrentlyAdmin)
            {
                var userTickets = await _ticketService.GetTicketsForUserAsync(userId, false);

                foreach (var ticket in userTickets)
                {
                    await _ticketService.DeleteTicketAsync(ticket.Id, userId, isAdmin: true);
                }
            }

            return Ok(new { message = $"User {user.UserName} role set to {role}" });
        }


        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpGet("tickets")]
        public async Task<IActionResult> GetAllTickets([FromQuery] string status = "", [FromQuery] string priority = "")
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            var user = await _userManager.FindByIdAsync(userId);
            var isSuperAdmin = await _userManager.IsInRoleAsync(user, "SuperAdmin");

            var tickets = await _ticketService.GetTicketsForAdminAsync(userId, isSuperAdmin);

            if (!string.IsNullOrEmpty(status))
                tickets = tickets.Where(t => t.Status == status);

            if (!string.IsNullOrEmpty(priority))
                tickets = tickets.Where(t => t.Priority == priority);

            return Ok(tickets);
        }


        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpPut("tickets/{id}/status/{newStatus}")]
        public async Task<IActionResult> UpdateTicketStatus(int id, string newStatus)
        {
            var allowedStatuses = new[] { "Open", "In Progress", "Resolved", "Closed" };

            if (!allowedStatuses.Contains(newStatus))
            {
                return BadRequest($"Invalid status. Allowed statuses: {string.Join(", ", allowedStatuses)}");
            }

            try
            {
                var adminName = User.Identity?.Name ?? "Admin";
                await _ticketService.UpdateTicketStatusAsync(id, newStatus, adminName);
                return Ok(new { message = "Ticket status updated" });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }


        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpGet("dashboard")]
        public async Task<IActionResult> GetDashboardStats()
        {
            var tickets = await _ticketService.GetTicketsForUserAsync(null, true);

            var openTickets = tickets.Count(t => t.Status == "Open");
            var inProgressTickets = tickets.Count(t => t.Status == "In Progress");
            var resolvedTickets = tickets.Count(t => t.Status == "Resolved");
            var closedTickets = tickets.Count(t => t.Status == "Closed");

            return Ok(new
            {
                openTickets,
                inProgressTickets,
                resolvedTickets,
                closedTickets,
                totalTickets = tickets.Count()
            });
        }

        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpPost("tickets/{ticketId}/mark-comments-read")]
        public async Task<IActionResult> MarkCommentsAsRead(int ticketId)
        {
            var userId = User.FindFirst(System.Security.Claims.ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId))
                return Unauthorized();

            await _ticketService.MarkTicketCommentsAsReadAsync(ticketId, userId);
            return Ok(new { message = "Comments marked as read." });
        }


        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpPost("tickets/{ticketId}/assign-to-me")]
        public async Task<IActionResult> AssignToMe(int ticketId)
        {
            var userId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(userId)) return Unauthorized();

            try
            {
                await _ticketService.AssignTicketToAdminAsync(ticketId, userId);
                return Ok(new { message = "Ticket successfully assigned to you." });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(ex.Message);
            }
        }

        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpPost("tickets/{ticketId}/assign")]
        public async Task<IActionResult> ReassignTicket(int ticketId, [FromBody] AssignTicketDto dto)
        {
            var adminId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(adminId)) return Unauthorized();

            await _ticketService.AssignTicketToAdminAsync(ticketId, dto.AdminUserId);
            return Ok(new { message = "Ticket reassigned successfully." });
        }

        [Authorize(Roles = "Admin,SuperAdmin")]
        [HttpPost("tickets/{ticketId}/reassign")]
        public async Task<IActionResult> ReassignTicket(int ticketId, [FromBody] ReassignTicketDto dto)
        {
            var currentUserId = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            if (string.IsNullOrEmpty(currentUserId))
                return Unauthorized();

            try
            {
                await _ticketService.ReassignTicketAsync(ticketId, dto.NewAdminId, currentUserId);
                return Ok(new { message = "Ticket reassigned successfully." });
            }
            catch (KeyNotFoundException ex)
            {
                return NotFound(new { message = "Ticket not found.", error = ex.Message });
            }
            catch (Exception ex)
            {
                return StatusCode(500, new { message = "Internal Server Error.", error = ex.Message });
            }

        }




    }
}
