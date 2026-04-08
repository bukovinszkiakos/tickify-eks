using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Hosting;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Tickify.Context;
using Tickify.DTOs;
using Tickify.Models;
using Tickify.Repositories;

namespace Tickify.Services
{
    public class TicketService : ITicketService
    {
        private readonly ITicketRepository _ticketRepository;
        private readonly UserManager<IdentityUser> _userManager;
        private readonly ITicketCommentService _ticketCommentService;
        private readonly ApplicationDbContext _dbContext;
        private readonly IHttpContextAccessor _httpContextAccessor;

        public TicketService(
     ITicketRepository ticketRepository,
     UserManager<IdentityUser> userManager,
     ITicketCommentService ticketCommentService,
     ApplicationDbContext dbContext,
     IHttpContextAccessor httpContextAccessor)
        {
            _ticketRepository = ticketRepository;
            _userManager = userManager;
            _ticketCommentService = ticketCommentService;
            _dbContext = dbContext;
            _httpContextAccessor = httpContextAccessor;
        }

        public async Task<IEnumerable<TicketDto>> GetTicketsForUserAsync(string userId, bool isAdmin)
        {
            var tickets = await _ticketRepository.GetAllTicketsAsync();

            var commentCounts = await _dbContext.TicketComments
                .GroupBy(c => c.TicketId)
                .Select(g => new {
                    TicketId = g.Key,
                    Total = g.Count()
                })
                .ToListAsync();

            var userIdString = (userId ?? "").Trim();

            var relevantTicketIds = isAdmin
                ? tickets.Select(t => t.Id).ToList()
                : tickets.Where(t => t.CreatedBy == userId).Select(t => t.Id).ToList();

            var unreadCounts = await _dbContext.TicketComments
                .Where(c => relevantTicketIds.Contains(c.TicketId))
                .Where(c => c.CommentedBy != userIdString)
                .Where(c => !_dbContext.CommentReadStatuses
                    .Any(r => r.CommentId == c.Id && r.UserId == userIdString))
                .GroupBy(c => c.TicketId)
                .Select(g => new {
                    TicketId = g.Key,
                    Unread = g.Count()
                })
                .ToListAsync();

            var assignedUserIds = tickets
                .Where(t => !string.IsNullOrEmpty(t.AssignedTo))
                .Select(t => t.AssignedTo)
                .Distinct()
                .ToList();

            var creatorUserIds = tickets
                .Where(t => !string.IsNullOrEmpty(t.CreatedBy))
                .Select(t => t.CreatedBy)
                .Distinct()
                .ToList();

            var allUserIds = assignedUserIds.Concat(creatorUserIds).Distinct().ToList();

            var userMap = await _dbContext.Users
                .Where(u => allUserIds.Contains(u.Id))
                .ToDictionaryAsync(u => u.Id, u => u.UserName);

            var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST") ?? "localhost:5000";

            var ticketDtos = tickets.Select(t => new TicketDto
            {
                Id = t.Id,
                Title = t.Title,
                Description = t.Description,
                CreatedAt = t.CreatedAt,
                UpdatedAt = t.UpdatedAt,
                Status = t.Status,
                Priority = t.Priority,
                CreatedBy = t.CreatedBy,
                CreatedByName = t.CreatedBy != null && userMap.ContainsKey(t.CreatedBy)
                    ? userMap[t.CreatedBy] : "Unknown",
                AssignedTo = t.AssignedTo,
                AssignedToName = t.AssignedTo != null && userMap.ContainsKey(t.AssignedTo)
                    ? userMap[t.AssignedTo] : null,
                ImageUrl = !string.IsNullOrEmpty(t.ImageUrl) ? $"http://{publicHost}{t.ImageUrl}" : null,
                TotalCommentCount = commentCounts.FirstOrDefault(c => c.TicketId == t.Id)?.Total ?? 0,
                UnreadCommentCount = unreadCounts.FirstOrDefault(u => u.TicketId == t.Id)?.Unread ?? 0
            });

            if (!isAdmin && !string.IsNullOrEmpty(userId))
            {
                ticketDtos = ticketDtos.Where(t => t.CreatedBy == userId);
            }

            return ticketDtos;
        }





