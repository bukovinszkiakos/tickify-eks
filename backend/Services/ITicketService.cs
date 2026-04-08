using Tickify.DTOs;
using Tickify.Models;

namespace Tickify.Services
{
    public interface ITicketService
    {
        Task<IEnumerable<TicketDto>> GetTicketsForUserAsync(string userId, bool isAdmin);

        Task<TicketDto> GetTicketDtoByIdAsync(int id, string userId, bool isAdmin);

        Task<TicketDto> CreateTicketAsync(string title, string description, string priority, string userId, bool isAdmin, IFormFile? image, string scheme, string host);

        Task UpdateTicketAsync(
            int id,
            UpdateTicketDto updateDto,
            string userId,
            bool isAdmin,
            IFormFile? image,
            string scheme,
            string host);

        Task DeleteTicketAsync(int id, string userId, bool isAdmin);

        Task<bool> DeleteTicketImageAsync(int ticketId, string userId, bool isAdmin);

        Task UpdateTicketStatusAsync(int ticketId, string newStatus, string changedByName);

        Task<IEnumerable<TicketDto>> GetTicketsForAdminAsync(string adminUserId, bool isSuperAdmin);

        Task MarkTicketCommentsAsReadAsync(int ticketId, string userId);

        Task AssignTicketToAdminAsync(int ticketId, string adminUserId);

        Task ReassignTicketAsync(int ticketId, string? newAdminId, string changedByAdminId);


    }
}
