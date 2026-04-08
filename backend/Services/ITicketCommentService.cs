using Tickify.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace Tickify.Services
{
    public interface ITicketCommentService
    {
        Task<IEnumerable<TicketComment>> GetCommentsByTicketIdAsync(int ticketId);
        Task AddCommentAsync(int ticketId, string comment, string userId, string username, string imageUrl);
    }
}