        public async Task<TicketDto> GetTicketDtoByIdAsync(int id, string userId, bool isAdmin)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(id);
            if (ticket == null)
                throw new KeyNotFoundException("Ticket not found.");

            var user = await _userManager.FindByIdAsync(userId);
            var isSuperAdmin = user != null && await _userManager.IsInRoleAsync(user, "SuperAdmin");

            var isCreator = ticket.CreatedBy == userId;
            var isAssigned = ticket.AssignedTo == userId;

            if (!(isSuperAdmin || isAdmin || isCreator))
                throw new UnauthorizedAccessException("Not allowed to access this ticket.");

            var createdByName = ticket.CreatedBy != null
                ? (await _dbContext.Users.FindAsync(ticket.CreatedBy))?.UserName
                : "Unknown";

            var assignedToName = ticket.AssignedTo != null
                ? (await _dbContext.Users.FindAsync(ticket.AssignedTo))?.UserName
                : null;

            var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST");
            var fullImageUrl = !string.IsNullOrEmpty(ticket.ImageUrl) && !string.IsNullOrEmpty(publicHost)
                ? $"http://{publicHost}{ticket.ImageUrl}"
                : ticket.ImageUrl;

            return new TicketDto
            {
                Id = ticket.Id,
                Title = ticket.Title,
                Description = ticket.Description,
                CreatedAt = ticket.CreatedAt,
                UpdatedAt = ticket.UpdatedAt,
                Status = ticket.Status,
                Priority = ticket.Priority,
                CreatedBy = ticket.CreatedBy,
                CreatedByName = createdByName,
                AssignedTo = ticket.AssignedTo,
                AssignedToName = assignedToName,
                ImageUrl = fullImageUrl
            };
        }




        public async Task<TicketDto> CreateTicketAsync(
    string title,
    string description,
    string priority,
    string userId,
    bool isAdmin,
    IFormFile? image,
    string scheme,
    string host)
        {
            if (isAdmin)
                throw new UnauthorizedAccessException("Admin users are not allowed to create tickets.");

            string? imageUrl = null;
            string? fullImageUrl = null;

            if (image != null && image.Length > 0)
            {
                var uploadsPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot/uploads");
                Directory.CreateDirectory(uploadsPath);

                var fileName = $"{Guid.NewGuid()}_{Path.GetFileName(image.FileName)}";
                var filePath = Path.Combine(uploadsPath, fileName);

                using var stream = new FileStream(filePath, FileMode.Create);
                await image.CopyToAsync(stream);

                imageUrl = $"/uploads/{fileName}";

                var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST") ?? host;
                fullImageUrl = $"{scheme}://{publicHost}{imageUrl}";
            }

            var ticket = new Ticket
            {
                Title = title,
                Description = description,
                Priority = priority,
                Status = "Open",
                CreatedBy = userId,
                CreatedAt = DateTime.Now,
                UpdatedAt = DateTime.Now,
                ImageUrl = imageUrl
            };

            await _ticketRepository.AddTicketAsync(ticket);
            await _ticketRepository.SaveChangesAsync();



            return new TicketDto
            {
                Id = ticket.Id,
                Title = ticket.Title,
                Description = ticket.Description,
                CreatedAt = ticket.CreatedAt,
                UpdatedAt = ticket.UpdatedAt,
                Status = ticket.Status,
                Priority = ticket.Priority,
                CreatedBy = ticket.CreatedBy,
                AssignedTo = ticket.AssignedTo,
                ImageUrl = imageUrl
            };
        }





        public async Task UpdateTicketAsync(
    int id,
    UpdateTicketDto updateDto,
    string userId,
    bool isAdmin,
    IFormFile? image,
    string scheme,
    string host)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(id);
            if (ticket == null) throw new KeyNotFoundException("Ticket not found.");
            if (!isAdmin && ticket.CreatedBy != userId) throw new UnauthorizedAccessException("Not allowed to update this ticket.");

            var changes = new List<string>();
            string? oldImageUrl = null;
            string? newImageUrl = null;
            bool imageChanged = false;

