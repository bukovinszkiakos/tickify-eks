using System.Collections.Generic;
using System.Threading.Tasks;
using Tickify.Models;
using Tickify.Repositories;
using Tickify.DTOs;
using Tickify.Context;
using Microsoft.EntityFrameworkCore;

namespace Tickify.Services
{
    public class TicketCommentService : ITicketCommentService
    {
        private readonly ITicketCommentRepository _commentRepository;
        private readonly ITicketRepository _ticketRepository;
        private readonly ApplicationDbContext _dbContext; 

        public TicketCommentService(
            ITicketCommentRepository commentRepository,
            ITicketRepository ticketRepository,
            ApplicationDbContext dbContext)
        {
            _commentRepository = commentRepository;
            _ticketRepository = ticketRepository;
            _dbContext = dbContext;
        }

        public async Task<IEnumerable<TicketComment>> GetCommentsByTicketIdAsync(int ticketId)
        {
            return await _commentRepository.GetCommentsByTicketIdAsync(ticketId);
        }

        public async Task AddCommentAsync(int ticketId, string comment, string userId, string username, string? imageUrl)
        {
            var ticket = await _ticketRepository.GetTicketByIdAsync(ticketId);
            if (ticket == null)
                throw new KeyNotFoundException("Ticket not found.");

            var newComment = new TicketComment
            {
                TicketId = ticketId,
                Comment = comment,
                CommentedBy = userId,
                CreatedAt = DateTime.Now,
                ImageUrl = imageUrl,
                CommenterName = username
            };

            await _commentRepository.AddCommentAsync(newComment);
            await _commentRepository.SaveChangesAsync();

            var notifications = new List<Notification>();

            var previousCommenters = await _dbContext.TicketComments
                .Where(c => c.TicketId == ticketId && c.CommentedBy != userId)
                .Select(c => c.CommentedBy)
                .Distinct()
                .ToListAsync();

            int.TryParse(userId, out int parsedUserId);

            var statusChangers = await _dbContext.TicketHistories
                .Where(h => h.TicketId == ticketId && h.ChangedBy != userId.Trim())
                .Select(h => h.ChangedBy)
                .Distinct()
                .ToListAsync();


            var commenterId = (userId ?? "").Trim();
            var relatedAdmins = previousCommenters
                .Concat(statusChangers)
                .Distinct()
                .Where(adminId =>
                    adminId != ticket.CreatedBy &&
                    !string.Equals(adminId?.Trim(), commenterId, StringComparison.OrdinalIgnoreCase)) 
                .ToList();


            foreach (var adminId in relatedAdmins)
            {
                notifications.Add(new Notification
                {
                    UserId = adminId,
                    CreatedBy = userId, 
                    Message = $"💬 {username} commented on ticket \"{ticket.Title}\"",
                    TicketId = ticket.Id.ToString(),
                    CreatedAt = DateTime.UtcNow,
                    IsRead = false
                });
            }

            var creatorId = (ticket.CreatedBy ?? "").Trim();

            if (!string.IsNullOrEmpty(creatorId) &&
                !string.IsNullOrEmpty(commenterId) &&
                !string.Equals(creatorId, commenterId, StringComparison.OrdinalIgnoreCase))
            {
                notifications.Add(new Notification
                {
                    UserId = creatorId,
                    CreatedBy = commenterId,
                    Message = $"💬 {username} commented on your ticket \"{ticket.Title}\"",
                    TicketId = ticket.Id.ToString(),
                    CreatedAt = DateTime.UtcNow,
                    IsRead = false
                });
            }


            if (notifications.Any())
            {
                await _dbContext.Notifications.AddRangeAsync(notifications);
                await _dbContext.SaveChangesAsync();
            }
        }

    }
}