            if (ticket.Title != updateDto.Title)
            {
                changes.Add($"Title: \"{ticket.Title}\" → \"{updateDto.Title}\"");
                ticket.Title = updateDto.Title;
            }

            if (ticket.Description != updateDto.Description)
            {
                changes.Add($"Description: \"{ticket.Description}\" → \"{updateDto.Description}\"");
                ticket.Description = updateDto.Description;
            }

            if (ticket.Priority != updateDto.Priority)
            {
                changes.Add($"Priority: {ticket.Priority} → {updateDto.Priority}");
                ticket.Priority = updateDto.Priority;
            }

            if (isAdmin && ticket.AssignedTo != updateDto.AssignedTo)
            {
                changes.Add($"Assigned To: {ticket.AssignedTo ?? "None"} → {updateDto.AssignedTo ?? "None"}");
                ticket.AssignedTo = updateDto.AssignedTo;
            }

            if (image != null && image.Length > 0)
            {
                var uploadsPath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot/uploads");
                Directory.CreateDirectory(uploadsPath);

                var fileName = $"{Guid.NewGuid()}_{Path.GetFileName(image.FileName)}";
                var newPath = Path.Combine(uploadsPath, fileName);

                using var stream = new FileStream(newPath, FileMode.Create);
                await image.CopyToAsync(stream);

                var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST") ?? host;

                if (!string.IsNullOrEmpty(ticket.ImageUrl))
                {
                    oldImageUrl = $"{scheme}://{publicHost}{ticket.ImageUrl}";
                }

                ticket.ImageUrl = $"/uploads/{fileName}";
                newImageUrl = $"{scheme}://{publicHost}{ticket.ImageUrl}";
                imageChanged = true;

                changes.Add("🖼️ Image updated.");
            }

            ticket.UpdatedAt = DateTime.Now;
            _ticketRepository.UpdateTicket(ticket);

            if (changes.Any())
            {
                var commentText = "🔄 Ticket updated:\n" + string.Join("\n", changes);
                if (imageChanged && !string.IsNullOrEmpty(newImageUrl))
                {
                    if (!string.IsNullOrEmpty(oldImageUrl))
                        commentText += $"\nOld image: {oldImageUrl}";
                    commentText += $"\nNew image: {newImageUrl}";
                }

                var user = await _userManager.FindByIdAsync(userId);
                await _ticketCommentService.AddCommentAsync(ticket.Id, commentText, userId, user?.UserName ?? "Unknown", null);
            }

            await _ticketRepository.SaveChangesAsync();
        }







        public async Task UpdateTicketStatusAsync(int ticketId, string newStatus, string adminName)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(ticketId);
            if (ticket == null)
                throw new KeyNotFoundException("Ticket not found.");

            var adminId = (_httpContextAccessor.HttpContext?.User.FindFirst(ClaimTypes.NameIdentifier)?.Value ?? "").Trim();

            if (!string.IsNullOrEmpty(ticket.AssignedTo) &&
                !string.Equals(ticket.AssignedTo.Trim(), adminId, StringComparison.OrdinalIgnoreCase))
            {
                throw new UnauthorizedAccessException("Only the assigned admin can update the ticket status.");
            }

            var oldStatus = ticket.Status;
            if (oldStatus == newStatus) return;

            ticket.Status = newStatus;
            ticket.UpdatedAt = DateTime.Now;
            _ticketRepository.UpdateTicket(ticket);

            var commentText = $"🔁 Status changed by admin ({adminName}): {oldStatus} → {newStatus}";
            await _ticketCommentService.AddCommentAsync(
                ticket.Id,
                commentText,
                adminId,
                adminName,
                null
            );

            var creatorId = (ticket.CreatedBy ?? "").Trim();
            if (!string.IsNullOrWhiteSpace(creatorId) &&
                !string.Equals(creatorId, adminId, StringComparison.OrdinalIgnoreCase))
            {
                await _dbContext.Notifications.AddAsync(new Notification
                {
                    UserId = creatorId,
                    CreatedBy = adminId,
                    Message = $"📌 Your ticket \"{ticket.Title}\" status changed to \"{newStatus}\".",
                    TicketId = ticket.Id.ToString(),
                    CreatedAt = DateTime.UtcNow,
                    IsRead = false
                });

                await _dbContext.SaveChangesAsync();
            }
        }








        public async Task DeleteTicketAsync(int id, string userId, bool isAdmin)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(id);
            if (ticket == null)
                throw new KeyNotFoundException("Ticket not found.");

            var creatorId = ticket.CreatedBy?.Trim();
            var isCreator = creatorId == userId.Trim();

            var user = await _userManager.FindByIdAsync(userId);
            var isSuperAdmin = user != null && await _userManager.IsInRoleAsync(user, "SuperAdmin");
            var isAssignedAdmin = ticket.AssignedTo?.Trim() == userId.Trim();

            if (!(isCreator || (isAdmin && (isAssignedAdmin || isSuperAdmin))))
            {
                throw new UnauthorizedAccessException("Not allowed to delete this ticket.");
            }

            var oldNotifications = _dbContext.Notifications
                .Where(n => n.TicketId == ticket.Id.ToString());
            _dbContext.Notifications.RemoveRange(oldNotifications);

            _ticketRepository.DeleteTicket(ticket);

            if (!isCreator && isAdmin && creatorId != null)
            {
                await _dbContext.Notifications.AddAsync(new Notification
                {
                    UserId = creatorId,
                    CreatedBy = userId,
                    Message = $"❌ Your ticket \"{ticket.Title}\" was deleted by an admin.",
                    TicketId = null,
                    CreatedAt = DateTime.UtcNow,
                    IsRead = false
                });
                await _dbContext.SaveChangesAsync();
            }

            await _ticketRepository.SaveChangesAsync();
        }



        public async Task<bool> DeleteTicketImageAsync(int ticketId, string userId, bool isAdmin)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(ticketId);
            if (ticket == null)
            {
                throw new KeyNotFoundException("Ticket not found.");
            }

            if (!isAdmin && ticket.CreatedBy != userId)
            {
                throw new UnauthorizedAccessException("Not allowed to delete this ticket image.");
            }

            if (string.IsNullOrEmpty(ticket.ImageUrl))
            {
                return false;
            }

            try
            {
                var imagePath = Path.Combine(Directory.GetCurrentDirectory(), "wwwroot", ticket.ImageUrl.TrimStart('/'));

                if (File.Exists(imagePath))
                {
                    File.Delete(imagePath);
                }

                ticket.ImageUrl = null;
                _ticketRepository.UpdateTicket(ticket);
                await _ticketRepository.SaveChangesAsync();

                return true;
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error deleting image: {ex.Message}");
                return false;
            }
        }

        public async Task<IEnumerable<TicketDto>> GetTicketsForAdminAsync(string adminUserId, bool isSuperAdmin)
        {
            var tickets = await _ticketRepository.GetAllTicketsAsync();

            var userIdString = adminUserId.Trim();
            var allTicketIds = tickets.Select(t => t.Id).ToList();

            var commentCounts = await _dbContext.TicketComments
                .GroupBy(c => c.TicketId)
                .Select(g => new {
                    TicketId = g.Key,
                    Total = g.Count()
                }).ToListAsync();

            var unreadCounts = await _dbContext.TicketComments
                .Where(c => allTicketIds.Contains(c.TicketId))
                .Where(c => c.CommentedBy != userIdString && c.CommentedBy != "admin-system")
                .Where(c => !_dbContext.CommentReadStatuses
                    .Any(r => r.CommentId == c.Id && r.UserId == userIdString))
                .GroupBy(c => c.TicketId)
                .Select(g => new {
                    TicketId = g.Key,
                    Unread = g.Count()
                }).ToListAsync();

            var assignedUserIds = tickets.Where(t => !string.IsNullOrEmpty(t.AssignedTo))
                                          .Select(t => t.AssignedTo)
                                          .Distinct()
                                          .ToList();

            var creatorUserIds = tickets
                .Where(t => !string.IsNullOrEmpty(t.CreatedBy))
                .Select(t => t.CreatedBy)
                .Distinct()
                .ToList();

            var creatorUserMap = await _dbContext.Users
                .Where(u => creatorUserIds.Contains(u.Id))
                .ToDictionaryAsync(u => u.Id, u => u.UserName);

            var assignedUserMap = await _dbContext.Users
                .Where(u => assignedUserIds.Contains(u.Id))
                .ToDictionaryAsync(u => u.Id, u => u.UserName);

            var publicHost = Environment.GetEnvironmentVariable("PUBLIC_HOST") ?? "localhost:5000";

            var ticketDtos = tickets.Select(t => new TicketDto
            {
                Id = t.Id,
                Title = t.Title,
                Description = t.Description,
                CreatedAt = t.CreatedAt,
                UpdatedAt = t.UpdatedAt,
                Status = t.Status,
                Priority = t.Priority,
                CreatedBy = t.CreatedBy,
                CreatedByName = t.CreatedBy != null && creatorUserMap.ContainsKey(t.CreatedBy)
                    ? creatorUserMap[t.CreatedBy] : "Unknown",
                AssignedTo = t.AssignedTo,
                AssignedToName = t.AssignedTo != null && assignedUserMap.ContainsKey(t.AssignedTo)
                    ? assignedUserMap[t.AssignedTo] : null,
                ImageUrl = !string.IsNullOrEmpty(t.ImageUrl) ? $"http://{publicHost}{t.ImageUrl}" : null,
                TotalCommentCount = commentCounts.FirstOrDefault(c => c.TicketId == t.Id)?.Total ?? 0,
                UnreadCommentCount = unreadCounts.FirstOrDefault(u => u.TicketId == t.Id)?.Unread ?? 0
            });

            return ticketDtos;
        }





        public async Task MarkTicketCommentsAsReadAsync(int ticketId, string userId)
        {
            var userIdString = userId.Trim();

            var unreadCommentIds = await _dbContext.TicketComments
                .Where(c => c.TicketId == ticketId)
                .Where(c => c.CommentedBy != userIdString)
                .Where(c => !_dbContext.CommentReadStatuses
                    .Any(r => r.CommentId == c.Id && r.UserId == userIdString))
                .Select(c => c.Id)
                .ToListAsync();

            var newStatuses = unreadCommentIds.Select(id => new CommentReadStatus
            {
                CommentId = id,
                UserId = userIdString,
                SeenAt = DateTime.UtcNow
            }).ToList();

            if (newStatuses.Any())
            {
                _dbContext.CommentReadStatuses.AddRange(newStatuses);
                await _dbContext.SaveChangesAsync();
            }
        }


        public async Task AssignTicketToAdminAsync(int ticketId, string adminUserId)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(ticketId);
            if (ticket == null)
                throw new KeyNotFoundException("Ticket not found.");

            ticket.AssignedTo = adminUserId;
            ticket.UpdatedAt = DateTime.UtcNow;

            _ticketRepository.UpdateTicket(ticket);
            await _ticketRepository.SaveChangesAsync();
        }

        public async Task ReassignTicketAsync(int ticketId, string? newAdminId, string currentUserId)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(ticketId);
            if (ticket == null)
            {
                throw new KeyNotFoundException("Ticket not found.");
            }

            if (string.IsNullOrEmpty(ticket.AssignedTo))
            {
                ticket.AssignedTo = newAdminId;
                ticket.UpdatedAt = DateTime.UtcNow;

                _ticketRepository.UpdateTicket(ticket);
                await _ticketRepository.SaveChangesAsync();
                return;
            }

            var assignedToTrimmed = (ticket.AssignedTo ?? "").Trim();
            var currentUserTrimmed = (currentUserId ?? "").Trim();

            if (!string.Equals(assignedToTrimmed, currentUserTrimmed, StringComparison.OrdinalIgnoreCase) &&
                !await _userManager.IsInRoleAsync(await _userManager.FindByIdAsync(currentUserId), "SuperAdmin"))
            {
                throw new UnauthorizedAccessException("Only the assigned admin or a SuperAdmin can reassign this ticket.");
            }

            ticket.AssignedTo = string.IsNullOrWhiteSpace(newAdminId) ? null : newAdminId;
            ticket.UpdatedAt = DateTime.UtcNow;

            _ticketRepository.UpdateTicket(ticket);
            await _ticketRepository.SaveChangesAsync();
        }








    }
}
